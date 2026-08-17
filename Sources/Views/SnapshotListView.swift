import SwiftUI

/// The list of restore points.
///
/// Selection lives in the model rather than in the row, so every action is
/// reachable from the menu bar with a shortcut and the list can be driven with
/// arrow keys alone. The previous version put Restore behind a hover state at
/// half opacity, which made the app's main action invisible to anyone not using
/// a mouse — and hard to read for everyone else.
struct SnapshotListView: View {
    @EnvironmentObject private var model: AppModel
    let vm: VirtualMachine

    var body: some View {
        List(selection: $model.selectedSnapshotID) {
            Section {
                ForEach(model.orderedSnapshots) { snapshot in
                    SnapshotRow(
                        snapshot: snapshot,
                        vm: vm,
                        isBaseline: model.isBaseline(snapshot, in: vm)
                    )
                    .tag(snapshot.id)
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    .contextMenu { menu(for: snapshot) }
                }
            } header: {
                HStack {
                    Text("Restore Points")
                    Spacer()
                    Text("\(vm.snapshots.count)")
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        // Return activates the selected row, matching Finder and Mail.
        .onKeyPress(.return) {
            guard let snapshot = model.selectedSnapshot, vm.canModifyDisks, snapshot.isComplete else { return .ignored }
            model.sheet = .restore(snapshot, machine: vm.id, restartAfter: false)
            return .handled
        }
    }

    @ViewBuilder
    private func menu(for snapshot: Snapshot) -> some View {
        Button("Restore…") { model.sheet = .restore(snapshot, machine: vm.id, restartAfter: false) }
            .disabled(!vm.canModifyDisks)
        Button("Restore and Start…") { model.sheet = .restore(snapshot, machine: vm.id, restartAfter: true) }
            .disabled(!vm.canModifyDisks || !vm.isRegisteredWithUTM)

        Divider()

        Button(model.isBaseline(snapshot, in: vm) ? "Remove as Baseline" : "Set as Baseline") {
            model.setBaseline(model.isBaseline(snapshot, in: vm) ? nil : snapshot, for: vm)
        }
        Button("Export…") { Task { await model.exportSnapshot(snapshot, on: vm.id) } }

        Divider()

        Button("Delete…", role: .destructive) { model.sheet = .delete(snapshot, machine: vm.id) }
            .disabled(!vm.canModifyDisks)
    }
}

struct SnapshotRow: View {
    @EnvironmentObject private var model: AppModel

    let snapshot: Snapshot
    let vm: VirtualMachine
    let isBaseline: Bool

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: isBaseline ? "flag.fill" : "clock.arrow.circlepath")
                    .font(.system(size: 16))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isBaseline ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(snapshot.name)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        if isBaseline {
                            Text("Baseline")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(.tint.opacity(0.18)))
                        }
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if !snapshot.isComplete {
                    Label("Incomplete", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                        .help("Missing on \(snapshot.missingFrom.count) of this machine's disks. Restoring is blocked, because it would leave the disks at different points in time.")
                }

                Button("Restore") {
                    model.sheet = .restore(snapshot, machine: vm.id, restartAfter: false)
                }
                .secondaryActionStyle()
                .controlSize(.small)
                .disabled(!vm.canModifyDisks || !snapshot.isComplete)

                Menu {
                    Button("Restore and Start…") { model.sheet = .restore(snapshot, machine: vm.id, restartAfter: true) }
                        .disabled(!vm.canModifyDisks || !vm.isRegisteredWithUTM || !snapshot.isComplete)
                    Button(isBaseline ? "Remove as Baseline" : "Set as Baseline") {
                        model.setBaseline(isBaseline ? nil : snapshot, for: vm)
                    }
                    Button("Export…") { Task { await model.exportSnapshot(snapshot, on: vm.id) } }
                    Divider()
                    Button("Delete…", role: .destructive) { model.sheet = .delete(snapshot, machine: vm.id) }
                        .disabled(!vm.canModifyDisks)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 22)
                .accessibilityLabel("More actions for \(snapshot.name)")
            }

            // Only machines with more than one disk have anything to expand.
            // qcow2 snapshots are flat within an image — the real structure
            // worth showing is which of the machine's disks this point covers.
            if vm.disks.count > 1 {
                DisclosureGroup(isExpanded: $isExpanded) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(vm.disks.enumerated()), id: \.element.id) { index, disk in
                            let present = snapshot.presentOn.contains(disk)
                            Label {
                                Text(disk.displayName(index: index, total: vm.disks.count))
                                    + Text(" · \(disk.fileName)").foregroundStyle(.tertiary)
                            } icon: {
                                Image(systemName: present ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(present ? Color.green : Color.orange)
                            }
                            .font(.caption)
                            .lineLimit(1)
                        }
                    }
                    .padding(.top, 4)
                    .padding(.leading, 34)
                } label: {
                    Text("\(snapshot.diskCount) of \(vm.disks.count) disks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 34)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var subtitle: String {
        var parts = [snapshot.relativeDate, snapshot.absoluteDate]
        if snapshot.stateBytes > 0 { parts.append(snapshot.stateDescription) }
        return parts.joined(separator: " · ")
    }

    private var accessibilityLabel: String {
        var text = snapshot.name
        if isBaseline { text += ", " + String(localized: "baseline") }
        text += ", " + snapshot.absoluteDate
        if !snapshot.isComplete {
            text += ", " + String(localized: "incomplete, present on \(snapshot.diskCount) of \(vm.disks.count) disks")
        }
        return text
    }
}
