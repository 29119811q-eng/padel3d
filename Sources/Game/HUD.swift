import SwiftUI

struct HUDView: View {
    @EnvironmentObject var vm: MatchViewModel

    var body: some View {
        GeometryReader { _ in
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    if vm.online {
                        Label(vm.status.isEmpty ? "Онлайн" : vm.status,
                              systemImage: "wifi")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.35), in: Capsule())
                            .padding(.leading, 14)
                    }
                    Spacer()
                    ScoreboardView().environmentObject(vm)
                    Spacer()
                    Button { vm.togglePause() } label: {
                        Image(systemName: "pause.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .padding(.trailing, 14)
                    .opacity(vm.online ? 0 : 1)   // пауза только офлайн
                }
                .padding(.top, 10)

                Spacer()

                HStack(alignment: .bottom) {
                    JoystickView(onChange: vm.move)
                        .padding(.leading, 26)
                        .opacity(vm.controlsEnabled ? 1 : 0.35)
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "hand.draw")
                        Text("свайп — удар")
                            .font(.caption2)
                    }
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.trailing, 32)
                }
                .padding(.bottom, 18)
            }

            if let banner = vm.banner {
                VStack {
                    Text(banner)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(Color(red: 0.78, green: 0.96, blue: 0.2).opacity(0.92),
                                    in: Capsule())
                        .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 64)
            }

            if let mo = vm.matchOver {
                ZStack {
                    Color.black.opacity(0.6).ignoresSafeArea()
                    VStack(spacing: 18) {
                        Text("🏆")
                            .font(.system(size: 54))
                        Text(mo)
                            .font(.title.bold())
                            .foregroundStyle(.white)
                        Button("В меню") { vm.quit() }
                            .font(.headline)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 12)
                            .background(Color(red: 0.78, green: 0.96, blue: 0.2), in: Capsule())
                            .foregroundStyle(Color(red: 0.05, green: 0.08, blue: 0.16))
                    }
                }
                .transition(.opacity)
            }

            if vm.paused {
                ZStack {
                    Color.black.opacity(0.55).ignoresSafeArea()
                    VStack(spacing: 16) {
                        Text("Пауза").font(.title.bold()).foregroundStyle(.white)
                        Button("Продолжить") { vm.togglePause() }
                            .menuStyled()
                        Button("Завершить матч") { vm.quit() }
                            .menuStyled(secondary: true)
                    }
                }
            }
        }
    }
}

extension View {
    func menuStyled(secondary: Bool = false) -> some View {
        self.font(.headline)
            .frame(maxWidth: 260)
            .padding(.vertical, 13)
            .background(
                secondary ? Color.white.opacity(0.15)
                          : Color(red: 0.78, green: 0.96, blue: 0.2),
                in: Capsule()
            )
            .foregroundStyle(secondary ? .white : Color(red: 0.05, green: 0.08, blue: 0.16))
    }
}

struct ScoreboardView: View {
    @EnvironmentObject var vm: MatchViewModel
    var body: some View {
        let s = vm.score ?? ScoreSnapshot()
        HStack(spacing: 16) {
            teamColumn("A", color: Color(red: 0.78, green: 0.96, blue: 0.2),
                       sets: s.setsA, games: s.gamesA,
                       points: ScoreText.points(s.ptsA, s.ptsB),
                       serving: s.serving == 0)
            Text(":")
                .font(.title3.bold())
                .foregroundStyle(.white.opacity(0.5))
            teamColumn("B", color: Color(red: 1.0, green: 0.45, blue: 0.4),
                       sets: s.setsB, games: s.gamesB,
                       points: ScoreText.points(s.ptsB, s.ptsA),
                       serving: s.serving == 1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule())
    }

    func teamColumn(_ name: String, color: Color, sets: Int, games: Int,
                    points: String, serving: Bool) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 10, height: 10)
            if serving { Image(systemName: "tennisball").font(.caption2).foregroundStyle(.white) }
            Text("\(sets)  \(games)  \(points)")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
    }
}
