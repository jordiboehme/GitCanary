import Foundation

extension Notification.Name {
    static let pollingScheduleChanged = Notification.Name("pollingScheduleChanged")
}

enum PollingMode: String, Codable, CaseIterable, Identifiable {
    case interval
    case scheduled
    case both

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .interval: "Interval"
        case .scheduled: "Scheduled"
        case .both: "Both"
        }
    }
}

@Observable
final class AppSettings {
    static let shared = AppSettings()

    var pollingMode: PollingMode {
        didSet {
            save("pollingMode", pollingMode.rawValue)
            notifyScheduleChanged()
        }
    }

    var pollIntervalMinutes: Int {
        didSet {
            save("pollIntervalMinutes", pollIntervalMinutes)
            notifyScheduleChanged()
        }
    }

    var scheduledChecks: [CheckSchedule] {
        didSet {
            saveJSON("scheduledChecks", scheduledChecks)
            notifyScheduleChanged()
        }
    }

    var gitBinaryPath: String {
        didSet { save("gitBinaryPath", gitBinaryPath) }
    }

    var selectedLLMProvider: LLMProviderType {
        didSet { save("selectedLLMProvider", selectedLLMProvider.rawValue) }
    }

    var ollamaBaseURL: String {
        didSet { save("ollamaBaseURL", ollamaBaseURL) }
    }

    var ollamaModel: String {
        didSet { save("ollamaModel", ollamaModel) }
    }

    var claudeModel: String {
        didSet { save("claudeModel", claudeModel) }
    }

    var openAIModel: String {
        didSet { save("openAIModel", openAIModel) }
    }

    var deferLLMToBattery: Bool {
        didSet { save("deferLLMToBattery", deferLLMToBattery) }
    }

    var maxCommitsToSummarize: Int {
        didSet { save("maxCommitsToSummarize", maxCommitsToSummarize) }
    }

    var customPromptInstructions: String {
        didSet { save("customPromptInstructions", customPromptInstructions) }
    }

    var repositorySortOrder: RepositorySortOrder {
        didSet { save("repositorySortOrder", repositorySortOrder.rawValue) }
    }

    private let defaults = UserDefaults.standard

    private init() {
        let d = UserDefaults.standard
        self.pollingMode = PollingMode(rawValue: d.string(forKey: "pollingMode") ?? "") ?? .scheduled
        self.pollIntervalMinutes = d.object(forKey: "pollIntervalMinutes") as? Int ?? 15
        self.scheduledChecks = Self.loadJSON(d, "scheduledChecks") ?? [
            CheckSchedule(hour: 9, minute: 0, weekdays: Set(2...6)),
        ]
        self.gitBinaryPath = d.string(forKey: "gitBinaryPath") ?? "/usr/bin/git"
        let loadedProvider = LLMProviderType(rawValue: d.string(forKey: "selectedLLMProvider") ?? "") ?? .appleIntelligence
        if loadedProvider == .appleIntelligence {
            if #available(macOS 26, *) {
                self.selectedLLMProvider = loadedProvider
            } else {
                self.selectedLLMProvider = .ollama
            }
        } else {
            self.selectedLLMProvider = loadedProvider
        }
        self.ollamaBaseURL = d.string(forKey: "ollamaBaseURL") ?? "http://localhost:11434"
        self.ollamaModel = d.string(forKey: "ollamaModel") ?? "llama3.2"
        self.claudeModel = d.string(forKey: "claudeModel") ?? "claude-sonnet-4-20250514"
        self.openAIModel = d.string(forKey: "openAIModel") ?? "gpt-4o"
        self.deferLLMToBattery = d.bool(forKey: "deferLLMToBattery")
        self.maxCommitsToSummarize = d.object(forKey: "maxCommitsToSummarize") as? Int ?? 50
        self.customPromptInstructions = d.string(forKey: "customPromptInstructions") ?? ""
        self.repositorySortOrder = RepositorySortOrder(rawValue: d.string(forKey: "repositorySortOrder") ?? "") ?? .dateAdded
    }

    private func save(_ key: String, _ value: Any) {
        defaults.set(value, forKey: key)
    }

    private func notifyScheduleChanged() {
        NotificationCenter.default.post(name: .pollingScheduleChanged, object: nil)
    }

    private func saveJSON<T: Encodable>(_ key: String, _ value: T) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private static func loadJSON<T: Decodable>(_ defaults: UserDefaults, _ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
