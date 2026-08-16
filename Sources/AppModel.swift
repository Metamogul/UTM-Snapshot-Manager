import SwiftUI

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
final class AppModel: ObservableObject {

    @Published var machines: [VirtualMachine] = []
    @Published var selectedID: VirtualMachine.ID?
    @Published var qemuImgPath: String?
    @Published var qemuVersion: String?

    @Published var isScanning = false
    @Published var busyTitle: String?
    @Published var alert: AppAlert?

    @Published var isCreatingSnapshot = false
    @Published var snapshotPendingRestore: Snapshot?
    @Published var snapshotPendingDeletion: Snapshot?
    @Published var showsWelcome = false
    /// macOS is showing a folder-permission dialog the user hasn't answered.
    @Published var awaitingPermission = false
    /// Standard folders macOS is currently blocking.
    @Published var restrictedFolders: [String] = []

    private var hasLoadedOnce = false
    private let welcomeKey = "hasSeenWelcome"

    var selected: VirtualMachine? {
        machines.first { $0.id == selectedID }
    }

    var isReady: Bool { qemuImgPath != nil }

    /// Names that appear more than once — we then show the folder instead,
    /// so two machines called "Debian 12" stay distinguishable.
    var ambiguousNames: Set<String> {
        var seen = Set<String>()
        var duplicates = Set<String>()
        for machine in machines {
            if !seen.insert(machine.name).inserted { duplicates.insert(machine.name) }
        }
        return duplicates
    }

    // MARK: - Loading

    func bootstrap() async {
        guard !hasLoadedOnce else { return }
        hasLoadedOnce = true
        if !UserDefaults.standard.bool(forKey: welcomeKey) {
            showsWelcome = true
        }
        await checkPrerequisites()
        await refresh()
    }

    func markWelcomeSeen() {
        UserDefaults.standard.set(true, forKey: welcomeKey)
    }

    func checkPrerequisites() async {
        let path = QemuImg.locate()
        qemuImgPath = path
        qemuVersion = path.flatMap { QemuImg.version(at: $0) }
    }

    func refresh() async {
        guard let qemuImg = qemuImgPath else { return }
        isScanning = true
        let result = await VMDiscovery.scan(qemuImg: qemuImg)
        machines = result.machines
        awaitingPermission = result.awaitingPermission
        restrictedFolders = result.restrictedFolders
        if selectedID == nil || !machines.contains(where: { $0.id == selectedID }) {
            selectedID = machines.first?.id
        }
        isScanning = false
    }

    // MARK: - Actions

    func beginNewSnapshot() {
        guard selected?.canSnapshot == true else { return }
        isCreatingSnapshot = true
    }

    func createSnapshot(named name: String) async {
        guard let vm = selected, let qemuImg = qemuImgPath else { return }
        defer { busyTitle = nil }

        do {
            try await ensureSafe(vm)
            busyTitle = String(localized: "Saving “\(name)”…")
            for disk in vm.disks {
                try await QemuImg.createSnapshot(qemuImg: qemuImg, disk: disk, name: name, vmName: vm.name)
            }
            await refresh()
        } catch {
            present(error)
            await refresh()
        }
    }

    func restore(_ snapshot: Snapshot, keepingSafetyCopy: Bool) async {
        guard let vm = selected, let qemuImg = qemuImgPath else { return }
        defer { busyTitle = nil }

        do {
            try await ensureSafe(vm)

            if keepingSafetyCopy {
                let safetyName = uniqueName(base: String(localized: "Automatic backup"), in: vm)
                busyTitle = String(localized: "Saving the current state…")
                for disk in vm.disks {
                    try await QemuImg.createSnapshot(qemuImg: qemuImg, disk: disk, name: safetyName, vmName: vm.name)
                }
            }

            busyTitle = String(localized: "Restoring “\(snapshot.name)”…")
            for disk in vm.disks {
                try await QemuImg.restoreSnapshot(qemuImg: qemuImg, disk: disk, name: snapshot.name, vmName: vm.name)
            }
            await refresh()
        } catch {
            present(error)
            await refresh()
        }
    }

    func delete(_ snapshot: Snapshot) async {
        guard let vm = selected, let qemuImg = qemuImgPath else { return }
        defer { busyTitle = nil }

        do {
            try await ensureSafe(vm)
            busyTitle = String(localized: "Deleting “\(snapshot.name)”…")
            for disk in vm.disks {
                try await QemuImg.deleteSnapshot(qemuImg: qemuImg, disk: disk, name: snapshot.name, vmName: vm.name)
            }
            await refresh()
        } catch {
            present(error)
            await refresh()
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
            NSWorkspace.shared.open(url)
        }
    }

    func revealInFinder(_ vm: VirtualMachine) {
        NSWorkspace.shared.activateFileViewerSelecting([vm.url])
    }

    /// Final safety check immediately before writing: the VM may have been
    /// started since the last scan. Writing to a running machine is the most
    /// reliable way to end up with a corrupted file system.
    private func ensureSafe(_ vm: VirtualMachine) async throws {
        busyTitle = String(localized: "Running safety check…")
        if await VMDiscovery.isRunning(vm) {
            throw QemuImgError.locked(vm: vm.name)
        }
    }

    // MARK: - Names

    func suggestedSnapshotName() -> String {
        guard let vm = selected else { return String(localized: "State") }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "d MMM yyyy 'at' HH.mm"
        return uniqueName(base: String(localized: "State from \(formatter.string(from: Date()))"), in: vm)
    }

    func validationMessage(for name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return String(localized: "Give the snapshot a name.") }
        if trimmed.count > 100 { return String(localized: "That name is too long.") }
        if Int(trimmed) != nil { return String(localized: "The name cannot consist of digits only.") }
        if trimmed.lowercased() == "suspend" { return String(localized: "This name is reserved by UTM.") }
        if let vm = selected, vm.snapshots.contains(where: { $0.name == trimmed }) {
            return String(localized: "A snapshot with this name already exists.")
        }
        return nil
    }

    private func uniqueName(base: String, in vm: VirtualMachine) -> String {
        let existing = Set(vm.snapshots.map(\.name))
        guard existing.contains(base) else { return base }
        var index = 2
        while existing.contains("\(base) (\(index))") { index += 1 }
        return "\(base) (\(index))"
    }

    // MARK: - Errors

    private func present(_ error: Error) {
        if let qemuError = error as? QemuImgError {
            alert = AppAlert(
                title: qemuError.errorDescription ?? String(localized: "Something went wrong"),
                message: qemuError.recoverySuggestion ?? ""
            )
        } else {
            alert = AppAlert(title: String(localized: "Something went wrong"), message: error.localizedDescription)
        }
    }
}
