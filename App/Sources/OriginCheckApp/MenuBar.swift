import SwiftUI
import AppKit

struct MenuBarContent: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Check Clipboard") { checkClipboard() }
            .keyboardShortcut("c", modifiers: [.command, .shift])
        Button("Verify a File...") { pickFile() }
            .keyboardShortcut("o", modifiers: [.command, .shift])
        Divider()
        Button("Open OriginCheck") { openWindow(id: "main") }
        Divider()
        Button("Quit OriginCheck") { NSApplication.shared.terminate(nil) }
    }

    @MainActor
    private func checkClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        // Bring the window forward before the check runs so a menu bar
        // action is never silent: the user sees the spinner, then the
        // verdict lands in the Check tab.
        openWindow(id: "main")
        Task { @MainActor in
            await appState.analyzeText(text)
        }
    }

    @MainActor
    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openWindow(id: "main")
        Task { @MainActor in
            await appState.verifyFile(url)
        }
    }
}
