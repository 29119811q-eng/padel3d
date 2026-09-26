import Foundation
import SceneKit

// MARK: - Команды и слоты

enum Team: Int, Codable, Equatable {
    case a = 0, b = 1
    var sign: Float { self == .a ? 1 : -1 }
    var other: Team { self == .a ? .b : .a }
    var displayName: String { self == .a ? "A" : "B" }
}

func teamOf(slot: Int) -> Team { slot < 2 ? .a : .b }

func homePosition(slot: Int) -> SCNVector3 {
    let s = teamOf(slot: slot).sign
    let x: Float = (slot % 2 == 0) ? -1.8 : 1.8
    return SCNVector3(x, 0, s * 7.3)
}

// MARK: - Ввод и удары

enum ShotType: String, Codable { case drive, lob, volley, smash }

struct Swing: Codable, Equatable {
    var type: ShotType
    var aim: Float    // -1...1 (боковой прицел)
    var power: Float  // 0.35...1
}

struct PlayerInput: Codable, Equatable {
    var dx: Float = 0
    var dz: Float = 0
    var swing: Swing? = nil
}

// MARK: - Математика-helpers

func clamp<T: Comparable>(_ v: T, _ a: T, _ b: T) -> T { min(max(v, a), b) }

func clampHalfZ(_ z: Float, sgn: Float) -> Float {
    clamp(z, min(0.55 * sgn, 9.35 * sgn), max(0.55 * sgn, 9.35 * sgn))
}

func dist3(_ a: SCNVector3, _ b: SCNVector3) -> Float {
    let dx = a.x - b.x, dy = a.y - b.y, dz = a.z - b.z
    return sqrtf(dx * dx + dy * dy + dz * dz)
}

func + (a: SCNVector3, b: SCNVector3) -> SCNVector3 { SCNVector3(a.x + b.x, a.y + b.y, a.z + b.z) }
func * (a: SCNVector3, s: Float) -> SCNVector3 { SCNVector3(a.x * s, a.y * s, a.z * s) }

let SCNVector3Zero = SCNVector3(0, 0, 0)

struct Vec3: Codable, Equatable {
    var x: Float; var y: Float; var z: Float
    init(_ v: SCNVector3) { x = v.x; y = v.y; z = v.z }
    var scn: SCNVector3 { SCNVector3(x, y, z) }
}

// MARK: - Корт

enum CourtSpec {
    static let halfW: Float = 5
    static let halfL: Float = 10
    static let netH: Float = 0.92
    static let eye: Float = 1.6
    static let reach: Float = 1.5      // зона удара ракеткой
    static let speed: Float = 4.7      // м/с бег игрока
    static let g: Float = 9.81
}

struct PhysCat {
    static let floor: UInt32 = 1
    static let wall: UInt32 = 2
    static let net: UInt32 = 4
    static let ball: UInt32 = 8
    static let player: UInt32 = 16
}

// MARK: - Счёт

struct ScoreSnapshot: Codable, Equatable {
    var setsA = 0, setsB = 0
    var gamesA = 0, gamesB = 0
    var ptsA = 0, ptsB = 0
    var serving = 0
    var over = false
    var winner = -1
}

enum ScoreText {
    static func points(_ p: Int, _ o: Int) -> String {
        if p >= 3 && o >= 3 { return p == o ? "40" : (p > o ? "Ad" : "–") }
        return ["0", "15", "30", "40"][min(max(p, 0), 3)]
    }
}

struct ScoreKeeper {
    private(set) var setsA = 0, setsB = 0, gamesA = 0, gamesB = 0
    private var ptsA = 0, ptsB = 0
    private(set) var serving: Team = .a
    private(set) var over = false
    private(set) var winner: Team?
    private var tiebreak: Bool { gamesA == 6 && gamesB == 6 }

    @discardableResult
    mutating func point(wonBy t: Team) -> PointKind {
        if over { return .point }
        if t == .a { ptsA += 1 } else { ptsB += 1 }
        let lead = abs(ptsA - ptsB), maxp = max(ptsA, ptsB)
        let need = tiebreak ? 7 : 4
        guard maxp >= need && lead >= 2 else { return .point }

        if t == .a { gamesA += 1 } else { gamesB += 1 }
        ptsA = 0; ptsB = 0
        serving = serving.other
        let gLead = abs(gamesA - gamesB), gMax = max(gamesA, gamesB)
        guard gMax >= 6 && gLead >= 2 else { return .game }

        if t == .a { setsA += 1 } else { setsB += 1 }
        gamesA = 0; gamesB = 0
        if setsA >= 2 || setsB >= 2 { over = true; winner = t; return .match }
        return .set
    }

    var snapshot: ScoreSnapshot {
        ScoreSnapshot(setsA: setsA, setsB: setsB, gamesA: gamesA, gamesB: gamesB,
                      ptsA: ptsA, ptsB: ptsB, serving: serving.rawValue,
                      over: over, winner: winner?.rawValue ?? -1)
    }

    mutating func restore(_ s: ScoreSnapshot) {
        setsA = s.setsA; setsB = s.setsB; gamesA = s.gamesA; gamesB = s.gamesB
        ptsA = s.ptsA; ptsB = s.ptsB
        serving = Team(rawValue: s.serving) ?? .a
        over = s.over
        winner = Team(rawValue: s.winner)
    }
}

// MARK: - Сетевой снапшот

struct Snapshot: Codable {
    var ball: Vec3
    var ballVel: Vec3
    var players: [Vec3]
    var score: ScoreSnapshot
    var serverSlot: Int
    var phase: Int
    var pointSeq: Int
    var lastWinner: Int
    var lastKind: String
    var swung: [Bool]
}
