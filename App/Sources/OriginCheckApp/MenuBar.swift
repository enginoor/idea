import SwiftUI
import AppKit

struct MenuBarContent: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // No keyboardShortcut here: a menu bar menu is only active while it
        // is open, so shortcuts declared on these items never fire. The real
        // shortcuts live in the Verify menu in OriginCheckApp.swift.
        Button("Check Clipboard") { checkClipboard() }
        Button("Verify a File...") { pickFile() }
        Divider()
        Button("Open OriginCheck") { openWindow(id: "main") }
        Divider()
        Button("Quit OriginCheck") { NSApplication.shared.terminate(nil) }
    }

    @MainActor
    private func checkClipboard() {
        // Bring the window forward before the check runs so a menu bar
        // action is never silent: the user sees the spinner, then the
        // verdict lands in the Check tab.
        openWindow(id: "main")
        Task { @MainActor in
            await appState.checkClipboardText()
        }
    }

    @MainActor
    private func pickFile() {
        openWindow(id: "main")
        Task { @MainActor in
            appState.pickAndVerifyFile()
        }
    }
}
