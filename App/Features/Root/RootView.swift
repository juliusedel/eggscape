import SwiftUI

/// The four tabs, plus the settings sheet, the first-launch tutorial and the full-screen game.
struct RootView: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        @Bindable var navigation = services.navigation
        @Bindable var launcher = services.launcher
        let gameCenter = services.gameCenter
        TabView(selection: $navigation.tab) {
            SingleplayerView()
                .tabItem { Label("Einzelspieler", systemImage: "figure.run") }
                .tag(AppNavigation.Tab.singleplayer)
            MultiplayerView()
                .tabItem { Label("Mehrspieler", systemImage: "person.3.fill") }
                .tag(AppNavigation.Tab.multiplayer)
            LeaderboardView()
                .tabItem { Label("Bestenliste", systemImage: "trophy.fill") }
                .tag(AppNavigation.Tab.leaderboard)
            ShopView()
                .tabItem { Label("Shop", systemImage: "bag.fill") }
                .tag(AppNavigation.Tab.shop)
        }
        .sheet(isPresented: $navigation.showsSettings) {
            SettingsView()
        }
        .fullScreenCover(isPresented: $navigation.showsTutorial) {
            TutorialView {
                services.settings.hasSeenTutorial = true
                navigation.showsTutorial = false
            }
        }
        .fullScreenCover(item: $launcher.flow) { flow in
            GameFlowView(flow: flow)
        }
        .fullScreenCover(item: invite) { accepted in
            NavigationStack {
                OnlineView(invite: accepted.invite)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Schließen") { gameCenter.acceptedInvite = nil }
                        }
                    }
            }
        }
        .fullScreenCover(isPresented: $navigation.showsScreenshotLobby) {
            NavigationStack {
                NearbyView(initialSession: .screenshotLobby(services: services))
            }
        }
        .onAppear {
            if let scene = LaunchOptions.current.screenshotScene.flatMap(ScreenshotScene.init(rawValue:)) {
                ScreenshotStage.prepare(scene, services: services)
            } else if !services.settings.hasSeenTutorial {
                navigation.showsTutorial = true
            }
        }
        .onChange(of: gameCenter.acceptedInvite?.id) { _, id in
            // An invitation does not wait behind the settings sheet: settings closes for it.
            if id != nil {
                navigation.showsSettings = false
            }
        }
    }

    /// An accepted invitation waits until no run, tutorial or settings sheet is on screen, because only one of them
    /// can be presented at a time.
    private var invite: Binding<AcceptedInvite?> {
        let navigation = services.navigation
        let gameCenter = services.gameCenter
        let isFree = services.launcher.flow == nil && !navigation.showsTutorial && !navigation.showsSettings
        let invite = isFree ? gameCenter.acceptedInvite : nil
        return Binding(get: { invite }, set: { gameCenter.acceptedInvite = $0 })
    }
}

/// Opens the settings sheet from any tab's navigation bar.
struct SettingsToolbarButton: ToolbarContent {
    @Environment(AppServices.self) private var services

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                services.navigation.showsSettings = true
            } label: {
                Label("Einstellungen", systemImage: "gearshape")
            }
            .accessibilityIdentifier("toolbar.settings")
        }
    }
}

/// Picks the right full-screen experience for the running game.
struct GameFlowView: View {
    let flow: GameFlow
    @Environment(AppServices.self) private var services

    var body: some View {
        switch flow {
        case let .single(single):
            SingleRunView(flow: single)
        case let .hotSeat(session):
            HotSeatFlowView(session: session)
        }
    }
}

private struct SingleRunView: View {
    let flow: SingleRunFlow
    @Environment(AppServices.self) private var services

    var body: some View {
        RunView(session: flow.session, onQuit: services.launcher.close) { outcome in
            RunResultsView(outcome: outcome, onRestart: services.launcher.restart, onDone: services.launcher.close)
        }
        .id(ObjectIdentifier(flow.session))
    }
}
