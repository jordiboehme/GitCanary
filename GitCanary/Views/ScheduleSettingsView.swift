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
                        Spacer()
                        Text("\(settings.pollIntervalMinutes) min")
                            .monospacedDigit()
                        Stepper(
                            "",
                            value: $settings.pollIntervalMinutes,
                            in: 1...240,
                            step: settings.pollIntervalMinutes < 10 ? 1 : 5
                        )
                        .labelsHidden()
                    }
                }
            }

            if settings.pollingMode == .scheduled || settings.pollingMode == .both {
                Section {
                    ForEach(settings.scheduledChecks) { schedule in
                        scheduleRow(for: schedule)
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

    private func indexFor(_ schedule: CheckSchedule) -> Int? {
        settings.scheduledChecks.firstIndex(where: { $0.id == schedule.id })
    }

    private func scheduleRow(for schedule: CheckSchedule) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                timePicker(for: schedule)

                Spacer()

                Button(role: .destructive) {
                    let id = schedule.id
                    withAnimation {
                        settings.scheduledChecks.removeAll { $0.id == id }
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(settings.scheduledChecks.count <= 1)
            }

            weekdayPicker(for: schedule)
        }
        .padding(.vertical, 4)
    }

    private func timePicker(for schedule: CheckSchedule) -> some View {
        HStack(spacing: 2) {
            Picker(selection: Binding(
                get: { schedule.hour },
                set: { newValue in
                    if let i = indexFor(schedule) {
                        settings.scheduledChecks[i].hour = newValue
                    }
                }
            )) {
                ForEach(0..<24, id: \.self) { h in
                    Text(String(format: "%02d", h)).tag(h)
                }
            } label: {
                Text(String(format: "%02d", schedule.hour))
                    .monospacedDigit()
            }
            .frame(width: 72)

            Text(":")

            Picker(selection: Binding(
                get: { schedule.minute },
                set: { newValue in
                    if let i = indexFor(schedule) {
                        settings.scheduledChecks[i].minute = newValue
                    }
                }
            )) {
                ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { m in
                    Text(String(format: "%02d", m)).tag(m)
                }
            } label: {
                Text(String(format: "%02d", schedule.minute))
                    .monospacedDigit()
            }
            .frame(width: 72)
        }
        .labelsHidden()
    }

    private func weekdayPicker(for schedule: CheckSchedule) -> some View {
        HStack(spacing: 4) {
            ForEach(weekdaySymbols, id: \.value) { day in
                Toggle(isOn: Binding(
                    get: { schedule.weekdays.contains(day.value) },
                    set: { isOn in
                        if let i = indexFor(schedule) {
                            if isOn {
                                settings.scheduledChecks[i].weekdays.insert(day.value)
                            } else {
                                settings.scheduledChecks[i].weekdays.remove(day.value)
                            }
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
        let symbols = calendar.veryShortWeekdaySymbols
        let firstWeekday = calendar.firstWeekday

        return (0..<7).map { offset in
            let weekday = ((firstWeekday - 1 + offset) % 7) + 1
            return (label: symbols[weekday - 1], value: weekday)
        }
    }
}
