import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        toggleLaunchAtLogin(newValue)
                    }
            }

            Section("Git") {
                HStack {
                    TextField("Git binary path", text: $settings.gitBinaryPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Detect") {
                        if let path = GitCLI.findGitBinary() {
                            settings.gitBinaryPath = path
                        }
                    }
                }
                Text("Default: /usr/bin/git. Requires Xcode Command Line Tools.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section("Summarization") {
                HStack {
                    Text("Max commits to summarize")
                    Spacer()
                    Stepper(
                        "\(settings.maxCommitsToSummarize)",
                        value: $settings.maxCommitsToSummarize,
                        in: 5...200,
                        step: 5
                    )
                }

                Toggle("Defer summarization on battery", isOn: $settings.deferLLMToBattery)

                if settings.deferLLMToBattery {
                    Text("When on battery, new commits are fetched but AI summarization is deferred until plugged in.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Section("About") {
                HStack {
                    Text("GitCanary")
                        .font(.body.weight(.medium))
                    Spacer()
                    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                        Text("v\(version)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func toggleLaunchAtLogin(_ enable: Bool) {
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
