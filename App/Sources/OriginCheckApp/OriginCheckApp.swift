import SwiftUI

@main
struct OriginCheckApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup("OriginCheck", id: "main") {
            MainView()
                .environment(appState)
                .frame(minWidth: 780, minHeight: 580)
        }

        MenuBarExtra("OriginCheck", systemImage: "checkmark.shield.fill") {
            MenuBarContent()
                .environment(appState)
        }
    }
}

struct MainView: View {
    var body: some View {
        TabView {
            CheckView()
                .tabItem { Label("Check", systemImage: "checkmark.circle") }
            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
