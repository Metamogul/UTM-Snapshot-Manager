import SwiftUI

struct VMDetailView: View {
    @EnvironmentObject private var model: AppModel
    let vm: VirtualMachine

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle(vm.name)
        .navigationSubtitle(vm.locationDescription)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.beginNewSnapshot()
                } label: {
                    Label("Take Snapshot", systemImage: "plus")
                }
                .disabled(!vm.canSnapshot)
                .help(vm.canSnapshot ? "Save the current state (⌘N)" : "Not possible right now")
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: vm.symbolName)
                    .font(.system(size: 34, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 3) {
                    Text(vm.name)
                        .font(.title2.weight(.semibold))
                    Text(metaLine)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    model.beginNewSnapshot()
                } label: {
                    Label("Take Snapshot", systemImage: "camera.aperture")
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!vm.canSnapshot)
            }

            if let blocker = vm.blocker {
                BlockerBanner(blocker: blocker, vmName: vm.name)
            } else {
                Text("A snapshot freezes the current state of the disk. You can return to it at any time.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }

    private var metaLine: String {
        var parts: [String] = []
        parts.append(String(localized: "\(vm.usedDescription) used of \(vm.virtualDescription)"))
        if vm.disks.count > 1 {
            parts.append(String(localized: "\(vm.disks.count) disks"))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if vm.snapshots.isEmpty {
            emptyState
        } else {
            List {
                Section {
                    ForEach(vm.snapshots) { snapshot in
                        SnapshotRow(snapshot: snapshot, canRestore: vm.canSnapshot)
                            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    }
                } header: {
                    Text("Restore Points")
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Snapshots Yet", systemImage: "camera.aperture")
        } description: {
            Text("Save the current state before you try something risky inside the VM. Getting back then takes a single click.")
        } actions: {
            Button("Take Snapshot") { model.beginNewSnapshot() }
                .buttonStyle(.borderedProminent)
                .disabled(!vm.canSnapshot)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Explains in plain language why the buttons are unavailable — instead of
/// leaving the user with a greyed-out control and no reason.
struct BlockerBanner: View {
    let blocker: VirtualMachine.Blocker
    let vmName: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(message).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var tint: Color {
        switch blocker {
        case .running, .suspended: return .orange
        default: return .secondary
        }
    }

    private var symbol: String {
        switch blocker {
        case .running: return "play.circle.fill"
        case .suspended: return "pause.circle.fill"
        case .appleBackend: return "apple.logo"
        case .noSupportedDisk: return "externaldrive.badge.questionmark"
        case .noAccess: return "lock.fill"
        }
    }

    private var title: String {
        switch blocker {
        case .running: return String(localized: "“\(vmName)” is running right now")
        case .suspended: return String(localized: "“\(vmName)” is suspended")
        case .appleBackend: return String(localized: "Snapshots aren't possible here")
        case .noSupportedDisk: return String(localized: "No supported disk")
        case .noAccess: return String(localized: "No access to this folder")
        }
    }

    private var message: String {
        switch blocker {
        case .running:
            return String(localized: "Shut the machine down in UTM before saving or restoring. Snapshotting a running VM risks a corrupted file system, because unwritten caches never reach the disk.")
        case .suspended:
            return String(localized: "UTM has parked the memory state on disk. Start the machine and shut it down properly, then you're good to go.")
        case .appleBackend:
            return String(localized: "This machine uses Apple Virtualization instead of QEMU. Its disk format has no notion of snapshots.")
        case .noSupportedDisk:
            return String(localized: "This machine has no disk in qcow2 format.")
        case .noAccess:
            return String(localized: "Grant UTM Snapshot Manager access to this folder under System Settings › Privacy & Security › Files and Folders.")
        }
    }
}
