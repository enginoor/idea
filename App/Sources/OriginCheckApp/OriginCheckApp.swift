import SwiftUI

@main
struct OriginCheckApp: App {
    @State private var appState = AppState()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("OriginCheck", id: "main") {
            MainView()
                .environment(appState)
                .frame(minWidth: 780, minHeight: 580)
                .onChange(of: appState.thresholdPreset) { persistSettings() }
                .onChange(of: appState.localAnalyzerEnabled) { persistSettings() }
                .onChange(of: appState.anthropicProviderEnabled) { persistSettings() }
                .onChange(of: appState.storeRawContent) { persistSettings() }
                .onChange(of: appState.c2paToolPath) { persistSettings() }
        }
        .commands {
            // The global shortcuts live here, not on the menu bar items:
            // a menu bar menu is only active while it is open, so a
            // keyboardShortcut on its buttons never fires.
            CommandMenu("Verify") {
                Button("Check Clipboard") {
                    Task { @MainActor in
                        openWindow(id: "main")
                        await appState.checkClipboardText()
                    }
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Button("Verify a File...") {
                    Task { @MainActor in
                        openWindow(id: "main")
                        appState.pickAndVerifyFile()
                    }
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra("OriginCheck", systemImage: "checkmark.shield.fill") {
            MenuBarContent()
                .environment(appState)
        }
    }

    /// Writes the observable settings to UserDefaults. The app scene owns
    /// persistence so the views never have to think about it.
    @MainActor
    private func persistSettings() {
        let defaults = UserDefaults.standard
        defaults.set(appState.thresholdPreset.rawValue, forKey: "thresholdPreset")
        defaults.set(appState.localAnalyzerEnabled, forKey: "localAnalyzerEnabled")
        defaults.set(appState.anthropicProviderEnabled, forKey: "anthropicProviderEnabled")
        defaults.set(appState.storeRawContent, forKey: "storeRawContent")
        defaults.set(appState.c2paToolPath, forKey: "c2paToolPath")
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
