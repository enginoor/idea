import SwiftUI
import OriginCheckEngine

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var keyText = ""

    var body: some View {
        @Bindable var appState = appState
        Form {
            Section("Detection providers") {
                Toggle("Local analyzer", isOn: $appState.localAnalyzerEnabled)
                Toggle("Anthropic detection API", isOn: $appState.anthropicProviderEnabled)
                if appState.anthropicProviderEnabled {
                    SecureField("API key", text: $keyText)
                        .onSubmit { appState.saveAnthropicKey(keyText) }
                    HStack {
                        Button("Save key") { appState.saveAnthropicKey(keyText) }
                        Button("Remove key") { appState.clearAnthropicKey(); keyText = "" }
                        Text(appState.hasAnthropicKey ? "A key is stored in the Keychain." : "No key stored.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("The API is not released yet. The provider reports the honest unavailable state until Anthropic ships it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
        }
        .formStyle(.grouped)
        .padding(24)
        .onAppear {
            keyText = appState.hasAnthropicKey ? "••••••••" : ""
        }
    }
}
