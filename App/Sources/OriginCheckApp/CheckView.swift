import SwiftUI
import UniformTypeIdentifiers

struct CheckView: View {
    @Environment(AppState.self) private var appState
    @State private var mode: Mode = .text
    @State private var showImporter = false
    @State private var isTargeted = false

    enum Mode: String, CaseIterable, Identifiable {
        case text
        case file
        var id: String { rawValue }
    }

    var body: some View {
        @Bindable var appState = appState
        VStack(alignment: .leading, spacing: 20) {
            Picker("Check", selection: $mode) {
                Text("Paste text").tag(Mode.text)
                Text("Verify a file").tag(Mode.file)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if mode == .text {
                textInput(appState: appState)
            } else {
                fileDrop
            }

            HStack(spacing: 12) {
                Button(mode == .text ? "Check text" : "Verify file") {
                    run()
                }
                .disabled(appState.isAnalyzing)

                if appState.isAnalyzing {
                    ProgressView().controlSize(.small)
                }
                if let message = appState.statusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let verdict = appState.lastTextVerdict {
                VerdictPanel(display: VerdictDisplay.text(verdict))
            } else if let verdict = appState.lastFileVerdict {
                VerdictPanel(display: VerdictDisplay.file(verdict))
            } else {
                emptyState
            }
        }
        .padding(24)
    }

    private func textInput(appState: AppState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $appState.textInput)
                .font(.body)
                .frame(minHeight: 180)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.quaternary)
                )
            Text("Minimum reliable length: \(appState.thresholdPreset.minimumTextLength) characters. Shorter passages report inconclusive.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var fileDrop: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6])
                )
                .frame(maxWidth: .infinity, minHeight: 180)
                .overlay(
                    Text(isTargeted ? "Drop to verify" : "Drag a png, jpg, jpeg, or svg here")
                        .foregroundStyle(.secondary)
                )
                .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                    handleDrop(providers)
                    return true
                }

            Button("Choose a file") {
                showImporter = true
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.png, .jpeg, .svg, .pdf, .data]
            ) { result in
                if case .success(let url) = result {
                    Task { await appState.verifyFile(url) }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("Paste a passage or drop a file to get a provenance verdict.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    private func run() {
        Task {
            if mode == .text {
                await appState.analyzeText(appState.textInput)
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        _ = provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            if let data = item as? Data,
               let url = URL(dataRepresentation: data, relativeTo: nil) {
                Task { await appState.verifyFile(url) }
            }
        }
    }
}
