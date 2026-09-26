import SwiftUI
import MultipeerConnectivity

struct RootView: View {
    @StateObject var vm = MatchViewModel()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.08, blue: 0.16),
                         Color(red: 0.10, green: 0.22, blue: 0.38)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ).ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer()
                Text("PADEL 3D")
                    .font(.system(size: 56, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("4 игрока · вид от первого лица · онлайн и офлайн")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.bottom, 24)

                MenuButton(title: "Играть с ботами", icon: "person.2.fill") { vm.startOffline() }
                MenuButton(title: "Создать онлайн-матч", icon: "wifi") { vm.startHost() }
                MenuButton(title: "Присоединиться к матчу", icon: "link") { vm.showBrowser = true }
                MenuButton(title: "Как играть", icon: "questionmark.circle") { vm.showHelp = true }

                Spacer()
                Text("v1.0 · SceneKit + Multipeer")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding()
        }
        .fullScreenCover(isPresented: $vm.inGame) {
            GameScreen().environmentObject(vm)
        }
        .sheet(isPresented: $vm.showHelp) { HelpView() }
        .sheet(isPresented: $vm.showBrowser) {
            BrowserView(session: vm.browserSession.session) {
                vm.showBrowser = false
                if !vm.browserSession.session.connectedPeers.isEmpty {
                    vm.beginClient()
                }
            }
        }
    }
}

struct MenuButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.headline)
                .frame(maxWidth: 320)
                .padding(.vertical, 14)
                .background(Color(red: 0.78, green: 0.96, blue: 0.2), in: Capsule())
                .foregroundStyle(Color(red: 0.05, green: 0.08, blue: 0.16))
        }
    }
}

struct HelpView: View {
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Group {
                        Text("🕹 Движение").font(.headline)
                        Text("Левый ползунок — бег по своей половине. Направление «вверх» всегда к сетке, автоматически подстраивается под сторону корта.")
                        Text("🎾 Удары (свайп справа)").font(.headline)
                        Text("• Тап или резкий короткий рывок — волей\n• Горизонтальный/диагональный свайп — драйв (боковой компонент задаёт прицел)\n• Свайп вверх — лоб\n• Резкий свайп вверх по высокому мячу — смэш")
                        Text("⏱ Тайминг").font(.headline)
                        Text("Чем ближе мяч к ракетке в момент свайпа, тем точнее и мощнее удар. Промах по таймингу — ошибка в прицеле.")
                        Text("🏆 Правила").font(.headline)
                        Text("Очки 15/30/40, при равенстве — Ad. Сет до 6 геймов (при 6:6 — тай-брейк), матч до 2 сетов. Мяч можно гонять от стёкл, как в настоящем паделе. Очко проигрывает сторона, на чьей половине мяч отскочил дважды, или после удара в сетку/аут.")
                        Text("🌐 Онлайн").font(.headline)
                        Text("Хост создаёт матч, остальные присоединяются в одной Wi-Fi/Bluetooth сети. Свободные места занимают боты, выбывших игроков боты заменяют автоматически.")
                    }
                    .font(.body)
                }
                .padding()
            }
            .navigationTitle("Как играть")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
        }
    }
}

struct BrowserView: UIViewControllerRepresentable {
    let session: MCSession
    let onDone: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    func makeUIViewController(context: Context) -> MCBrowserViewController {
        let browser = MCBrowserViewController(serviceType: NetSession.serviceType, session: session)
        browser.delegate = context.coordinator
        browser.maximumNumberOfPeers = 3
        browser.minimumNumberOfPeers = 1
        return browser
    }

    func updateUIViewController(_ uiViewController: MCBrowserViewController, context: Context) {}

    final class Coordinator: NSObject, MCBrowserViewControllerDelegate {
        let onDone: () -> Void
        init(onDone: @escaping () -> Void) { self.onDone = onDone }
        func browserViewControllerDidFinish(_ browserViewController: MCBrowserViewController) { onDone() }
        func browserViewControllerWasCancelled(_ browserViewController: MCBrowserViewController) { onDone() }
    }
}
