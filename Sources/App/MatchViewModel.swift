import SwiftUI
import UIKit

@MainActor
final class MatchViewModel: ObservableObject {
    @Published var inGame = false
    @Published var showBrowser = false
    @Published var showHelp = false
    @Published var score: ScoreSnapshot?
    @Published var banner: String?
    @Published var status = ""
    @Published var online = false
    @Published var controlsEnabled = true
    @Published var paused = false
    @Published var matchOver: String?

    private(set) var controller: GameControlling?
    private var net: NetSession?
    let browserSession = NetSession()

    private var bannerToken = 0

    func startOffline() {
        online = false
        status = ""
        let c = LocalMatchController()
        c.onEvent = { [weak self] in self?.handle($0) }
        controller = c
        inGame = true
    }

    func startHost() {
        online = true
        status = "Ожидание игроков…"
        let session = NetSession()
        net = session
        let c = HostController(net: session)
        c.onEvent = { [weak self] in self?.handle($0) }
        c.onStatus = { [weak self] s in self?.status = s }
        controller = c
        inGame = true
    }

    func beginClient() {
        online = true
        status = "Подключение…"
        let c = ClientController(net: browserSession)
        c.onEvent = { [weak self] in self?.handle($0) }
        c.onStatus = { [weak self] s in self?.status = s }
        controller = c
        inGame = true
    }

    func move(_ x: Float, _ y: Float) { controller?.setMove(x, y) }

    func togglePause() {
        paused.toggle()
        controller?.setPaused(paused)
    }

    func quit() {
        controller?.shutdown()
        controller = nil
        net = nil
        inGame = false
        paused = false
        matchOver = nil
        score = nil
        banner = nil
    }

    private func handle(_ e: GameEvent) {
        switch e {
        case .hit(let q, _):
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: CGFloat(q))
        case .bounce:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        case .wall:
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.4)
        case .point(let won, let kind, let s):
            score = s
            switch kind {
            case .point: showBanner("Очко — команда \(won.displayName)")
            case .game: showBanner("Гейм — команда \(won.displayName)!")
            case .set: showBanner("Сет — команда \(won.displayName)!")
            case .match: break
            }
        case .matchOver(let w, let s):
            score = s
            matchOver = "Победа команды \(w.displayName)!"
        }
    }

    private func showBanner(_ text: String) {
        bannerToken += 1
        let token = bannerToken
        banner = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            guard let self, self.bannerToken == token else { return }
            self.banner = nil
        }
    }
}
