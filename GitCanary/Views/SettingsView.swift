import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
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

            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
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
