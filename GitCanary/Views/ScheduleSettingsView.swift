import SwiftUI

struct ScheduleSettingsView: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Polling Mode") {
                Picker("Mode", selection: $settings.pollingMode) {
                    ForEach(PollingMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                switch settings.pollingMode {
                case .interval:
                    Text("Check all repositories at a fixed interval.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .scheduled:
                    Text("Check at specific times on selected days.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .both:
                    Text("Combine interval polling with scheduled checks.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if settings.pollingMode == .interval || settings.pollingMode == .both {
                Section("Interval") {
                    HStack {
                        Text("Check every")
                        Stepper(
                            "\(settings.pollIntervalMinutes) min",
                            value: $settings.pollIntervalMinutes,
                            in: 1...240,
                            step: settings.pollIntervalMinutes < 10 ? 1 : 5
                        )
                    }
                }
            }

            if settings.pollingMode == .scheduled || settings.pollingMode == .both {
                Section {
                    ForEach(settings.scheduledChecks.indices, id: \.self) { index in
                        scheduleRow(index: index)
                    }

                    Button("Add Schedule") {
                        withAnimation {
                            settings.scheduledChecks.append(
                                CheckSchedule(hour: 9, minute: 0, weekdays: Set(2...6))
                            )
                        }
                    }
                } header: {
                    Text("Scheduled Times")
                } footer: {
                    Text("Missed schedules are caught up automatically when your Mac wakes or gains connectivity.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func scheduleRow(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                timePicker(index: index)

                Spacer()

                Button(role: .destructive) {
                    withAnimation {
                        _ = settings.scheduledChecks.remove(at: index)
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(settings.scheduledChecks.count <= 1)
            }

            weekdayPicker(index: index)
        }
        .padding(.vertical, 4)
    }

    private func timePicker(index: Int) -> some View {
        HStack(spacing: 2) {
            Picker(selection: Binding(
                get: { settings.scheduledChecks[index].hour },
                set: { settings.scheduledChecks[index].hour = $0 }
            )) {
                ForEach(0..<24, id: \.self) { h in
                    Text(String(format: "%02d", h)).tag(h)
                }
            } label: {
                Text(String(format: "%02d", settings.scheduledChecks[index].hour))
                    .monospacedDigit()
            }
            .frame(width: 72)

            Text(":")

            Picker(selection: Binding(
                get: { settings.scheduledChecks[index].minute },
                set: { settings.scheduledChecks[index].minute = $0 }
            )) {
                ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { m in
                    Text(String(format: "%02d", m)).tag(m)
                }
            } label: {
                Text(String(format: "%02d", settings.scheduledChecks[index].minute))
                    .monospacedDigit()
            }
            .frame(width: 72)
        }
        .labelsHidden()
    }

    private func weekdayPicker(index: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(weekdaySymbols, id: \.value) { day in
                Toggle(isOn: Binding(
                    get: { settings.scheduledChecks[index].weekdays.contains(day.value) },
                    set: { isOn in
                        if isOn {
                            settings.scheduledChecks[index].weekdays.insert(day.value)
                        } else {
                            settings.scheduledChecks[index].weekdays.remove(day.value)
                        }
                    }
                )) {
                    Text(day.label)
                        .font(.caption2.weight(.medium))
                        .frame(width: 24, height: 24)
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var weekdaySymbols: [(label: String, value: Int)] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortWeekdaySymbols // Localized: ["S","M","T",…] or ["M","D","M",…]
        let firstWeekday = calendar.firstWeekday // 1=Sunday (US), 2=Monday (DE), etc.

        // Calendar weekday indices: 1=Sunday, 2=Monday, …, 7=Saturday
        // Reorder to start from the locale's first weekday
        return (0..<7).map { offset in
            let weekday = ((firstWeekday - 1 + offset) % 7) + 1 // 1-based
            return (label: symbols[weekday - 1], value: weekday)
        }
    }
}
