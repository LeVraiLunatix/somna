import SwiftUI

/// Seven sections, in the order someone looks for them.
///
/// Privacy and Storage sit above Appearance on purpose: in a private beta, the
/// questions that actually get asked are "where is my audio" and "how do I get
/// rid of it", not "can I have a light theme".
struct SettingsView: View {

    @Environment(\.somna) private var environment
    @Environment(AppSettings.self) private var appSettings
    @State private var store: SettingsStore?

    var body: some View {
        Group {
            if let store {
                form(store)
            } else {
                LoadingStateView(message: String(localized: "settings.loading",
                                                 defaultValue: "Loading…"))
            }
        }
        .accessibilityIdentifier("settings.root")
        .navigationTitle(Text(String(localized: "settings.title", defaultValue: "Settings")))
        .task {
            if store == nil {
                store = SettingsStore(environment: environment, appSettings: appSettings)
            }
            await store?.load()
        }
    }

    private func form(_ store: SettingsStore) -> some View {
        @Bindable var store = store

        return Form {
            recording($store)
            notifications(store, binding: $store)
            privacy(store)
            storage(store)
            appearance($store)
            accessibility
            about(store)
        }
        // The system Form's own row colours are chosen against the system
        // grouped background. Hiding that background and painting our own
        // breaks the contrast contract those colours assume — which is what the
        // audit caught here. Settings is the one screen where deferring to the
        // platform beats matching the rest of the app.
        .navigationDestination(for: AppDestination.self) { destination in
            if case .premium = destination { PremiumView() }
        }
        .disabled(store.isWorking)
        .confirmationDialog(
            Text(String(localized: "settings.confirm.title", defaultValue: "Are you sure?")),
            isPresented: Binding(
                get: { store.pendingDeletion != nil },
                set: { if !$0 { store.pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: store.pendingDeletion
        ) { deletion in
            Button(role: .destructive) {
                Task { await store.confirmPendingDeletion() }
            } label: {
                Text(deletion == .everything
                     ? String(localized: "settings.delete.everything.confirm", defaultValue: "Delete everything")
                     : String(localized: "settings.delete.audio.confirm", defaultValue: "Delete raw audio"))
            }
            Button(role: .cancel) {} label: {
                Text(String(localized: "action.cancel", defaultValue: "Cancel"))
            }
        } message: { deletion in
            Text(store.confirmationMessage(for: deletion))
        }
    }

    // MARK: - Recording

    private func recording(_ store: Bindable<SettingsStore>) -> some View {
        Section {
            Picker(
                String(localized: "settings.sensitivity", defaultValue: "Detection sensitivity"),
                selection: store.settings.analysisSensitivity
            ) {
                ForEach(AnalysisSensitivity.allCases, id: \.self) { level in
                    Text(sensitivityTitle(level)).tag(level)
                }
            }

            Toggle(
                String(localized: "settings.highQuality", defaultValue: "Higher audio quality"),
                isOn: store.settings.useHighQualityAudio
            )

            // The wake alarm sits under Recording rather than Notifications
            // because it is not a notification: it rings through Focus and the
            // ring switch, and it ends the night. Filing it with reminders
            // would suggest it can be silenced the same way.
            Toggle(
                String(localized: "settings.wakeAlarm", defaultValue: "Wake alarm"),
                isOn: store.settings.wakeAlarmEnabled
            )

            if store.wrappedValue.settings.wakeAlarmEnabled {
                DatePicker(
                    String(localized: "settings.wakeTime", defaultValue: "Wake me at"),
                    selection: Binding(
                        get: { reminderDate(store.wrappedValue.settings.wakeAlarmMinutes) },
                        set: { store.wrappedValue.settings.wakeAlarmMinutes = minutes(from: $0) }
                    ),
                    displayedComponents: .hourAndMinute
                )

                if store.wrappedValue.wakeAlarmPermission != .granted {
                    Button {
                        Task { await store.wrappedValue.requestWakeAlarmPermission() }
                    } label: {
                        Text(String(localized: "settings.wakeAlarm.allow",
                                    defaultValue: "Allow Somna to ring an alarm"))
                    }
                }
            }

            // The onboarding promises this screen exists. Until now it did not,
            // which made the promise a lie and left anyone who skipped the step
            // without a measured noise floor for good.
            NavigationLink(value: AppDestination.calibration) {
                LabeledContent(
                    String(localized: "settings.calibration", defaultValue: "Room calibration"),
                    value: calibrationSummary(store.wrappedValue)
                )
            }
        } header: {
            Text(String(localized: "settings.section.recording", defaultValue: "Recording"))
        } footer: {
            Text(String(
                localized: "settings.recording.footer",
                defaultValue: "A stricter sensitivity means fewer detections, and the ones you get are surer. Higher quality roughly doubles the space a night uses. The wake alarm rings even in silent mode, and ends the recording when it does."
            ))
        }
    }

    // MARK: - Notifications

    private func notifications(_ store: SettingsStore, binding: Bindable<SettingsStore>) -> some View {
        Section {
            if store.notifications == .undetermined {
                Button {
                    Task { await store.requestNotifications() }
                } label: {
                    Text(String(localized: "settings.enableNotifications",
                                defaultValue: "Turn on notifications"))
                }
            } else if store.notifications == .denied {
                Button {
                    store.openSystemSettings()
                } label: {
                    Text(String(localized: "status.openSettings", defaultValue: "Open iOS Settings"))
                }
            } else {
                Toggle(
                    String(localized: "settings.eveningReminder", defaultValue: "Evening reminder"),
                    isOn: binding.settings.eveningReminderEnabled
                )

                if store.settings.eveningReminderEnabled {
                    DatePicker(
                        String(localized: "settings.reminderTime", defaultValue: "Remind me at"),
                        selection: Binding(
                            get: { reminderDate(store.settings.eveningReminderMinutes) },
                            set: { binding.wrappedValue.settings.eveningReminderMinutes = minutes(from: $0) }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                }

                Toggle(
                    String(localized: "settings.reportReady",
                           defaultValue: "Tell me when a report is ready"),
                    isOn: binding.settings.morningSummaryEnabled
                )

                Toggle(
                    String(localized: "settings.weeklyReport", defaultValue: "Weekly report"),
                    isOn: binding.settings.weeklyReportEnabled
                )

                if store.settings.weeklyReportEnabled {
                    DatePicker(
                        String(localized: "settings.weeklyTime", defaultValue: "Send it on Sunday at"),
                        selection: Binding(
                            get: { reminderDate(store.settings.weeklyReportMinutes) },
                            set: { binding.wrappedValue.settings.weeklyReportMinutes = minutes(from: $0) }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                }
            }
        } header: {
            Text(String(localized: "settings.section.notifications", defaultValue: "Notifications"))
        } footer: {
            Text(String(
                localized: "settings.notifications.footer",
                defaultValue: "Somna never comments on how you slept — it does not know. The report notification is sent when an analysis actually finishes, not on a timer, so it never announces a night you did not record."
            ))
        }
    }

    // MARK: - Privacy

    private func privacy(_ store: SettingsStore) -> some View {
        Section {
            LabeledContent(
                String(localized: "settings.processing", defaultValue: "Processing"),
                value: String(localized: "settings.processing.local", defaultValue: "On this iPhone only")
            )

            // Present, off, and not switchable: the consent exists so the choice
            // is recorded as opt-in from the first version, but v0.1 has no
            // network code at all, so offering the switch would be a lie.
            LabeledContent(
                String(localized: "settings.cloud", defaultValue: "Cloud processing"),
                value: String(localized: "settings.notInThisVersion", defaultValue: "Not in this version")
            )
            LabeledContent(
                String(localized: "settings.analytics", defaultValue: "Analytics"),
                value: String(localized: "settings.none", defaultValue: "None")
            )

            // Promoted out of the section footer. Footer chrome is styled for
            // incidental notes, and the audit measured it below the contrast a
            // sentence like this one needs. What Somna does with someone's
            // recordings is not an incidental note.
            Text(String(
                localized: "settings.privacy.footer",
                defaultValue: "Somna has no account and no server. Nothing is ever uploaded, and no speech is ever transcribed."
            ))
            .font(SomnaFont.secondary)
            .foregroundStyle(SomnaColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            Button(role: .destructive) {
                store.pendingDeletion = .rawAudio
            } label: {
                Text(String(localized: "settings.delete.audio", defaultValue: "Delete raw recordings"))
            }

            Button(role: .destructive) {
                store.pendingDeletion = .everything
            } label: {
                Text(String(localized: "settings.delete.everything", defaultValue: "Delete everything"))
            }
        } header: {
            Text(String(localized: "settings.section.privacy", defaultValue: "Privacy"))
        }
    }

    // MARK: - Storage

    private func storage(_ store: SettingsStore) -> some View {
        Section {
            LabeledContent(
                String(localized: "settings.storage.nights", defaultValue: "Nights"),
                value: "\(store.storage.nightCount)"
            )
            LabeledContent(
                String(localized: "settings.storage.raw", defaultValue: "Raw recordings"),
                value: store.storage.rawAudioBytes.formattedByteSize
            )
            LabeledContent(
                String(localized: "settings.storage.clips", defaultValue: "Event clips"),
                value: store.storage.clipBytes.formattedByteSize
            )
            LabeledContent(
                String(localized: "settings.storage.free", defaultValue: "Free space"),
                value: store.storage.availableBytes.formattedByteSize
            )

            Picker(
                String(localized: "settings.retention", defaultValue: "Keep raw audio for"),
                selection: Bindable(store).settings.retentionPolicy
            ) {
                ForEach(AudioRetentionPolicy.allCases, id: \.self) { policy in
                    Text(retentionTitle(policy)).tag(policy)
                }
            }

            Button {
                Task { await store.applyRetentionNow() }
            } label: {
                Text(String(localized: "settings.applyRetention", defaultValue: "Apply now"))
            }

            if let result = store.lastResult, result.freedBytes > 0 {
                Text(String(
                    localized: "settings.freed",
                    defaultValue: "Freed \(result.freedBytes.formattedByteSize)."
                ))
                .font(SomnaFont.caption)
                .foregroundStyle(SomnaColor.success)
            }
        } header: {
            Text(String(localized: "settings.section.storage", defaultValue: "Storage"))
        } footer: {
            Text(String(
                localized: "settings.storage.footer",
                defaultValue: "A full night is about 115 MB of raw audio, or about 10 MB once only the event clips remain. Clips are never removed by retention — they are what lets you check each detection."
            ))
        }
    }

    // MARK: - Appearance

    private func appearance(_ store: Bindable<SettingsStore>) -> some View {
        Section {
            Picker(
                String(localized: "settings.theme", defaultValue: "Appearance"),
                selection: store.settings.theme
            ) {
                ForEach(ThemePreference.allCases, id: \.self) { theme in
                    Text(themeTitle(theme)).tag(theme)
                }
            }

            Toggle(
                String(localized: "settings.reducedEffects", defaultValue: "Reduce visual effects"),
                isOn: store.settings.reducedVisualEffects
            )
        } header: {
            Text(String(localized: "settings.section.appearance", defaultValue: "Appearance"))
        }
    }

    // MARK: - Accessibility

    /// Read-only on purpose. These are iOS settings, and duplicating them here
    /// would create two switches that disagree.
    private var accessibility: some View {
        Section {
            Text(String(
                localized: "settings.accessibility.body",
                defaultValue: "Somna follows your iOS settings for text size, Reduce Motion, Reduce Transparency and Increase Contrast. Every event is labelled in words, so nothing depends on colour alone, and haptics never carry information on their own."
            ))
            .font(SomnaFont.secondary)
            .foregroundStyle(SomnaColor.textSecondary)
        } header: {
            Text(String(localized: "settings.section.accessibility", defaultValue: "Accessibility"))
        }
    }

    // MARK: - About

    private func about(_ store: SettingsStore) -> some View {
        Section {
            LabeledContent(
                String(localized: "settings.version", defaultValue: "Version"),
                value: store.appVersion
            )
            LabeledContent(
                String(localized: "settings.analysisVersion", defaultValue: "Analysis"),
                value: store.analysisVersion
            )
            LabeledContent(
                String(localized: "settings.channel", defaultValue: "Channel"),
                value: String(localized: "settings.channel.beta", defaultValue: "Private beta")
            )

            NavigationLink(value: AppDestination.premium) {
                Text(String(localized: "settings.premium", defaultValue: "What might come later"))
            }
        } header: {
            Text(String(localized: "settings.section.about", defaultValue: "About"))
        } footer: {
            Text(String(
                localized: "settings.medicalDisclaimer",
                defaultValue: "Somna is not a medical device. It does not diagnose anything, does not detect sleep apnea, and does not measure sleep stages. If you are worried about your sleep, talk to a doctor."
            ))
        }
    }

    // MARK: - Titles

    private func sensitivityTitle(_ level: AnalysisSensitivity) -> String {
        switch level {
        case .conservative: String(localized: "settings.sensitivity.conservative", defaultValue: "Fewer, surer")
        case .balanced: String(localized: "settings.sensitivity.balanced", defaultValue: "Balanced")
        case .sensitive: String(localized: "settings.sensitivity.sensitive", defaultValue: "More detections")
        }
    }

    private func retentionTitle(_ policy: AudioRetentionPolicy) -> String {
        switch policy {
        case .clipsOnly: String(localized: "settings.retention.clipsOnly", defaultValue: "Not at all")
        case .sevenDays: String(localized: "settings.retention.week", defaultValue: "7 days")
        case .thirtyDays: String(localized: "settings.retention.month", defaultValue: "30 days")
        case .ninetyDays: String(localized: "settings.retention.quarter", defaultValue: "90 days")
        case .keepAll: String(localized: "settings.retention.forever", defaultValue: "Keep everything")
        }
    }

    private func themeTitle(_ theme: ThemePreference) -> String {
        switch theme {
        case .system: String(localized: "settings.theme.system", defaultValue: "Follow iOS")
        case .dark: String(localized: "settings.theme.dark", defaultValue: "Dark")
        case .light: String(localized: "settings.theme.light", defaultValue: "Light")
        }
    }

    /// One line summarising calibration, so the row says something before it is
    /// tapped rather than being a door with no sign on it.
    private func calibrationSummary(_ store: SettingsStore) -> String {
        guard let calibration = store.calibration else {
            return String(localized: "settings.calibration.never", defaultValue: "Never measured")
        }
        if store.isCalibrationStale {
            return String(localized: "settings.calibration.stale", defaultValue: "Over a month old")
        }
        return calibration.createdAt.formatted(date: .abbreviated, time: .omitted)
    }

    private func reminderDate(_ minutes: Int) -> Date {
        Calendar.current.date(
            from: DateComponents(hour: minutes / 60, minute: minutes % 60)
        ) ?? Date()
    }

    private func minutes(from date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 22) * 60 + (components.minute ?? 30)
    }
}
