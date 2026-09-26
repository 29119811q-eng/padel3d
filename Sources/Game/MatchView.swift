import SwiftUI
import UIKit
import SceneKit

// MARK: - Классификатор свайпа (механика ударов)

enum SwingClassifier {
    /// Перевод жеста в удар. ballY/dist — контекст для выбора смэша/волея.
    static func classify(translation t: CGPoint, duration: TimeInterval,
                         ballY: Float, distance: Float) -> Swing? {
        let dt = max(duration, 0.02)
        let speed = CGFloat(hypot(Float(t.width), Float(t.height))) / CGFloat(dt) // pt/s
        guard speed > 300 || distance < 2.2 else { return nil }

        var type: ShotType = .drive
        if t.height < -160 && ballY > 1.85 { type = .smash }
        else if t.height < -60 { type = .lob }
        else if speed > 900 && distance < 2.6 { type = .volley }

        let aim = Float(clamp(t.width / 220, -1, 1))
        let power = Float(clamp(speed / 1400, 0.4, 1))
        return Swing(type: type, aim: aim, power: power)
    }
}

// MARK: - 3D-вью со свайпами (правая часть экрана — зона удара)

final class SwingView: SCNView {
    var onSwing: ((Swing) -> Void)?
    var ballInfo: (() -> (y: Float, dist: Float))?
    private var start: CGPoint = .zero
    private var startTime: TimeInterval = 0
    private var tracking = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let p = t.location(in: self)
        guard p.x > bounds.width * 0.38 else { return }
        tracking = true
        start = p
        startTime = event?.timestamp ?? CACurrentMediaTime()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard tracking, let t = touches.first else { return }
        tracking = false
        let end = t.location(in: self)
        let tr = CGPoint(x: end.x - start.x, y: end.y - start.y)
        let dur = (event?.timestamp ?? CACurrentMediaTime()) - startTime
        let info = ballInfo?() ?? (1, 99)
        if let sw = SwingClassifier.classify(translation: tr, duration: dur,
                                             ballY: info.y, distance: info.dist) {
            onSwing?(sw)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        tracking = false
    }
}

// MARK: - Общий протокол контроллеров матча

protocol GameControlling: AnyObject {
    var view: SwingView { get }
    func setMove(_ x: Float, _ y: Float)
    func setPaused(_ p: Bool)
    func shutdown()
}

struct ControllerView: UIViewRepresentable {
    let controller: GameControlling
    func makeUIView(context: Context) -> UIView { controller.view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - Экран матча

struct GameScreen: View {
    @EnvironmentObject var vm: MatchViewModel
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let c = vm.controller {
                ControllerView(controller: c).ignoresSafeArea()
            }
            HUDView().environmentObject(vm)
        }
        .statusBarHidden(true)
        .onDisappear { vm.quit() }
    }
}
