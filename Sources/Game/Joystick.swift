import SwiftUI

/// Левый виртуальный ползунок: возвращает нормированный вектор (-1...1).
struct JoystickView: View {
    var onChange: (Float, Float) -> Void
    @State private var offset: CGSize = .zero
    private let size: CGFloat = 128

    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.10))
                .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1.5))
            Circle()
                .fill(Color(red: 0.78, green: 0.96, blue: 0.2).opacity(0.9))
                .frame(width: 52, height: 52)
                .offset(offset)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let max = Float(size / 2)
                    var dx = Float(v.translation.width) / max
                    var dy = Float(v.translation.height) / max
                    let l = sqrtf(dx * dx + dy * dy)
                    if l > 1 { dx /= l; dy /= l }
                    offset = CGSize(width: CGFloat(dx) * size / 2,
                                    height: CGFloat(dy) * size / 2)
                    onChange(dx, dy)
                }
                .onEnded { _ in
                    offset = .zero
                    onChange(0, 0)
                }
        )
    }
}
