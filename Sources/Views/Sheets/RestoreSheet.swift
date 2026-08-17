import SwiftUI

/// Confirms a rollback.
///
/// The confirm button is deliberately *not* the default action. Restoring
/// destroys everything the machine did since the restore point, and a dialog
/// that does that on a stray Return press is a trap — Cancel takes Return here,
/// and the destructive button has to be aimed at or tabbed to.
struct RestoreSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let snapshot: Snapshot
    /// The machine this dialog names. Held rather than re-derived from the
    /// selection, so a rescan behind the sheet cannot move the target.
    let machineID: VirtualMachine.ID
    let restartAfter: Bool

    @State private var keepSafetyCopy = true
    @State private var restart: Bool

    init(snapshot: Snapshot, machineID: VirtualMachine.ID, restartAfter: Bool) {
        self.snapshot = snapshot
        self.machineID = machineID
        self.restartAfter = restartAfter
        _restart = State(initialValue: restartAfter)
    }

    private var vm: VirtualMachine? { model.machines.first { $0.id == machineID } }
    private var needsShutdown: Bool { vm.map { !$0.state.allowsDiskWrites && $0.canStop } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 30, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Restore “\(snapshot.name)”?")
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(explanation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 16)

            // Spells out every step that will happen, in order. A single
            // confirmation that quietly shuts a machine down would be a
            // surprise, however convenient.
            VStack(alignment: .leading, spacing: 8) {
                if needsShutdown {
                    Step(number: 1, text: String(localized: "Shut “\(vm?.name ?? "")” down — a disk cannot be rolled back while in use."))
                }
                if keepSafetyCopy {
                    Step(number: needsShutdown ? 2 : 1, text: String(localized: "Save the current state as a new restore point."))
                }
                Step(
                    number: (needsShutdown ? 1 : 0) + (keepSafetyCopy ? 1 : 0) + 1,
                    text: String(localized: "Roll \(diskPhrase) back to \(snapshot.absoluteDate).")
                )
                if restart {
                    Step(
                        number: (needsShutdown ? 1 : 0) + (keepSafetyCopy ? 1 : 0) + 2,
                        text: String(localized: "Start the machine again.")
                    )
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .noticeSurface(.secondary)

            Toggle(isOn: $keepSafetyCopy) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Save the current state first")
                    Text(safetyDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.checkbox)
            .padding(.top, 14)
            .disabled(mustKeepSafetyCopy)

            if vm?.isRegisteredWithUTM == true {
                Toggle("Start the machine afterwards", isOn: $restart)
                    .toggleStyle(.checkbox)
                    .padding(.top, 8)
            }

            Divider().padding(.vertical, 16)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Restore") {
                    let safety = keepSafetyCopy
                    let restartNow = restart
                    dismiss()
                    Task {
                        await model.restore(
                            snapshot, on: machineID,
                            keepingSafetyCopy: safety, restartAfter: restartNow
                        )
                    }
                }
                .primaryActionStyle()
                .tint(.orange)
                .disabled(!snapshot.isComplete)
            }
        }
        .padding(22)
        .frame(width: 500)
        .onAppear {
            if mustKeepSafetyCopy { keepSafetyCopy = true }
        }
    }

    /// On a multi-disk machine a rollback cannot be undone if it fails halfway,
    /// so the safety copy stops being optional.
    private var mustKeepSafetyCopy: Bool { (vm?.disks.count ?? 1) > 1 }

    private var diskPhrase: String {
        let count = vm?.disks.count ?? 1
        return count > 1
            ? String(localized: "all \(count) disks")
            : String(localized: "the disk")
    }

    private var explanation: String {
        String(localized: "Everything that happened inside the machine since \(snapshot.absoluteDate) will be gone.")
    }

    private var safetyDetail: String {
        mustKeepSafetyCopy
            ? String(localized: "Required for machines with several disks: if a rollback fails partway it cannot be undone, and this is the only way back.")
            : String(localized: "Recommended. Creates an extra restore point so this step stays reversible.")
    }
}

private struct Step: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(.secondary))
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

struct DeleteSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let snapshot: Snapshot
    let machineID: VirtualMachine.ID

    private var vm: VirtualMachine? { model.machines.first { $0.id == machineID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "trash")
                    .font(.system(size: 28, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Delete “\(snapshot.name)”?")
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("This restore point is removed and the space it occupies is freed. The machine itself and its current state stay exactly as they are.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let vm, model.isBaseline(snapshot, in: vm) {
                Label("This is the baseline for “\(vm.name)”. Deleting it clears that mark.", systemImage: "flag.slash")
                    .font(.callout)
                    .padding(.top, 14)
            }

            Divider().padding(.vertical, 16)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Delete") {
                    dismiss()
                    Task { await model.delete(snapshot, on: machineID) }
                }
                .primaryActionStyle()
                .tint(.red)
            }
        }
        .padding(22)
        .frame(width: 470)
    }
}

struct CheckReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let lines: [String]

    private var allHealthy: Bool { lines.allSatisfy { $0.hasPrefix("✔︎") } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: allHealthy ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 28, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(allHealthy ? .green : .orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(allHealthy ? "Disks Are Healthy" : "A Disk Needs Attention")
                        .font(.title3.weight(.semibold))
                    Text("qemu-img read every block. Nothing was modified.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: 260)
            .noticeSurface(.secondary)

            Divider().padding(.vertical, 16)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .primaryActionStyle()
            }
        }
        .padding(22)
        .frame(width: 560)
    }
}

/// Explains the one permission the app cannot work around, and why it refuses
/// to guess instead.
struct AutomationHelpSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 28, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Let This App Ask UTM")
                        .font(.title3.weight(.semibold))
                    Text("UTM is the only reliable source for whether a machine is running or merely paused. Both are unsafe to write to, and without an answer this app will not touch a disk at all.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 10) {
                Step(number: 1, text: String(localized: "Open System Settings › Privacy & Security › Automation."))
                Step(number: 2, text: String(localized: "Find “UTM Snapshot Manager” in the list."))
                Step(number: 3, text: String(localized: "Switch on “UTM”."))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .noticeSurface(.secondary)

            Divider().padding(.vertical, 16)

            HStack {
                Button("Open Automation Settings") { model.openAutomationSettings() }
                Spacer()
                Button("Check Again") {
                    dismiss()
                    Task { await model.refresh() }
                }
                .keyboardShortcut(.defaultAction)
                .primaryActionStyle()
            }
        }
        .padding(22)
        .frame(width: 500)
    }
}
