import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List(selection: $model.selectedMachineID) {
            Section("Virtual Machines") {
                // An empty sidebar with no explanation is the worst possible
                // state: it looks like the app lost the machines.
                if model.machines.isEmpty {
                    Text(emptyLabel)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(model.machines) { vm in
                    SidebarRow(vm: vm, showsLocation: model.ambiguousNames.contains(vm.name))
                        .tag(vm.id)
                        .contextMenu { contextMenu(for: vm) }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("UTM Snapshot Manager")
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .help("Search for virtual machines again (⌘R)")
                .disabled(model.isScanning || model.activity != nil)
            }
        }
        .safeAreaInset(edge: .bottom) { footer }
    }

    @ViewBuilder
    private func contextMenu(for vm: VirtualMachine) -> some View {
        if vm.canStart {
            Button("Start") { Task { await model.start(vm) } }
        }
        if vm.canStop {
            Button("Shut Down") { Task { await model.stop(vm, method: .request) } }
        }
        Divider()
        Button("Show in Finder") { model.revealInFinder(vm) }
        if UTMControl.isInstalled {
            Button("Open in UTM") { model.openUTM() }
        }
    }

    /// Says which of the three it is, because "Searching…" forever is how a
    /// waiting permission dialog looks from the inside.
    private var emptyLabel: LocalizedStringKey {
        if model.permissionPending { return "Waiting for your answer to macOS's permission dialog…" }
        if model.isScanning { return "Searching…" }
        return "No machines found"
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if model.permissionPending {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(.orange)
                Text("Permission dialog open")
                    .lineLimit(1)
            } else if model.isScanning {
                ProgressView().controlSize(.small)
                Text("Searching…")
            } else if model.scanWasIncomplete {
                Image(systemName: "clock.badge.exclamationmark")
                    .foregroundStyle(.orange)
                Text("Last search timed out — list kept")
                    .lineLimit(1)
            } else {
                Image(systemName: "checkmark.seal")
                    .foregroundStyle(.secondary)
                Text(model.qemuVersion ?? "QEMU ready")
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .help("Every snapshot operation runs through qemu-img.")
    }
}

struct SidebarRow: View {
    let vm: VirtualMachine
    let showsLocation: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: vm.symbolName)
                .font(.system(size: 15))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(vm.name)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    // Head truncation on a path keeps the folder that actually
                    // distinguishes two machines with the same name.
                    .truncationMode(showsLocation ? .head : .tail)
            }

            Spacer(minLength: 4)

            if vm.state != .stopped {
                StateChip(state: vm.state, compact: true)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(vm.name), \(vm.state.label), \(subtitle)")
    }

    private var subtitle: String {
        if !vm.hasAccess { return String(localized: "No access — permission needed") }
        if showsLocation { return vm.locationDescription }
        if vm.backend == .apple { return String(localized: "Apple Virtualization") }
        if vm.disks.isEmpty { return String(localized: "No supported disk") }
        switch vm.snapshots.count {
        case 0: return String(localized: "No restore points")
        case 1: return String(localized: "1 restore point")
        default: return String(localized: "\(vm.snapshots.count) restore points")
        }
    }
}
