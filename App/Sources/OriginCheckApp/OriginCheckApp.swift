import SwiftUI

@main
struct OriginCheckApp: App {
    @State private var appState = AppState()
    @Environment(\.openWindow) private var openWindow

    @MainActor
    init() {
        // Start Sparkle's updater at launch so scheduled background checks
        // run even if no window is ever opened. The updater reads the feed
        // URL and public key from the packaged Info.plist.
        UpdateController.shared.start()
    }

    var body: some Scene {
        WindowGroup("OriginCheck", id: "main") {
            MainView()
                .environment(appState)
                .frame(minWidth: 920, minHeight: 600)
                .modifier(SettingsPersistence(appState: appState))
        }
        .defaultSize(width: 1120, height: 720)
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

            // The conventional home for "Check for Updates" is the app
            // menu, right below About.
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    UpdateController.shared.checkForUpdates(nil)
                }
            }
        }

        // Settings is its own window in the classic macOS way: Cmd+, opens
        // it from the app menu, and the main window sidebar stays focused
        // on the two verification surfaces. Same persistence hook as the
        // main window, because settings can be changed from either window.
        Settings {
            SettingsView()
                .environment(appState)
                .frame(minWidth: 520, minHeight: 420)
                .modifier(SettingsPersistence(appState: appState))
        }

        MenuBarExtra("OriginCheck", systemImage: "checkmark.shield.fill") {
            MenuBarContent()
                .environment(appState)
        }
    }
}

/// Persists the observable settings to UserDefaults. Attached to both the
/// main window and the Settings window so a change made in either place is
/// written once, in one code path, no matter which scene the user is in.
struct SettingsPersistence: ViewModifier {
    let appState: AppState

    func body(content: Content) -> some View {
        content
            .onChange(of: appState.thresholdPreset) { persist() }
            .onChange(of: appState.localAnalyzerEnabled) { persist() }
            .onChange(of: appState.anthropicProviderEnabled) { persist() }
            .onChange(of: appState.storeRawContent) { persist() }
            .onChange(of: appState.c2paToolPath) { persist() }
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(appState.thresholdPreset.rawValue, forKey: "thresholdPreset")
        defaults.set(appState.localAnalyzerEnabled, forKey: "localAnalyzerEnabled")
        defaults.set(appState.anthropicProviderEnabled, forKey: "anthropicProviderEnabled")
        defaults.set(appState.storeRawContent, forKey: "storeRawContent")
        defaults.set(appState.c2paToolPath, forKey: "c2paToolPath")
    }
}

/// The main window: a sidebar listing the two verification surfaces, with
/// the Check or History pane as the detail column. This is the structure a
/// Mac user expects from a utility app: sidebar, toolbar, and a detail pane,
/// instead of an iOS-style tab bar crammed into one window.
struct MainView: View {
    @State private var selection: AppSection? = .check

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 180, ideal: 205, max: 260)
        } detail: {
            switch selection ?? .check {
            case .check:
                CheckView()
            case .history:
                HistoryView()
            }
        }
        .navigationTitle(selection?.title ?? "Check")
    }
}

/// The two sidebar destinations. String-backed so the sidebar selection
/// binds directly to the split view navigation.
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case check
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .check: "Check"
        case .history: "History"
        }
    }

    var icon: String {
        switch self {
        case .check: "checkmark.circle"
        case .history: "clock.arrow.circlepath"
        }
    }
}
