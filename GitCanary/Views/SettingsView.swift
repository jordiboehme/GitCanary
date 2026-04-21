import SwiftUI

struct SettingsView: View {
    @State private var navigator = SettingsNavigator.shared
    @State private var selectedTab: String = "general"

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag("general")

            RepositorySettingsView()
                .tabItem {
                    Label("Repositories", systemImage: "folder.badge.gearshape")
                }
                .tag("repositories")

            ScheduleSettingsView()
                .tabItem {
                    Label("Schedule", systemImage: "clock")
                }
                .tag("schedule")

            LLMSettingsView()
                .tabItem {
                    Label("AI Provider", systemImage: "sparkles")
                }
                .tag("llm")

            CustomPromptView()
                .tabItem {
                    Label("Customize Prompt", systemImage: "text.quote")
                }
                .tag("prompt")

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag("about")
        }
        .frame(width: 480, height: 400)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            applyNavigator()
        }
        .onChange(of: navigator.targetRepositoriesTab) {
            applyNavigator()
        }
    }

    private func applyNavigator() {
        if navigator.targetRepositoriesTab {
            selectedTab = "repositories"
            navigator.targetRepositoriesTab = false
        }
    }
}
