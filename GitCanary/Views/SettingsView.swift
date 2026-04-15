import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            RepositorySettingsView()
                .tabItem {
                    Label("Repositories", systemImage: "folder.badge.gearshape")
                }

            ScheduleSettingsView()
                .tabItem {
                    Label("Schedule", systemImage: "clock")
                }

            LLMSettingsView()
                .tabItem {
                    Label("AI Provider", systemImage: "sparkles")
                }

            CustomPromptView()
                .tabItem {
                    Label("Customize Prompt", systemImage: "text.quote")
                }

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 480, height: 400)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
