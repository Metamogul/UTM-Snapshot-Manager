import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List(selection: $model.selectedID) {
            Section("Virtual Machines") {
                ForEach(model.machines) { vm in
                    SidebarRow(vm: vm, showsLocation: model.ambiguousNames.contains(vm.name))
                        .tag(vm.id)
                        .contextMenu {
                            Button("Show in Finder") { model.revealInFinder(vm) }
                        }
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
                    Label("Search Again", systemImage: "arrow.clockwise")
                }
                .help("Look for virtual machines (⌘R)")
                .disabled(model.isScanning)
            }
        }
        .safeAreaInset(edge: .bottom) { footer }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if model.isScanning {
                ProgressView().controlSize(.small)
                Text("Searching…")
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
        .help("UTM Snapshot Manager uses qemu-img for every operation.")
    }
}

struct SidebarRow: View {
    let vm: VirtualMachine
    let showsLocation: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: vm.symbolName)
                .font(.system(size: 16))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(vm.name)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer(minLength: 4)

            if vm.isRunning {
                StatusDot(color: .green, label: "Running")
            } else if vm.isSuspended {
                StatusDot(color: .orange, label: "Suspended")
            }
        }
        .padding(.vertical, 3)
    }

    private var subtitle: String {
        if showsLocation { return vm.locationDescription }
        if vm.backend == .apple { return String(localized: "Apple Virtualization") }
        if vm.disks.isEmpty { return String(localized: "No supported disk") }
        switch vm.snapshots.count {
        case 0: return String(localized: "No snapshots")
        case 1: return String(localized: "1 snapshot")
        default: return String(localized: "\(vm.snapshots.count) snapshots")
        }
    }
}

struct StatusDot: View {
    let color: Color
    let label: LocalizedStringKey

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .help(label)
            .accessibilityLabel(Text(label))
    }
}
