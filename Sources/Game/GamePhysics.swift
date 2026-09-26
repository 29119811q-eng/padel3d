import SceneKit

/// Скорость, чтобы попасть из `from` в `target` с вершиной траектории на `apex` выше самой высокой точки.
func velocityForShot(from: SCNVector3, target: SCNVector3, apex: Float) -> SCNVector3 {
    let g = CourtSpec.g
    let peak = max(from.y, target.y) + max(apex, 0.1)
    let vUp = sqrtf(2 * g * max(peak - from.y, 0.05))
    let tUp = vUp / g
    let vDown = sqrtf(2 * g * max(peak - target.y, 0.05))
    let tDown = vDown / g
    let T = tUp + tDown
    return SCNVector3((target.x - from.x) / T, vUp, (target.z - from.z) / T)
}

/// Где мяч коснётся пола (с одним отражением от заднего стекла).
func predictedBounce(pos: SCNVector3, vel: SCNVector3) -> (x: Float, z: Float, t: Float) {
    let g = CourtSpec.g
    let disc = vel.y * vel.y + 2 * g * pos.y
    let t = (vel.y + sqrtf(max(disc, 0.0001))) / g
    var x = pos.x + vel.x * t
    var z = pos.z + vel.z * t
    let maxZ = CourtSpec.halfL - 0.15
    if abs(z) > maxZ {
        z = 2 * maxZ * (z > 0 ? 1 : -1) - z
        x *= 0.96
    }
    let maxX = CourtSpec.halfW - 0.15
    if abs(x) > maxX { x = 2 * maxX * (x > 0 ? 1 : -1) - x }
    return (clamp(x, -4.8, 4.8), clamp(z, -9.8, 9.8), t)
}
