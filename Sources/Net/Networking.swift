import MultipeerConnectivity
import SceneKit
import UIKit

// MARK: - Транспорт

struct Envelope: Codable {
    var kind: String
    var payload: Data
}

func pack<T: Encodable>(_ kind: String, _ v: T) -> Data? {
    guard let p = try? JSONEncoder().encode(v) else { return nil }
    return try? JSONEncoder().encode(Envelope(kind: kind, payload: p))
}

final class NetSession: NSObject, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate {
    static let serviceType = "padel3d"

    private let peerID = MCPeerID(displayName: UIDevice.current.name)
    let session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?

    var onData: ((Data, MCPeerID) -> Void)?
    var onPeersChange: (() -> Void)?
    var onDisconnect: ((MCPeerID) -> Void)?

    override init() {
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        session.delegate = self
    }

    func host() {
        advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil,
                                               serviceType: NetSession.serviceType)
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
    }

    func stopHosting() { advertiser?.stopAdvertisingPeer() }

    func send(_ data: Data, reliable: Bool = true) {
        guard !session.connectedPeers.isEmpty else { return }
        try? session.send(data, toPeers: session.connectedPeers,
                          with: reliable ? .reliable : .unreliable)
    }

    // MARK: MCSessionDelegate

    func session(_ session: MCSession, peer peerID: MCPeerID,
                 didChange state: MCSessionState) {
        DispatchQueue.main.async { [weak self] in
            self?.onPeersChange?()
            if state == .notConnected { self?.onDisconnect?(peerID) }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        DispatchQueue.main.async { [weak self] in self?.onData?(data, peerID) }
    }

    func session(_ session: MCSession, didReceive stream: InputStream,
                 withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
    func session(_ session: MCSession, didReceiveCertificate certificate: [Any]?,
                 fromPeer peerID: MCPeerID, certificateHandler: @escaping (Bool) -> Void) {
        certificateHandler(true)
    }

    // MARK: MCNearbyServiceAdvertiserDelegate

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }
}

// MARK: - Хост: авторитетная симуляция, рассадка игроков, замена на ботов

final class HostController: NSObject, GameControlling, SCNSceneRendererDelegate {
    let world: GameWorld
    let view: SwingView
    let net: NetSession

    var onEvent: ((GameEvent) -> Void)?
    var onStatus: ((String) -> Void)?

    private var slotsByPeer: [String: Int] = [:]
    private var timer: Timer?
    private var lastT: TimeInterval = 0

    init(net: NetSession) {
        self.net = net
        world = GameWorld(authority: true)
        view = SwingView()
        super.init()
        world.ownSlot = 0
        world.setHuman(true, slot: 0)
        setupView()
        net.host()
        net.onPeersChange = { [weak self] in self?.syncPeers() }
        net.onData = { [weak self] d, p in self?.handleData(d, from: p) }
        net.onDisconnect = { [weak self] p in self?.peerLeft(p) }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            self?.broadcast()
        }
    }

    private func setupView() {
        view.scene = world.scene
        view.delegate = self
        view.isPlaying = true
        view.allowsCameraControl = false
        view.preferredFramesPerSecond = 60
        view.backgroundColor = .black
        view.ballInfo = { [weak self] in
            guard let w = self?.world else { return (1, 99) }
            let d = dist3(w.ballNode.position, SCNVector3(w.pos[0].x, 1.3, w.pos[0].z))
            return (w.ballNode.position.y, d)
        }
        view.onSwing = { [weak self] sw in
            self?.world.input[0].swing = sw
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        world.onEvent = { [weak self] e in self?.onEvent?(e) }
    }

    // MARK: Слоты

    private func syncPeers() {
        let connected = Set(net.session.connectedPeers.map { $0.displayName })
        for name in connected where slotsByPeer[name] == nil {
            if let free = (1...3).first(where: { world.isBot[$0] }) {
                slotsByPeer[name] = free
                world.setHuman(true, slot: free)
                if let peer = net.session.connectedPeers.first(where: { $0.displayName == name }),
                   let d = pack("welcome", free) {
                    try? net.session.send(d, toPeers: [peer], with: .reliable)
                }
            }
        }
        onStatus?("Игроков: \(connected.count + 1)/4")
    }

    private func peerLeft(_ peer: MCPeerID) {
        if let slot = slotsByPeer.removeValue(forKey: peer.displayName) {
            world.setHuman(false, slot: slot)   // бот заходит на замену
        }
    }

    private func handleData(_ data: Data, from peer: MCPeerID) {
        guard let env = try? JSONDecoder().decode(Envelope.self, from: data),
              let slot = slotsByPeer[peer.displayName] else { return }
        if env.kind == "input",
           let i = try? JSONDecoder().decode(PlayerInput.self, from: env.payload) {
            world.input[slot].dx = i.dx
            world.input[slot].dz = i.dz
            if let sw = i.swing { world.input[slot].swing = sw }
        }
    }

    private func broadcast() {
        if let d = pack("snapshot", world.makeSnapshot()) {
            net.send(d, reliable: false)
        }
    }

    // MARK: GameControlling

    func setMove(_ x: Float, _ y: Float) {
        world.input[0].dx = x
        world.input[0].dz = y * teamOf(slot: 0).sign
    }

   func setPaused(_ p: Bool) { view.scene?.isPaused = p }

    func shutdown() {
        timer?.invalidate()
        net.stopHosting()
        net.session.disconnect()
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt = lastT == 0 ? 1 / 60 : Float(min(time - lastT, 0.05))
        lastT = time
        world.update(dt)
    }
}

// MARK: - Клиент: предсказание своего движения + интерполяция снапшотов

final class ClientController: NSObject, GameControlling, SCNSceneRendererDelegate {
    let world: GameWorld
    let view: SwingView
    let net: NetSession

    var onEvent: ((GameEvent) -> Void)?
    var onStatus: ((String) -> Void)?

    private var mySlot = -1
    private var ballTarget = SCNVector3(0, 1.5, 0)
    private var ballVel = SCNVector3Zero
    private var playerTargets: [SCNVector3]
    private var age: Float = 0
    private var lastPointSeq = -1
    private var timer: Timer?
    private var lastT: TimeInterval = 0
    private var pendingSwing: Swing?

    init(net: NetSession) {
        self.net = net
        world = GameWorld(authority: false)
        view = SwingView()
        playerTargets = world.pos
        super.init()

        view.scene = world.scene
        view.delegate = self
        view.isPlaying = true
        view.allowsCameraControl = false
        view.preferredFramesPerSecond = 60
        view.backgroundColor = .black
        view.ballInfo = { [weak self] in
            guard let self, self.mySlot >= 0 else { return (1, 99) }
            let d = dist3(self.world.ballNode.position,
                          SCNVector3(self.world.pos[self.mySlot].x, 1.3, self.world.pos[self.mySlot].z))
            return (self.world.ballNode.position.y, d)
        }
        view.onSwing = { [weak self] sw in
            self?.pendingSwing = sw
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        net.onData = { [weak self] d, _ in self?.handleData(d) }
        net.onDisconnect = { [weak self] _ in self?.onStatus?("Соединение потеряно") }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            self?.sendInput()
        }
    }

    private func handleData(_ data: Data) {
        guard let env = try? JSONDecoder().decode(Envelope.self, from: data) else { return }
        if env.kind == "welcome",
           let slot = try? JSONDecoder().decode(Int.self, from: env.payload) {
            mySlot = slot
            world.ownSlot = slot
            onStatus?("Вы — игрок \(slot + 1)")
        } else if env.kind == "snapshot",
                  let s = try? JSONDecoder().decode(Snapshot.self, from: env.payload) {
            apply(s)
        }
    }

    private func apply(_ s: Snapshot) {
        ballTarget = s.ball.scn
        ballVel = s.ballVel.scn
        age = 0
        for i in 0..<4 { playerTargets[i] = s.players[i].scn }
        world.score.restore(s.score)
        world.applyRemoteMeta(phase: s.phase, serverSlot: s.serverSlot,
                              pointSeq: s.pointSeq, lastWinner: s.lastWinner,
                              lastKind: s.lastKind)
        if s.pointSeq != lastPointSeq {
            lastPointSeq = s.pointSeq
            let team = Team(rawValue: s.lastWinner) ?? .a
            let kind = PointKind(rawValue: s.lastKind) ?? .point
            if kind == .match {
                onEvent?(.matchOver(winner: team, score: world.score.snapshot))
            } else {
                onEvent?(.point(wonBy: team, kind: kind, score: world.score.snapshot))
            }
        }
        for i in 0..<4 where s.swung[i] { world.triggerRemoteSwing(slot: i) }
    }

    private func sendInput() {
        guard mySlot >= 0 else { return }
        let i = PlayerInput(dx: world.input[mySlot].dx, dz: world.input[mySlot].dz,
                            swing: pendingSwing)
        pendingSwing = nil
        if let d = pack("input", i) { net.send(d, reliable: true) }
    }

    // MARK: GameControlling

    func setMove(_ x: Float, _ y: Float) {
        guard mySlot >= 0 else { return }
        world.input[mySlot].dx = x
        world.input[mySlot].dz = y * teamOf(slot: mySlot).sign
    }

func setPaused(_ p: Bool) { view.scene?.isPaused = p }

    func shutdown() {
        timer?.invalidate()
        net.session.disconnect()
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt = lastT == 0 ? 1 / 60 : Float(min(time - lastT, 0.05))
        lastT = time
        age += dt

        // Интерполяция мяча с короткой экстраполяцией по скорости
        let predicted = ballTarget + ballVel * min(age, 0.15)
        let k = min(1, dt * 14)
        let bp = world.ballNode.position
        world.ballNode.position = SCNVector3(bp.x + (predicted.x - bp.x) * k,
                                             bp.y + (predicted.y - bp.y) * k,
                                             bp.z + (predicted.z - bp.z) * k)
        for i in 0..<4 {
            let p = world.pos[i], t = playerTargets[i]
            world.pos[i] = SCNVector3(p.x + (t.x - p.x) * k,
                                      p.y + (t.y - p.y) * k,
                                      p.z + (t.z - p.z) * k)
        }
        world.update(dt)
    }
}
