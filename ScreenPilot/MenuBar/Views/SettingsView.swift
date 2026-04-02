import SwiftUI

struct SettingsView: View {
    @Bindable var appState: AppState
    @State private var apiKeyInput: String = ""
    @State private var apiKeySaved = false
    @State private var blocklist: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                apiKeySection
                Divider()
                budgetSection
                Divider()
                modelSection
                Divider()
                blocklistSection
                Divider()
                quitSection
            }
            .padding(16)
        }
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            loadAPIKey()
            blocklist = appState.customBlocklist.sorted().joined(separator: "\n")
        }
    }

    // MARK: - Sections

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("API Key")
                .font(.headline)

            SecureField("sk-ant-...", text: $apiKeyInput)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Save to Keychain") {
                    KeychainHelper.save(apiKey: apiKeyInput)
                    apiKeySaved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        apiKeySaved = false
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(apiKeyInput.isEmpty)

                if apiKeySaved {
                    Text("Saved!")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
    }

    private var budgetSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Daily API Budget")
                .font(.headline)

            HStack {
                Slider(
                    value: Binding(
                        get: { Double(appState.dailyBudgetLimit) },
                        set: {
                            appState.dailyBudgetLimit = Int($0)
                            appState.saveSetting(key: "dailyBudgetLimit", value: "\(appState.dailyBudgetLimit)")
                        }
                    ),
                    in: 100...2000,
                    step: 50
                )
                Text("\(appState.dailyBudgetLimit)")
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 40)
            }

            Text("calls per day")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Model")
                .font(.headline)

            TextField("claude-sonnet-4-20250514", text: Binding(
                get: { appState.selectedModel },
                set: {
                    appState.selectedModel = $0
                    appState.saveSetting(key: "model", value: $0)
                }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
        }
    }

    private var blocklistSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("App Blocklist")
                .font(.headline)

            Text("Bundle IDs to never capture (one per line)")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $blocklist)
                .font(.system(.caption, design: .monospaced))
                .frame(height: 80)
                .border(Color(nsColor: .separatorColor))
                .onChange(of: blocklist) {
                    let entries = Set(
                        blocklist.components(separatedBy: "\n")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                    )
                    appState.customBlocklist = entries
                    appState.saveSetting(key: "customBlocklist", value: blocklist)
                }
        }
    }

    private var quitSection: some View {
        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            HStack {
                Image(systemName: "power")
                Text("Quit ScreenPilot")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }

    // MARK: - Helpers

    private func loadAPIKey() {
        if let key = KeychainHelper.loadAPIKey() {
            apiKeyInput = key
        }
    }
}
