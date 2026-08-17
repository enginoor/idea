import SwiftUI
import OriginCheckEngine

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var keyText = ""
    @State private var toolPathText = ""

    var body: some View {
        @Bindable var appState = appState
        // The grouped form is taller than the window on small screens, and a
        // plain Form clips at the bottom without scrolling, so the whole
        // settings tab scrolls.
        ScrollView {
            Form {
                Section("Detection providers") {
                    Toggle("Local detector", isOn: $appState.localAnalyzerEnabled)
                    Text("Scores text for AI-typical patterns across model families (ChatGPT, Claude, Gemini, and others): sentence rhythm, vocabulary surprisal, rare-word rate, and AI phrasing. The frequency dictionary and phrase database ship inside the app, so detection works fully offline with no installed tools. It is a heuristic, not an official watermark detector, which has not been released for any model.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("Anthropic detection API", isOn: $appState.anthropicProviderEnabled)
                    if appState.anthropicProviderEnabled {
                        SecureField("API key", text: $keyText)
                            .onSubmit { appState.saveAnthropicKey(keyText) }
                        HStack {
                            Button("Save key") { appState.saveAnthropicKey(keyText) }
                                .disabled(keyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            Button("Remove key") { appState.clearAnthropicKey(); keyText = "" }
                                .disabled(!appState.anthropicKeyStored)
                            Text(appState.anthropicKeyStored ? "A key is stored in the Keychain." : "No key stored.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("The API is not released yet. The provider reports the honest unavailable state until Anthropic ships it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Verification tool") {
                    TextField("c2patool path", text: $toolPathText)
                        .onSubmit { appState.setC2PAToolPath(toolPathText) }
                    HStack {
                        Button("Save path") { appState.setC2PAToolPath(toolPathText) }
                            .disabled(toolPathText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Text("Current: \(appState.c2paToolPath)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if AppState.toolIsReachable(appState.c2paToolPath) {
                        Label("Tool is reachable", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Label("Tool not found. PNG files are still verified by the built-in reader; other formats need c2patool.", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Text("Path to the c2patool binary, the reference C2PA tool. Leave as c2patool when it is on your PATH. Without it, PNG provenance (the most common AI-image format) is still verified by the built-in reader, though signatures cannot be validated without the tool.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Confidence") {
                    Picker("Threshold preset", selection: $appState.thresholdPreset) {
                        Text("Relaxed").tag(ThresholdPreset.relaxed)
                        Text("Balanced").tag(ThresholdPreset.balanced)
                        Text("Strict").tag(ThresholdPreset.strict)
                    }
                    Text("Minimum reliable text length: \(appState.thresholdPreset.minimumTextLength) characters.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("History") {
                    Toggle("Store raw content with consent", isOn: $appState.storeRawContent)
                    Text("By default only a SHA-256 hash of each input is stored. Raw text is kept only while this is on.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Privacy") {
                    Text("Everything runs locally. No telemetry, no accounts, no cloud. The Anthropic API provider is the only optional network feature and it uses your own key.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Updates") {
                    Button("Check for Updates...") {
                        UpdateController.shared.checkForUpdates(nil)
                    }
                    Toggle("Check for updates automatically", isOn: Binding(
                        get: { UpdateController.shared.automaticallyChecksForUpdates },
                        set: { UpdateController.shared.automaticallyChecksForUpdates = $0 }
                    ))
                    Text("Updates are downloaded from the project's GitHub releases, verified against the published Sparkle signature, and installed only with your approval. Preferences and history survive every update.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("About") {
                    LabeledContent("Version", value: Self.bundleVersion)
                    LabeledContent("Build", value: Self.bundleBuild)
                    Text("OriginCheck answers one question: was this text or file generated by an AI model? Text is scored against local statistical patterns for any model family; files are checked for C2PA provenance metadata. Everything runs on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .padding(24)
        }
        .onAppear {
            // Never prefill the key field, not even with a mask: the field
            // value is what gets saved, so a placeholder could overwrite the
            // real key. The caption already reports whether a key is stored.
            keyText = ""
            toolPathText = appState.c2paToolPath
        }
    }

    /// Version from the packaged Info.plist. A SwiftPM dev build has no
    /// version stamped, so it reads "dev" instead of lying about it.
    private static var bundleVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    private static var bundleBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "dev"
    }
}
