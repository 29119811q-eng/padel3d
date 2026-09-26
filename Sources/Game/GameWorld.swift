import SceneKit

enum Phase: Int, Codable { case serve, rally, pause }
enum PointKind: String, Codable { case point, game, set, match }

enum GameEvent {
    case hit(quality: Float, slot: Int)
    case bounce(side: Team)
    case wall
    case point(wonBy: Team, kind: PointKind, score: ScoreSnapshot)
    case matchOver(winner: Team, score: ScoreSnapshot)
}

/// Сердце игры: сцена, физика мяча, розыгрыш, счёт. Работает в авторитетном
/// режиме (офлайн/хост) и в режиме клиента (только рендер по снапшотам).
final class GameWorld: NSObject, SCNPhysicsContactDelegate {
    let scene = SCNScene()
    let authority: Bool
    let avatars: [PlayerAvatar]
    var pos: [SCNVector3]
    var input: [PlayerInput]
    var isBot: [Bool]
    var ownSlot: Int = 0 { didSet { for a in avatars { a.setOwn(a.slot == ownSlot) } } }

    let ballNode: SCNNode
    let camera = SCNNode()
    var score = ScoreKeeper()

    private(set) var phase = Phase.serve
    private var phaseT: Float = 0
    private(set) var serverSlot = 0
    private var gameIndex = 0
    private(set) var lastHitter: Team = .b
    private var lastBounce: Team?
    private(set) var lastWinner: Team = .a
    private(set) var lastKind: PointKind = .point
    private(set) var pointSeq = 0
    private var serveFaults = 0
    private var serveT: Float = 0
    private var restT: Float = 0
    private var swungFlags = [false, false, false, false]
    private var bots: [BotBrain?] = [nil, nil, nil, nil]

    var onEvent: ((GameEvent) -> Void)?

    init(authority: Bool) {
        self.authority = authority
        avatars = (0..<4).map { PlayerAvatar(slot: $0) }
        pos = (0..<4).map { homePosition(slot: $0) }
        input = (0..<4).map { _ in PlayerInput() }
        isBot = [true, true, true, true]

        scene.physicsWorld.gravity = SCNVector3(0, -CourtSpec.g, 0)
        buildCourt(into: scene)
        ballNode = makeBall()
        super.init()

        scene.rootNode.addChildNode(ballNode)
        for a in avatars { scene.rootNode.addChildNode(a.root) }
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 70
        scene.rootNode.addChildNode(camera)
        scene.physicsWorld.contactDelegate = self
        if !authority { ballNode.physicsBody = nil }
        startPoint()
    }

    // MARK: Управление слотами

    func setHuman(_ human: Bool, slot: Int) {
        isBot[slot] = !human
        if human { bots[slot] = nil }
    }

    func applyRemoteMeta(phase: Int, serverSlot: Int, pointSeq: Int,
                         lastWinner: Int, lastKind: String) {
        if let p = Phase(rawValue: phase) { self.phase = p }
        self.serverSlot = serverSlot
        self.pointSeq = pointSeq
        if let w = Team(rawValue: lastWinner) { self.lastWinner = w }
        if let k = PointKind(rawValue: lastKind) { self.lastKind = k }
    }

    // MARK: Цикл

    func update(_ dt: Float) {
        if authority, phase == .serve {
            serveT += dt
            if serveT > 8 { awardPoint(to: teamOf(slot: serverSlot).other) }
        }
        if phase == .pause {
            phaseT -= dt
            if phaseT <= 0, !score.over { startPoint() }
        }
        if authority {
            for s in 0..<4 where isBot[s] {
                if bots[s] == nil { bots[s] = BotBrain(slot: s) }
                input[s] = bots[s]!.update(world: self, dt: dt)
            }
        }
        for s in 0..<4 {
            var v = SCNVector3(input[s].dx, 0, input[s].dz)
            let l = sqrtf(v.x * v.x + v.z * v.z)
            if l > 1 { v.x /= l; v.z /= l }
            var p = pos[s]
            p.x = clamp(p.x + v.x * CourtSpec.speed * dt, -4.55, 4.55)
            p.z = clampHalfZ(p.z + v.z * CourtSpec.speed * dt, sgn: teamOf(slot: s).sign)
            pos[s] = p
            let av = avatars[s]
            av.root.position = p
            av.setMoving(l, dt: dt)
            av.update(dt: dt)
            av.root.eulerAngles.y = teamOf(slot: s).sign > 0 ? 0 : .pi
        }
        if authority {
            processSwings()
            updateBallState(dt)
        }
        updateCamera()
    }

    private func updateCamera() {
        guard (0..<4).contains(ownSlot) else { return }
        let av = avatars[ownSlot]
        let sgn = teamOf(slot: ownSlot).sign
        camera.position = av.headWorld
        camera.eulerAngles = SCNVector3(-0.10, sgn > 0 ? 0 : .pi, 0)
    }

    // MARK: Удары

    private func processSwings() {
        for s in 0..<4 {
            guard let sw = input[s].swing else { continue }
            input[s].swing = nil
            guard phase != .pause else { continue }
            swungFlags[s] = true
            let bp = ballNode.position
            let d = dist3(bp, avatars[s].racketWorld)
            let bv = ballNode.physicsBody?.velocity ?? SCNVector3Zero
            let toPlayer = SCNVector3(pos[s].x - bp.x, 0, pos[s].z - bp.z)
            let approaching = (bv.x * toPlayer.x + bv.z * toPlayer.z) > 0
            guard d < CourtSpec.reach, approaching else { continue }
            hitBall(slot: s, swing: sw, distance: d)
        }
    }

    private func hitBall(slot: Int, swing: Swing, distance: Float) {
        let sgn = teamOf(slot: slot).sign
        let quality = clamp(1.15 - distance / CourtSpec.reach, 0.3, 1)
        let err = 1 - quality
        var apex: Float
        var depth: Float
        var power = swing.power

        switch swing.type {
        case .smash:
            if ballNode.position.y < 1.9 { apex = 0.7; depth = 6.5 }
            else { apex = 0.25; depth = 8.6; power = min(1, power + 0.25) }
        case .lob: apex = 3.0; depth = 8.8
        case .volley: apex = 0.45; depth = 4.2
        case .drive: apex = 0.8; depth = 7.2
        }

        let aimX = clamp(swing.aim, -1, 1) * 3.6 + Float.random(in: -1...1) * err * 2.2
        let target = SCNVector3(clamp(aimX, -4.6, 4.6), 0.1, -sgn * depth)
        let vel = velocityForShot(from: ballNode.position, target: target,
                                  apex: apex + err * Float.random(in: -0.3...0.5))
        let pw = 0.85 + 0.3 * power
        ballNode.physicsBody?.velocity = SCNVector3(vel.x * pw, vel.y, vel.z * pw)
        lastHitter = teamOf(slot: slot)
        lastBounce = nil
        restT = 0
        if phase == .serve { phase = .rally }
        avatars[slot].triggerSwing()
        onEvent?(.hit(quality: quality, slot: slot))
    }

    // MARK: Мяч вне игры / покой

    private func updateBallState(_ dt: Float) {
        guard phase != .pause else { return }
        if ballNode.position.y > 4.35 {
            awardPoint(to: lastHitter.other)   // ушёл выше ограждения — аут
            return
        }
        let v = ballNode.physicsBody?.velocity ?? SCNVector3Zero
        if ballNode.position.y < 0.12,
           sqrtf(v.x * v.x + v.y * v.y + v.z * v.z) < 0.35 {
            restT += dt
            if restT > 1.0 { awardPoint(to: lastHitter) }
        } else {
            restT = 0
        }
    }

    // MARK: Контакты физики

    func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
        guard authority else { return }
        let maskA = contact.nodeA.physicsBody?.categoryBitMask ?? 0
        let isABall = maskA == PhysCat.ball
        let otherMask = isABall ? (contact.nodeB.physicsBody?.categoryBitMask ?? 0) : maskA
        let ball = isABall ? contact.nodeA : contact.nodeB
        guard ball == ballNode else { return }

        if otherMask == PhysCat.floor {
            handleFloorContact(at: contact.contactPoint)
        } else if otherMask == PhysCat.net {
            let v = ball.physicsBody?.velocity ?? SCNVector3Zero
            if phase == .rally, (v.z > 0) == (lastHitter == .a) {
                awardPoint(to: lastHitter.other)   // не пересёк сетку
            }
        } else if otherMask == PhysCat.wall {
            onEvent?(.wall)
        }
    }

    private func handleFloorContact(at p: SCNVector3) {
        let side: Team = p.z >= 0 ? .a : .b
        if phase == .serve {
            if side == teamOf(slot: serverSlot) {
                serveFaults += 1
                if serveFaults >= 2 {
                    awardPoint(to: teamOf(slot: serverSlot).other)
                } else {
                    startPoint()   // повторная подача
                }
            } else {
                phase = .rally
                lastBounce = side
            }
            return
        }
        let inX = abs(p.x) <= 5.0, inZ = abs(p.z) <= 10.0
        if !inX || !inZ {
            awardPoint(to: lastHitter.other)   // аут
            return
        }
        if let lb = lastBounce, lb == side {
            awardPoint(to: side.other)         // два отскока — очко сопернику
        } else {
            lastBounce = side
            onEvent?(.bounce(side: side))
        }
    }

    // MARK: Очки и подача

    func awardPoint(to t: Team) {
        guard phase != .pause else { return }
        pointSeq += 1
        let kind = score.point(wonBy: t)
        lastWinner = t
        lastKind = kind
        phase = .pause
        phaseT = 1.7
        if kind == .match {
            onEvent?(.matchOver(winner: t, score: score.snapshot))
        } else {
            onEvent?(.point(wonBy: t, kind: kind, score: score.snapshot))
        }
        if kind != .point {
            gameIndex += 1
            serverSlot = (score.serving == .a ? 0 : 2) + (gameIndex % 2)
        }
    }

    func startPoint() {
        phase = .serve
        serveFaults = 0
        serveT = 0
        lastBounce = nil
        restT = 0
        guard authority else { return }
        let sgn = teamOf(slot: serverSlot).sign
        let sp = pos[serverSlot]
        ballNode.physicsBody?.velocity = SCNVector3Zero
        ballNode.position = SCNVector3(sp.x, 1.6, sp.z - sgn * 0.5)
        ballNode.physicsBody?.velocity = SCNVector3(0, 2.2, -sgn * 0.8)   // подброс
    }

    // MARK: Снапшоты

    func makeSnapshot() -> Snapshot {
        let snap = Snapshot(
            ball: Vec3(ballNode.presentation.position),
            ballVel: Vec3(ballNode.physicsBody?.velocity ?? SCNVector3Zero),
            players: pos.map { Vec3($0) },
            score: score.snapshot,
            serverSlot: serverSlot,
            phase: phase.rawValue,
            pointSeq: pointSeq,
            lastWinner: lastWinner.rawValue,
            lastKind: lastKind.rawValue,
            swung: swungFlags
        )
        swungFlags = [false, false, false, false]
        return snap
    }

    func triggerRemoteSwing(slot: Int) { avatars[slot].triggerSwing() }
}
