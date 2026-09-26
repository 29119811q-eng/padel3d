import SceneKit

/// ИИ-игрок: занимает позицию по предсказанному отскоку, выбирает удар.
/// skill 0.6...0.9 влияет на реакцию, прицел и выбор удара.
final class BotBrain {
    let slot: Int
    let skill: Float
    private let sgn: Float
    private var cooldown: Float = 0

    init(slot: Int, skill: Float = Float.random(in: 0.62...0.85)) {
        self.slot = slot
        self.skill = skill
        self.sgn = teamOf(slot: slot).sign
    }

    func update(world: GameWorld, dt: Float) -> PlayerInput {
        cooldown -= dt
        var out = PlayerInput()
        let myPos = world.pos[slot]
        let b = world.ballNode.position
        let v = world.ballNode.physicsBody?.velocity ?? SCNVector3Zero
        let d = dist3(b, SCNVector3(myPos.x, 1.3, myPos.z))
        let ballComing = (v.z * sgn) < -0.5
        let ballOnMyHalf = (b.z * sgn) > 0.1

        var target = homePosition(slot: slot)

        if world.phase == .serve && slot == world.serverSlot {
            // Подающий бот: подойти к подброшенному мячу
            target = SCNVector3(b.x, 0, clampHalfZ(b.z, sgn: sgn))
            if d < CourtSpec.reach * 0.85 && cooldown <= 0 {
                out.swing = Swing(type: .drive, aim: Float.random(in: -0.5...0.5), power: 0.8)
                cooldown = 0.4
            }
        } else if world.phase != .serve && ballOnMyHalf && (ballComing || d < 7) {
            let pred = predictedBounce(pos: b, vel: v)
            target = SCNVector3(pred.x, 0, clampHalfZ(pred.z - sgn * 0.6, sgn: sgn))
            if d < CourtSpec.reach * (0.8 + 0.2 * skill) && ballComing && cooldown <= 0 {
                out.swing = chooseShot(ballY: b.y)
                cooldown = 0.22 + (1 - skill) * 0.5
            }
        } else {
            // Позиционная игра: закрываем свою половину
            target = SCNVector3((slot % 2 == 0 ? -1.7 : 1.7), 0, sgn * 7.2)
        }

        let dx = target.x - myPos.x, dz = target.z - myPos.z
        let l = sqrtf(dx * dx + dz * dz)
        if l > 0.18 { out.dx = dx / l; out.dz = dz / l }
        return out
    }

    private func chooseShot(ballY: Float) -> Swing {
        let defensive = ballY < 0.9
        let r = Float.random(in: 0...1)
        let type: ShotType = defensive ? .lob
            : (ballY > 2.0 && r < 0.3 ? .smash : (r < 0.15 ? .volley : .drive))
        let err = 1 - skill
        return Swing(type: type,
                     aim: Float.random(in: -1...1) * (0.35 + err),
                     power: Float.random(in: 0.6...0.95))
    }
}
