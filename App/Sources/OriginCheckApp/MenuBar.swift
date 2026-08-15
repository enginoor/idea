import SwiftUI
import AppKit

struct MenuBarContent: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Check Clipboard") { checkClipboard() }
        Button("Verify a File...") { pickFile() }
        Divider()
        Button("Open OriginCheck") { openWindow(id: "main") }
        Divider()
        Button("Quit OriginCheck") { NSApplication.shared.terminate(nil) }
    }

    private func checkClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        Task { await appState.analyzeText(text) }
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await appState.verifyFile(url) }
    }
}
