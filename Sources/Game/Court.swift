import SceneKit

func staticBody(mask: UInt32, restitution: CGFloat, friction: CGFloat) -> SCNPhysicsBody {
    let b = SCNPhysicsBody(type: .static, shape: nil)
    b.categoryBitMask = mask
    b.collisionBitMask = PhysCat.ball
    b.contactTestBitMask = PhysCat.ball
    b.restitution = restitution
    b.friction = friction
    return b
}

func makeBall() -> SCNNode {
    let n = SCNNode(geometry: SCNSphere(radius: 0.033))
    n.geometry?.firstMaterial?.diffuse.contents = UIColor(red: 0.95, green: 0.9, blue: 0.3, alpha: 1)
    let body = SCNPhysicsBody(type: .dynamic, shape: SCNPhysicsShape(geometry: n.geometry!, options: nil))
    body.mass = 0.058
    body.restitution = 0.74
    body.friction = 0.5
    body.damping = 0.05
    body.angularDamping = 0.4
    body.categoryBitMask = PhysCat.ball
    body.collisionBitMask = PhysCat.floor | PhysCat.wall | PhysCat.net | PhysCat.player
    body.contactTestBitMask = PhysCat.floor | PhysCat.wall | PhysCat.net
    n.physicsBody = body
    return n
}

func buildCourt(into scene: SCNScene) {
    scene.background.contents = UIColor(red: 0.04, green: 0.06, blue: 0.12, alpha: 1)

    // Свет и тени
    let sun = SCNNode()
    sun.light = SCNLight()
    sun.light?.type = .directional
    sun.light?.castsShadow = true
    sun.light?.shadowRadius = 5
    sun.light?.shadowMapSize = CGSize(width: 2048, height: 2048)
    sun.eulerAngles = SCNVector3(-CGFloat.pi / 3, CGFloat.pi / 6, 0)
    scene.rootNode.addChildNode(sun)
    let amb = SCNNode()
    amb.light = SCNLight()
    amb.light?.type = .ambient
    amb.light?.color = UIColor(white: 0.4, alpha: 1)
    scene.rootNode.addChildNode(amb)

    // Пол (чуть больше линий — зоны «аут»)
    let floor = SCNNode(geometry: SCNBox(width: 11.4, height: 0.2, length: 21.4, chamferRadius: 0))
    floor.position.y = -0.1
    floor.geometry?.firstMaterial?.diffuse.contents = UIColor(red: 0.12, green: 0.32, blue: 0.55, alpha: 1)
    floor.physicsBody = staticBody(mask: PhysCat.floor, restitution: 0.72, friction: 0.6)
    scene.rootNode.addChildNode(floor)

    // Линии
    let lineMat = SCNMaterial()
    lineMat.diffuse.contents = UIColor.white
    func line(_ w: Float, _ l: Float, x: Float, z: Float) {
        let n = SCNNode(geometry: SCNBox(width: CGFloat(w), height: 0.012, length: CGFloat(l), chamferRadius: 0))
        n.geometry?.firstMaterial = lineMat
        n.position = SCNVector3(x, 0.012, z)
        scene.rootNode.addChildNode(n)
    }
    line(0.05, 20.1, x: -5, z: 0); line(0.05, 20.1, x: 5, z: 0)
    line(10.05, 0.05, x: 0, z: -10); line(10.05, 0.05, x: 0, z: 10)
    line(10.05, 0.05, x: 0, z: -3.05); line(10.05, 0.05, x: 0, z: 3.05)
    line(0.05, 6.15, x: 0, z: -6.525); line(0.05, 6.15, x: 0, z: 6.525)

    // Сетка
    let net = SCNNode(geometry: SCNBox(width: 10.0, height: CGFloat(CourtSpec.netH), length: 0.04, chamferRadius: 0))
    net.position.y = CourtSpec.netH / 2
    let netMat = SCNMaterial()
    netMat.diffuse.contents = UIColor(white: 0.08, alpha: 0.9)
    net.geometry?.firstMaterial = netMat
    net.physicsBody = staticBody(mask: PhysCat.net, restitution: 0.05, friction: 0.9)
    scene.rootNode.addChildNode(net)
    for sx in [-5.0, 5.0] {
        let post = SCNNode(geometry: SCNCylinder(radius: 0.06, height: CGFloat(CourtSpec.netH + 0.1)))
        post.position = SCNVector3(CGFloat(sx), CGFloat(CourtSpec.netH / 2), 0)
        post.geometry?.firstMaterial?.diffuse.contents = UIColor.darkGray
        scene.rootNode.addChildNode(post)
    }

    // Задние стёкла + металлическая сетка сверху
    for s in [Float(1), -1] {
        let glass = SCNNode(geometry: SCNBox(width: 10.4, height: 3.0, length: 0.08, chamferRadius: 0))
        glass.position = SCNVector3(0, 1.5, s * 10)
        let gm = SCNMaterial()
        gm.diffuse.contents = UIColor.white.withAlphaComponent(0.16)
        gm.isDoubleSided = true
        glass.geometry?.firstMaterial = gm
        glass.physicsBody = staticBody(mask: PhysCat.wall, restitution: 0.82, friction: 0.05)
        scene.rootNode.addChildNode(glass)

        let mesh = SCNNode(geometry: SCNBox(width: 10.4, height: 1.4, length: 0.06, chamferRadius: 0))
        mesh.position = SCNVector3(0, 3.7, s * 10)
        let mm = SCNMaterial()
        mm.diffuse.contents = UIColor.darkGray.withAlphaComponent(0.25)
        mesh.geometry?.firstMaterial = mm
        mesh.physicsBody = staticBody(mask: PhysCat.wall, restitution: 0.6, friction: 0.2)
        scene.rootNode.addChildNode(mesh)
    }

    // Боковые стёкла (полная длина)
    for s in [Float(1), -1] {
        let wall = SCNNode(geometry: SCNBox(width: 0.08, height: 4.4, length: 20.4, chamferRadius: 0))
        wall.position = SCNVector3(s * 5, 2.2, 0)
        let wm = SCNMaterial()
        wm.diffuse.contents = UIColor.white.withAlphaComponent(0.14)
        wm.isDoubleSided = true
        wall.geometry?.firstMaterial = wm
        wall.physicsBody = staticBody(mask: PhysCat.wall, restitution: 0.82, friction: 0.05)
        scene.rootNode.addChildNode(wall)
    }
}
