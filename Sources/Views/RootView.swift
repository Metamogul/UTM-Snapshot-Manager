import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.isReady {
                MainSplitView()
            } else {
                SetupView()
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .alert(item: $model.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text(alert.isCritical ? "I understand" : "OK"))
            )
        }
        .sheet(isPresented: $model.showsWelcome, onDismiss: { model.markWelcomeSeen() }) {
            WelcomeView()
        }
        .sheet(item: $model.sheet) { route in
            sheet(for: route).environmentObject(model)
        }
        .onAppear { model.startPollingIfNeeded() }
        .onDisappear { model.stopPolling() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            Task { await model.applicationBecameActive() }
        }
    }

    @ViewBuilder
    private func sheet(for route: SheetRoute) -> some View {
        switch route {
        case .newSnapshot(let machineID):
            NewSnapshotSheet(machineID: machineID)
        case .restore(let snapshot, let machineID, let restartAfter):
            RestoreSheet(snapshot: snapshot, machineID: machineID, restartAfter: restartAfter)
        case .delete(let snapshot, let machineID):
            DeleteSheet(snapshot: snapshot, machineID: machineID)
        case .checkReport(let lines):
            CheckReportSheet(lines: lines)
        case .automationHelp:
            AutomationHelpSheet()
        }
    }
}

struct MainSplitView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
        } detail: {
            detail
        }
        .overlay(alignment: .top) { notices }
        .overlay { ActivityOverlay(activity: model.activity) }
        // Runs after the view update that changed the selection, so it cannot
        // mutate published state mid-pass.
        .onChange(of: model.selectedMachineID, initial: true) {
            model.syncSnapshotSelection()
        }
    }

    // MARK: - Notices

    @ViewBuilder
    private var notices: some View {
        VStack(spacing: 8) {
            if model.permissionPending {
                NoticeBar(
                    icon: "hand.raised.fill",
                    tint: .orange,
                    title: String(localized: "macOS is asking you for permission"),
                    detail: String(localized: "A dialog is waiting for an answer. Until it is answered, folders cannot be read and this list stays short.")
                ) {
                    Button("Check Again") { Task { await model.refresh() } }
                        .primaryActionStyle()
                }
            }

            if model.utmLibraryUnreadable {
                NoticeBar(
                    icon: "questionmark.folder",
                    tint: .orange,
                    title: String(localized: "UTM's library could not be read"),
                    detail: String(localized: "Without it, a duplicated machine cannot be told from the original — so starting and stopping stay off. Snapshots still work; every one is checked against UTM and the running processes first.")
                ) {
                    Button("Rescan") { Task { await model.refresh() } }
                        .primaryActionStyle()
                }
            }

            if !model.restrictedFolders.isEmpty {
                NoticeBar(
                    icon: "lock.fill",
                    tint: .orange,
                    title: String(localized: "macOS is blocking \(model.restrictedFolders.formatted(.list(type: .and)))"),
                    detail: String(localized: "Machines stored there stay invisible until you allow access.")
                ) {
                    Button("Open Settings…") { model.openPrivacySettings() }
                    Button("Check Again") { Task { await model.refresh() } }
                        .primaryActionStyle()
                }
            }

            if model.utmAvailability == .denied {
                NoticeBar(
                    icon: "hand.raised.fill",
                    tint: .orange,
                    title: String(localized: "UTM is not letting this app check machine states"),
                    detail: String(localized: "Without that check, writing to a disk is not safe — so all changes stay disabled.")
                ) {
                    Button("How to fix") { model.sheet = .automationHelp }
                        .primaryActionStyle()
                }
            }

            if let outcome = model.lastOutcome {
                NoticeBar(
                    icon: "checkmark.circle.fill",
                    tint: .green,
                    title: outcome,
                    detail: nil
                ) {
                    Button("Dismiss") { model.lastOutcome = nil }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(12)
        .animation(.snappy, value: model.lastOutcome)
        .animation(.snappy, value: model.restrictedFolders)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let vm = model.selectedMachine {
            MachineDetailView(vm: vm).id(vm.id)
        } else if model.isScanning {
            ProgressView("Looking for virtual machines…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label("No Virtual Machines Found", systemImage: "desktopcomputer.trianglebadge.exclamationmark")
            } description: {
                Text("Your Mac was searched automatically — UTM's own folder, your Documents, Downloads and Desktop. Machines on network volumes and in protected folders like Pictures are skipped on purpose.")
            } actions: {
                Button("Search Again") { Task { await model.refresh() } }
                    .primaryActionStyle()
                if UTMControl.isInstalled {
                    Button("Open UTM") { model.openUTM() }
                }
            }
        }
    }
}

// MARK: - Notice bar

struct NoticeBar<Actions: View>: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String?
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)
            actions.controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 760)
        .noticeSurface(tint)
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }
}

// MARK: - Activity

/// Blocks the interface while something is in flight, so two operations can
/// never run against the same disk at once. Shows elapsed time, because a
/// snapshot of a 60 GB image is slow enough that a bare spinner reads as a hang.
struct ActivityOverlay: View {
    let activity: Activity?

    var body: some View {
        if let activity {
            ZStack {
                Rectangle()
                    .fill(.black.opacity(0.15))
                    .ignoresSafeArea()

                VStack(spacing: 14) {
                    ProgressView().controlSize(.large)

                    Text(activity.title)
                        .font(.headline)
                        .multilineTextAlignment(.center)

                    if let detail = activity.detail {
                        Text(detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    TimelineView(.periodic(from: activity.startedAt, by: 1)) { context in
                        let elapsed = Int(context.date.timeIntervalSince(activity.startedAt))
                        if elapsed >= 3 {
                            Text("\(elapsed) s elapsed — this is not stuck.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                        }
                    }
                }
                .padding(30)
                .frame(maxWidth: 380)
                .glassCard(cornerRadius: 18)
                .shadow(radius: 24, y: 10)
            }
            .transition(.opacity)
        }
    }
}
