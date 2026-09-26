import SceneKit
import UIKit

/// Офлайн-матч: вы — слот 0, остальные — боты.
final class LocalMatchController: NSObject, GameControlling, SCNSceneRendererDelegate {
    let world: GameWorld
    let view: SwingView
    var onEvent: ((GameEvent) -> Void)?
    private var lastT: TimeInterval = 0

    override init() {
        world = GameWorld(authority: true)
        view = SwingView()
        super.init()
        world.ownSlot = 0
        world.setHuman(true, slot: 0)
        setupView()
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

    func setMove(_ x: Float, _ y: Float) {
        world.input[0].dx = x
        world.input[0].dz = y * teamOf(slot: 0).sign
    }

    func setPaused(_ p: Bool) { view.isPaused = p }
    func shutdown() {}

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt = lastT == 0 ? 1 / 60 : Float(min(time - lastT, 0.05))
        lastT = time
        world.update(dt)
    }
}
