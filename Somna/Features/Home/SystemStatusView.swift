import SwiftUI

/// Readiness screen: whether Somna could record tonight, and what is missing.
///
/// Not a placeholder. This screen earns its place twice — it proves the whole
/// dependency graph is wired end to end today, and in Phase 4 it becomes
/// Settings › Diagnostics, which is the first thing worth asking a beta tester
/// to screenshot when they report a problem.
struct SystemStatusView: View {

    @Environment(\.somna) private var environment
    @State private var store: SystemStatusStore?

    var body: some View {
        ZStack {
            SomnaColor.backgroundPrimary.ignoresSafeArea()
            content
        }
        .accessibilityIdentifier("status.root")
        .navigationTitle(Text(verbatim: "Somna"))
        .task {
            // The store needs the injected environment, which is unavailable
            // until the view is in the hierarchy — hence building it here rather
            // than in an initialiser.
            if store == nil { store = SystemStatusStore(environment: environment) }
            await store?.refresh()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store?.state {
        case .none, .loading:
            LoadingStateView(
                message: String(localized: "status.loading", defaultValue: "Checking readiness…")
            )
        case .failed(let error):
            ErrorStateView(error: error) {
                Task { await store?.refresh() }
            }
        case .ready:
            if let store {
                readyContent(store)
            }
        }
    }

    private func readyContent(_ store: SystemStatusStore) -> some View {
        ScrollView {
            VStack(spacing: SomnaSpacing.l) {
                summaryCard(store)
                permissionsCard(store)
                storageCard(store)
                dataCard(store)
            }
            .padding(SomnaSpacing.l)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Cards

    private func summaryCard(_ store: SystemStatusStore) -> some View {
        SomnaCard {
            if let issue = store.blockingIssue {
                Label {
                    Text(issue.errorDescription ?? "")
                        .font(SomnaFont.cardTitle)
                        .foregroundStyle(SomnaColor.textPrimary)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(SomnaColor.warning)
                }

                if let suggestion = issue.recoverySuggestion {
                    Text(suggestion)
                        .font(SomnaFont.secondary)
                        .foregroundStyle(SomnaColor.textSecondary)
                }

                if store.microphone.canPrompt {
                    Button {
                        Task { await store.requestMicrophoneAccess() }
                    } label: {
                        Text(String(localized: "status.allowMicrophone",
                                    defaultValue: "Allow microphone access"))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else if store.microphone == .permanentlyDenied {
                    // iOS will not prompt again, so offering a request button
                    // here would be a button that does nothing.
                    Button {
                        store.openSystemSettings()
                    } label: {
                        Text(String(localized: "status.openSettings",
                                    defaultValue: "Open iOS Settings"))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            } else {
                Label {
                    Text(String(localized: "status.ready", defaultValue: "Ready to record tonight"))
                        .font(SomnaFont.cardTitle)
                        .foregroundStyle(SomnaColor.textPrimary)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(SomnaColor.success)
                }

                Text(String(
                    localized: "status.readyDetail",
                    defaultValue: "Keep your iPhone plugged in and within a metre of the bed. Do not swipe Somna away while it records."
                ))
                .font(SomnaFont.secondary)
                .foregroundStyle(SomnaColor.textSecondary)
            }
        }
    }

    private func permissionsCard(_ store: SystemStatusStore) -> some View {
        SomnaCard {
            Text(String(localized: "status.permissions", defaultValue: "Permissions"))
                .font(SomnaFont.sectionTitle)
                .foregroundStyle(SomnaColor.textPrimary)

            StatusRow(
                label: String(localized: "status.microphone", defaultValue: "Microphone"),
                value: microphoneDescription(store.microphone),
                state: store.microphone.allowsRecording ? .ok : .problem
            )

            StatusRow(
                label: String(localized: "status.notifications", defaultValue: "Notifications"),
                value: notificationDescription(store.notifications),
                // Optional by design: nothing in Somna depends on them, so a
                // refusal is neutral, never a problem.
                state: store.notifications == .granted ? .ok : .neutral
            )
        }
    }

    private func storageCard(_ store: SystemStatusStore) -> some View {
        SomnaCard {
            Text(String(localized: "status.storage", defaultValue: "Storage"))
                .font(SomnaFont.sectionTitle)
                .foregroundStyle(SomnaColor.textPrimary)

            StatusRow(
                label: String(localized: "status.freeSpace", defaultValue: "Free space"),
                value: store.availableCapacity.formattedByteSize,
                state: store.availableCapacity >= AudioConstants.minimumFreeSpaceToRecord ? .ok : .problem
            )

            StatusRow(
                label: String(localized: "status.recordable", defaultValue: "Room for roughly"),
                value: String(localized: "status.hours",
                              defaultValue: "\(store.estimatedRecordableHours) hours"),
                state: .neutral
            )
        }
    }

    private func dataCard(_ store: SystemStatusStore) -> some View {
        SomnaCard {
            Text(String(localized: "status.data", defaultValue: "Your data"))
                .font(SomnaFont.sectionTitle)
                .foregroundStyle(SomnaColor.textPrimary)

            StatusRow(
                label: String(localized: "status.nights", defaultValue: "Recorded nights"),
                value: "\(store.storedNightCount)",
                state: .neutral
            )

            if store.unfinishedNightCount > 0 {
                StatusRow(
                    label: String(localized: "status.unfinished", defaultValue: "Unfinished nights"),
                    value: "\(store.unfinishedNightCount)",
                    state: .attention
                )
            }

            StatusRow(
                label: String(localized: "status.calibration", defaultValue: "Calibration"),
                value: store.isCalibrationStale
                    ? String(localized: "status.calibrationNeeded", defaultValue: "Not done yet")
                    : String(localized: "status.calibrationDone", defaultValue: "Done"),
                state: store.isCalibrationStale ? .attention : .ok
            )

            Text(String(
                localized: "status.privacyNote",
                defaultValue: "Everything stays on this iPhone. Somna has no account, no server, and never uploads audio."
            ))
            .font(SomnaFont.caption)
            .foregroundStyle(SomnaColor.textTertiary)
        }
    }

    // MARK: - Descriptions

    private func microphoneDescription(_ permission: MicrophonePermission) -> String {
        switch permission {
        case .granted: String(localized: "permission.granted", defaultValue: "Allowed")
        case .undetermined: String(localized: "permission.undetermined", defaultValue: "Not asked yet")
        case .denied, .permanentlyDenied:
            String(localized: "permission.denied", defaultValue: "Blocked in iOS Settings")
        }
    }

    private func notificationDescription(_ permission: NotificationPermission) -> String {
        switch permission {
        case .granted: String(localized: "permission.granted", defaultValue: "Allowed")
        case .provisional: String(localized: "permission.provisional", defaultValue: "Quiet delivery")
        case .undetermined: String(localized: "permission.undetermined", defaultValue: "Not asked yet")
        case .denied: String(localized: "permission.off", defaultValue: "Off")
        }
    }
}

#Preview("Ready") {
    NavigationStack {
        SystemStatusView()
    }
    .environment(\.somna, .preview())
}

#Preview("Microphone blocked") {
    NavigationStack {
        SystemStatusView()
    }
    .environment(\.somna, .preview(microphone: .permanentlyDenied, notifications: .denied))
}
