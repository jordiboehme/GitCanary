import SwiftUI

struct LLMSettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var claudeKey: String = KeychainManager.loadAPIKey(for: .claude) ?? ""
    @State private var openAIKey: String = KeychainManager.loadAPIKey(for: .openai) ?? ""
    @State private var testingConnection = false
    @State private var connectionStatus: String?

    var body: some View {
        Form {
            providerPicker

            switch settings.selectedLLMProvider {
            case .appleIntelligence:
                appleIntelligenceSection
            case .ollama:
                ollamaSection
            case .claude:
                claudeSection
            case .openai:
                openAISection
            }

            customInstructionsSection
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Provider Picker

    private var providerPicker: some View {
        Section {
            Picker("Provider", selection: $settings.selectedLLMProvider) {
                ForEach(LLMProviderType.allCases) { provider in
                    HStack(spacing: 6) {
                        Image(systemName: provider.icon)
                            .frame(width: 16)
                        Text(provider.displayName)
                        if provider.isLocal {
                            Text("Local")
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.green.opacity(0.15))
                                .foregroundStyle(.green)
                                .clipShape(Capsule())
                        } else {
                            Text("Cloud")
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.orange.opacity(0.15))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                    }
                    .tag(provider)
                }
            }
            .pickerStyle(.radioGroup)
        } header: {
            Text("Summarization Provider")
        } footer: {
            if !settings.selectedLLMProvider.isLocal {
                Label(
                    "Commit messages and diffs will be sent to \(settings.selectedLLMProvider.displayName) servers.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Apple Intelligence

    private var appleIntelligenceSection: some View {
        Section("Apple Intelligence") {
            HStack {
                Image(systemName: "apple.intelligence")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("On-device processing")
                        .font(.caption.weight(.medium))
                    Text("Requires macOS 26 with Apple Intelligence enabled.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Ollama

    private var ollamaSection: some View {
        Section("Ollama") {
            TextField("Base URL", text: $settings.ollamaBaseURL)
                .textFieldStyle(.roundedBorder)

            TextField("Model", text: $settings.ollamaModel)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Test Connection") {
                    testOllamaConnection()
                }
                .disabled(testingConnection)

                if testingConnection {
                    ProgressView()
                        .controlSize(.small)
                }

                if let status = connectionStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(status.contains("OK") ? .green : .orange)
                }
            }

            Text("Ollama can run locally or on any machine on your network (e.g., Raspberry Pi, NAS). Data stays within your trusted environment.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Claude

    private var claudeSection: some View {
        Section("Claude API") {
            SecureField("API Key", text: $claudeKey)
                .textFieldStyle(.roundedBorder)
                .onChange(of: claudeKey) { _, newValue in
                    saveKey(newValue, for: .claude)
                }

            TextField("Model", text: $settings.claudeModel)
                .textFieldStyle(.roundedBorder)

            privacyWarning
        }
    }

    // MARK: - OpenAI

    private var openAISection: some View {
        Section("OpenAI API") {
            SecureField("API Key", text: $openAIKey)
                .textFieldStyle(.roundedBorder)
                .onChange(of: openAIKey) { _, newValue in
                    saveKey(newValue, for: .openai)
                }

            TextField("Model", text: $settings.openAIModel)
                .textFieldStyle(.roundedBorder)

            privacyWarning
        }
    }

    private var privacyWarning: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "lock.open")
                .foregroundStyle(.orange)
                .font(.caption)
            Text("Repository data (commit messages, diffs) will be sent to external servers. Only use this provider if you trust them with your codebase data.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.orange.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Custom Instructions

    private var customInstructionsSection: some View {
        Section {
            TextEditor(text: $settings.customPromptInstructions)
                .font(.body)
                .frame(minHeight: 60, maxHeight: 120)
                .scrollContentBackground(.hidden)
        } header: {
            Text("Custom Instructions")
        } footer: {
            Text("Guide what the summary focuses on, e.g. \"Focus on bug fixes and who authored them\" or \"Emphasize user-facing changes\".")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func saveKey(_ key: String, for provider: LLMProviderType) {
        if key.isEmpty {
            try? KeychainManager.deleteAPIKey(for: provider)
        } else {
            try? KeychainManager.saveAPIKey(key, for: provider)
        }
    }

    private func testOllamaConnection() {
        testingConnection = true
        connectionStatus = nil

        Task {
            let service = OllamaService(
                baseURL: settings.ollamaBaseURL,
                model: settings.ollamaModel
            )
            let available = await service.isAvailable
            testingConnection = false
            connectionStatus = available ? "OK — Connected" : "Cannot reach Ollama"
        }
    }
}
