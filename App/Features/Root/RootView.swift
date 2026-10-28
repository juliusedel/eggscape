import SwiftUI

/// The four tabs, plus the settings sheet, the first-launch tutorial and the full-screen game.
struct RootView: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        @Bindable var navigation = services.navigation
        @Bindable var launcher = services.launcher
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
