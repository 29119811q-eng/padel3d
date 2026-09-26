import SceneKit

/// Видимое тело игрока: ноги, корпус, рука с ракеткой. Анимируются шаги и замах.
final class PlayerAvatar {
    let root = SCNNode()
    let slot: Int

    private let legL = SCNNode()
    private let legR = SCNNode()
    private let arm = SCNNode()
    private let head = SCNNode()
    private var walk: Float = 0
    private var swing: Float = 0

    var headWorld: SCNVector3 { head.worldPosition }
    var racketWorld: SCNVector3 { tip.worldPosition }
    private let tip = SCNNode()

    init(slot: Int) {
        self.slot = slot
        let shirt: UIColor = slot < 2
            ? UIColor(red: 0.78, green: 0.96, blue: 0.2, alpha: 1)
            : UIColor(red: 1.0, green: 0.35, blue: 0.3, alpha: 1)
        let skin = UIColor(red: 0.9, green: 0.72, blue: 0.55, alpha: 1)

        // Корпус
        let body = SCNNode(geometry: SCNCapsule(capRadius: 0.19, height: 0.75))
        body.position.y = 1.02
        body.geometry?.firstMaterial?.diffuse.contents = shirt
        root.addChildNode(body)

        // Голова (скрывается у «своего» игрока — вид от первого лица)
        head.position.y = 1.62
        let h = SCNNode(geometry: SCNSphere(radius: 0.14))
        h.geometry?.firstMaterial?.diffuse.contents = skin
        head.addChildNode(h)
        root.addChildNode(head)

        // Ноги (шарниры в бедрах)
        for (node, x) in [(legL, Float(-0.1)), (legR, Float(0.1))] {
            node.position = SCNVector3(x, 0.85, 0)
            let leg = SCNNode(geometry: SCNCylinder(radius: 0.07, height: 0.82))
            leg.position.y = -0.41
            leg.geometry?.firstMaterial?.diffuse.contents = UIColor(red: 0.1, green: 0.12, blue: 0.25, alpha: 1)
            node.addChildNode(leg)
            root.addChildNode(node)
        }

        // Рука + ракетка (справа от камеры)
        arm.position = SCNVector3(0.3, 1.42, 0.05)
        let forearm = SCNNode(geometry: SCNCylinder(radius: 0.05, height: 0.32))
        forearm.rotation = SCNVector4(1, 0, 0, CGFloat.pi / 2)
        forearm.position = SCNVector3(0, -0.04, 0.16)
        forearm.geometry?.firstMaterial?.diffuse.contents = skin
        arm.addChildNode(forearm)

        let racket = SCNNode()
        racket.position = SCNVector3(0, -0.04, 0.33)
        let handle = SCNNode(geometry: SCNCylinder(radius: 0.02, height: 0.2))
        handle.rotation = SCNVector4(1, 0, 0, CGFloat.pi / 2)
        handle.geometry?.firstMaterial?.diffuse.contents = UIColor.black
        racket.addChildNode(handle)
        let headR = SCNNode(geometry: SCNTorus(ringRadius: 0.115, pipeRadius: 0.014))
        headR.scale = SCNVector3(1, 1.28, 1)
        headR.position = SCNVector3(0, 0.02, 0.14)
        headR.geometry?.firstMaterial?.diffuse.contents = UIColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 1)
        racket.addChildNode(headR)
        tip.position = SCNVector3(0, 0.02, 0.2)
        racket.addChildNode(tip)
        arm.addChildNode(racket)
        root.addChildNode(arm)

        // Физическое тело (мяч от него отскакивает)
        let phys = SCNPhysicsBody(type: .kinematic,
                                  shape: SCNPhysicsShape(geometry: SCNCapsule(capRadius: 0.24, height: 1.2), options: nil))
        phys.categoryBitMask = PhysCat.player
        phys.collisionBitMask = PhysCat.ball
        root.physicsBody = phys
    }

    func setOwn(_ own: Bool) { head.isHidden = own }

    func setMoving(_ m: Float, dt: Float) {
        walk += m * dt * 9
        legL.rotation = SCNVector4(1, 0, 0, CGFloat(sin(walk) * 0.6 * m))
        legR.rotation = SCNVector4(1, 0, 0, CGFloat(-sin(walk) * 0.6 * m))
    }

    func triggerSwing() { swing = 1 }

    func update(dt: Float) {
        guard swing > 0 else { return }
        swing = max(0, swing - dt * 2.6)
        let s = sin(swing * .pi)
        arm.rotation = SCNVector4(1, 0, 0, CGFloat(-s * 1.7))
    }
}
