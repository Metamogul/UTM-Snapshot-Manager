import AppKit
import SwiftUI

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    /// Critical alerts describe a machine left in a broken state. They are
    /// styled and worded so they cannot be mistaken for a routine hiccup.
    var isCritical = false
}

/// Something long-running is happening. Writes are not cancellable — pulling
/// the rug out from under `qemu-img` mid-write is how images get damaged — but
/// read-only work like an integrity check is.
struct Activity: Equatable {
    let title: String
    var detail: String?
    var isCancellable = false
    var startedAt = Date()
}

/// Every sheet that acts on a machine carries which machine it meant.
///
/// Resolving the target from the current selection at confirmation time is a
/// trap: a background rescan can drop a machine and move the selection while
/// the dialog is still on screen, and the action then lands somewhere the
/// dialog never named.
enum SheetRoute: Identifiable, Equatable {
    case newSnapshot(machine: VirtualMachine.ID)
    case restore(Snapshot, machine: VirtualMachine.ID, restartAfter: Bool)
    case delete(Snapshot, machine: VirtualMachine.ID)
    case checkReport([String])
    case automationHelp

    var id: String {
        switch self {
        case .newSnapshot(let m): return "new-\(m)"
        case .restore(let s, let m, _): return "restore-\(m)-\(s.id)"
        case .delete(let s, let m): return "delete-\(m)-\(s.id)"
        case .checkReport: return "check"
        case .automationHelp: return "automation"
        }
    }
}

/// Coordinates the UI. Holds no logic about disks or processes — that lives in
/// `VMLibrary` — and exists to keep exactly one copy of "what is on screen".
@MainActor
final class AppModel: ObservableObject {

    // MARK: - Environment

    @Published private(set) var qemuImgPath: String?
    @Published private(set) var qemuVersion: String?
    @Published private(set) var utmAvailability: UTMControl.Availability = .notInstalled

    var isReady: Bool { qemuImgPath != nil }
    var canControlMachines: Bool { utmAvailability == .ready || utmAvailability == .notRunning }

    // MARK: - Library

    @Published private(set) var machines: [VirtualMachine] = []

    @Published var selectedMachineID: VirtualMachine.ID?
    @Published var selectedSnapshotID: Snapshot.ID?

    /// Points the snapshot selection at the current machine.
    ///
    /// Restore points are identified by name, and two machines can easily both
    /// have one called "Baseline" — so the selection has to be reset when the
    /// machine changes, or it silently carries over to a different machine's
    /// identically named point.
    ///
    /// This deliberately is *not* a `didSet` on `selectedMachineID`. That
    /// property is bound straight to the sidebar's `List`, so the setter runs
    /// inside SwiftUI's view update, and publishing a second change from there
    /// is a state mutation during an update: the run loop bails out mid-pass and
    /// leaves the window half-drawn — empty sidebar, missing detail header.
    /// Called from `onChange` instead, which runs after the update completes.
    func syncSnapshotSelection() {
        guard let vm = selectedMachine else {
            selectedSnapshotID = nil
            return
        }
        if !vm.snapshots.contains(where: { $0.id == selectedSnapshotID }) {
            selectedSnapshotID = orderedSnapshots.first?.id
        }
    }

    @Published private(set) var isScanning = false
    @Published private(set) var scanWasIncomplete = false
    @Published private(set) var restrictedFolders: [String] = []
    /// macOS is showing a consent dialog the user hasn't answered yet.
    @Published private(set) var permissionPending = false
    /// UTM is installed but its library could not be read, so no machine can be
    /// shown to be the one UTM manages.
    @Published private(set) var utmLibraryUnreadable = false

    private var lastScanFinishedAt: Date?

    // MARK: - Presentation

    @Published private(set) var activity: Activity?
    @Published var alert: AppAlert?
    @Published var sheet: SheetRoute?
    @Published var showsWelcome = false

    /// Confirmation of what just happened, shown briefly in place of nothing at
    /// all. Rolling a disk back is a big event and deserves an acknowledgement.
    @Published var lastOutcome: String?

    // MARK: - Baselines

    /// The restore point a machine is reset to over and over. Analysis work is
    /// a loop — roll back, run the sample, roll back — and picking the right row
    /// out of thirty every single time is both slow and an invitation to pick
    /// the wrong one.
    @Published private(set) var baselines: [String: String] = [:]

    // MARK: - Lineage

    enum DetailMode: String, CaseIterable, Identifiable {
        case list, tree
        var id: String { rawValue }
        var label: String {
            switch self {
            case .list: return String(localized: "List")
            case .tree: return String(localized: "Tree")
            }
        }
        var symbol: String {
            switch self {
            case .list: return "list.bullet"
            case .tree: return "point.topleft.down.to.point.bottomright.curvepath"
            }
        }
    }

    @Published var detailMode: DetailMode = .list {
        didSet { UserDefaults.standard.set(detailMode.rawValue, forKey: detailModeKey) }
    }

    /// Recorded ancestry per machine. See `Lineage` for why this is kept here
    /// rather than read from the image.
    @Published private(set) var lineages: [String: Lineage] = [:]

    func lineage(for vm: VirtualMachine) -> Lineage {
        var value = lineages[vm.id] ?? Lineage()
        value.prune(to: Set(vm.snapshots.map(\.name)))
        return value
    }

    private func updateLineage(for machineID: VirtualMachine.ID, _ change: (inout Lineage) -> Void) {
        var value = lineages[machineID] ?? Lineage()
        change(&value)
        lineages[machineID] = value
        saveLineages()
    }

    private func saveLineages() {
        guard let data = try? JSONEncoder().encode(lineages) else { return }
        UserDefaults.standard.set(data, forKey: lineageKey)
    }

    private func loadLineages() {
        guard let data = UserDefaults.standard.data(forKey: lineageKey),
              let decoded = try? JSONDecoder().decode([String: Lineage].self, from: data)
        else { return }
        lineages = decoded
    }

    private let baselineKey = "baselineSnapshots"
    private let welcomeKey = "hasSeenWelcome"
    private let lineageKey = "snapshotLineages"
    private let detailModeKey = "detailMode"

    private var hasLoadedOnce = false
    private var isRefreshing = false
    /// A refresh asked for while another was running. Without this the refresh
    /// that follows a write is silently dropped, and the in-flight scan then
    /// overwrites the list with data from before the change.
    private var refreshQueued = false
    private var pollTask: Task<Void, Never>?

    // MARK: - Derived

    var selectedMachine: VirtualMachine? {
        machines.first { $0.id == selectedMachineID }
    }

    var selectedSnapshot: Snapshot? {
        guard let snapshots = selectedMachine?.snapshots else { return nil }
        return snapshots.first { $0.id == selectedSnapshotID }
    }

    /// Snapshots with the pinned baseline floated to the top.
    var orderedSnapshots: [Snapshot] {
        guard let vm = selectedMachine else { return [] }
        let baseline = baselines[vm.id]
        return vm.snapshots.sorted { lhs, rhs in
            if lhs.name == baseline { return true }
            if rhs.name == baseline { return false }
            return lhs.date > rhs.date
        }
    }

    func isBaseline(_ snapshot: Snapshot, in vm: VirtualMachine) -> Bool {
        baselines[vm.id] == snapshot.name
    }

    var baselineSnapshot: Snapshot? {
        guard let vm = selectedMachine, let name = baselines[vm.id] else { return nil }
        return vm.snapshots.first { $0.name == name }
    }

    /// Names that appear more than once — the folder is then shown instead, so
    /// three machines called "Debian 12" stay distinguishable.
    var ambiguousNames: Set<String> {
        var seen = Set<String>()
        var duplicates = Set<String>()
        for machine in machines {
            if !seen.insert(machine.name).inserted { duplicates.insert(machine.name) }
        }
        return duplicates
    }

    private var library: VMLibrary? {
        qemuImgPath.map { VMLibrary(qemuImgPath: $0) }
    }

    // MARK: - Lifecycle

    func bootstrap() async {
        guard !hasLoadedOnce else { return }
        hasLoadedOnce = true

        baselines = (UserDefaults.standard.dictionary(forKey: baselineKey) as? [String: String]) ?? [:]
        loadLineages()
        if let raw = UserDefaults.standard.string(forKey: detailModeKey),
           let mode = DetailMode(rawValue: raw) {
            detailMode = mode
        }
        if !UserDefaults.standard.bool(forKey: welcomeKey) { showsWelcome = true }

        await checkPrerequisites()
        await refresh()
    }

    /// Safe to call repeatedly — the window may be closed and reopened, and
    /// `bootstrap` returns immediately on the second run, so tying polling to it
    /// left the state frozen for the rest of the session.
    func startPollingIfNeeded() {
        guard pollTask == nil else { return }
        startPolling()
    }

    func markWelcomeSeen() {
        UserDefaults.standard.set(true, forKey: welcomeKey)
    }

    func checkPrerequisites() async {
        let path = await ProcessRunner.timeboxed(12, fallback: String?.none) { QemuImg.locate() }
        qemuImgPath = path

        if let path {
            qemuVersion = await ProcessRunner.timeboxed(8, fallback: String?.none) {
                QemuImg.version(at: path)
            }
        } else {
            qemuVersion = nil
        }
    }

    /// Keeps the run state fresh without rescanning the whole disk.
    ///
    /// Asking UTM is cheap and the answer is what every destructive button is
    /// gated on, so it is polled. Without this the Take Snapshot button stays
    /// enabled for however long it takes the user to notice, on a machine they
    /// started in UTM ten seconds ago.
    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                // Frequent enough that the buttons react while you are looking
                // at them, and near-idle when you are not. Each poll spawns an
                // osascript process and makes UTM answer an Apple Event, so
                // there is no reason to keep that up in the background.
                let isActive = await MainActor.run { NSApp.isActive }
                try? await Task.sleep(for: .seconds(isActive ? 5 : 30))
                guard !Task.isCancelled else { return }
                await self?.refreshRunStates()
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Re-scans when the window comes back to the front, but only if the last
    /// scan admitted to being incomplete.
    ///
    /// Granting access happens *outside* this app — in a consent dialog or in
    /// System Settings — and nothing tells the app afterwards. Without this the
    /// short list simply stays on screen until something else happens to trigger
    /// a scan, and the machines then appear out of nowhere, seemingly at random.
    func applicationBecameActive() async {
        guard !isScanning, activity == nil else { return }

        // A sheet holds a machine and a restore point the user picked. Swapping
        // the list underneath it can move the selection, and the confirmed
        // action would then land on a different machine than the one named in
        // the dialog.
        guard sheet == nil else { return }

        // Several of these conditions can never resolve themselves — a denied
        // folder permission never re-prompts, and a Mac with no machines stays
        // that way. Without a floor, every single switch back to the window
        // would launch a full scan: mdfind, six folder walks, ps and an Apple
        // Event to UTM, forever.
        if let lastScanFinishedAt, Date().timeIntervalSince(lastScanFinishedAt) < 60 { return }

        guard permissionPending || scanWasIncomplete || !restrictedFolders.isEmpty else { return }
        await refresh()
    }

    private func refreshRunStates() async {
        // Never poll over a write: the scan would fight the operation for the
        // image lock and the answer would be stale by the time it lands.
        guard activity == nil, !isRefreshing else { return }

        let wasAvailable = utmAvailability
        let (utmMachines, availability) = await UTMControl.machines()
        utmAvailability = availability

        // UTM was launched since the last scan. The machine list was built
        // without it and may say "not in UTM's library" about everything, so it
        // needs rebuilding rather than patching. Checked before the early exit
        // below, which would otherwise leave that state stuck until a manual
        // rescan.
        if availability == .ready, wasAvailable == .notRunning {
            await refresh()
            return
        }

        guard availability == .ready else { return }
        // Nothing here is managed by UTM, so there is nothing left to patch.
        guard machines.contains(where: \.isRegisteredWithUTM) else { return }

        var states: [String: RunState] = [:]
        for machine in utmMachines { states[machine.uuid] = machine.state }

        machines = machines.map { vm in
            // Only machines UTM manages take their state from UTM. A duplicated
            // bundle carries the original's UUID, and letting it inherit the
            // original's state would report a copy as running.
            guard vm.isRegisteredWithUTM else { return vm }
            guard let uuid = vm.uuid, let state = states[uuid], state != vm.state else { return vm }

            // Two states this quick poll must never overwrite, because they were
            // established by evidence it does not re-gather: a suspend snapshot
            // read from the image, and a process found holding the disk. UTM
            // reporting "stopped" for either — a stale QEMU it no longer tracks,
            // a parked memory state it forgot — would light the buttons back up
            // on a machine that is not safe. Both wait for a full rescan.
            if state == .stopped, vm.state == .suspended || vm.state == .running { return vm }

            return vm.with(state: state)
        }
    }

    // MARK: - Scanning

    func refresh() async {
        guard let library else { return }

        if isRefreshing {
            refreshQueued = true
            return
        }
        isRefreshing = true
        isScanning = true
        defer {
            isRefreshing = false
            isScanning = false
        }

        repeat {
            refreshQueued = false

            // Published before the scan, so a window blocked behind a consent
            // dialog says so within seconds instead of showing a spinner for as
            // long as the dialog stands.
            let probe = await VMDiscovery.probePermissions()
            restrictedFolders = probe.restricted
            permissionPending = probe.pending

            // A hard ceiling on the whole scan. Every step inside already has
            // its own deadline, but an unanswered consent dialog can stall
            // several of them at once, and an app stuck on "Searching…" with no
            // way out is indistinguishable from a broken one.
            guard let result = await ProcessRunner.withDeadline(90, { await library.scan() }) else {
                // Deliberately not reported as a pending consent dialog: an
                // overrun has other causes, and claiming macOS is asking for
                // permission when nothing is on screen sends people hunting for
                // a dialog that does not exist.
                scanWasIncomplete = true
                continue
            }

            utmAvailability = result.utmAvailability
            restrictedFolders = result.restrictedFolders
            permissionPending = result.permissionPending
            utmLibraryUnreadable = result.utmLibraryUnreadable
            lastScanFinishedAt = Date()

            // A cut-short scan must never wipe a list that was already good.
            // Spotlight is empty on many Macs, so the folder walk is the only
            // source; if it hits its deadline the result says "nothing found"
            // even though the machines are still right there on disk.
            if result.machines.isEmpty && !machines.isEmpty && result.wasCutShort {
                scanWasIncomplete = true
                continue
            }

            scanWasIncomplete = false
            machines = result.machines

            if selectedMachineID == nil || !machines.contains(where: { $0.id == selectedMachineID }) {
                selectedMachineID = machines.first?.id
            }
            syncSnapshotSelection()
        } while refreshQueued
    }

    // MARK: - Baseline

    func setBaseline(_ snapshot: Snapshot?, for vm: VirtualMachine) {
        if let snapshot {
            baselines[vm.id] = snapshot.name
        } else {
            baselines.removeValue(forKey: vm.id)
        }
        UserDefaults.standard.set(baselines, forKey: baselineKey)
    }

    // MARK: - Machine control

    func start(_ vm: VirtualMachine) async {
        guard let uuid = vm.uuid else { return }
        await run(Activity(title: String(localized: "Starting “\(vm.name)”…"))) {
            try await UTMControl.start(machineWith: uuid)
        }
    }

    func stop(_ vm: VirtualMachine, method: UTMControl.StopMethod = .request) async {
        guard let uuid = vm.uuid else { return }
        let title = method == .request
            ? String(localized: "Asking “\(vm.name)” to shut down…")
            : String(localized: "Forcing “\(vm.name)” off…")
        await run(Activity(title: title, detail: method == .request
            ? String(localized: "The guest decides when it is ready. This can take a moment.")
            : nil)) {
            try await UTMControl.stop(machineWith: uuid, method: method)
            try await self.waitForStop(uuid: uuid)
        }
    }

    func suspend(_ vm: VirtualMachine) async {
        guard let uuid = vm.uuid else { return }
        await run(Activity(title: String(localized: "Suspending “\(vm.name)”…"))) {
            try await UTMControl.suspend(machineWith: uuid)
        }
    }

    /// Polls until the machine is actually down. `stop` returns as soon as the
    /// request is delivered, and writing to a disk that is merely on its way out
    /// is exactly as damaging as writing to a running one.
    private func waitForStop(uuid: String, timeout: TimeInterval = 120) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let state = await UTMControl.state(ofMachineWith: uuid)
            if state == .stopped { return }
            try? await Task.sleep(for: .seconds(1))
        }
        throw AppError.timedOut(what: String(localized: "Shutting the machine down"), seconds: Int(timeout))
    }

    // MARK: - Snapshot actions

    func beginNewSnapshot() {
        guard let vm = selectedMachine, vm.canModifyDisks else { return }
        sheet = .newSnapshot(machine: vm.id)
    }

    /// Looks the target up by identity rather than by "whatever is selected
    /// now". Returns nil and explains itself if the machine has since gone.
    private func machine(_ id: VirtualMachine.ID) -> VirtualMachine? {
        guard let vm = machines.first(where: { $0.id == id }) else {
            alert = AppAlert(
                title: String(localized: "That machine is no longer there"),
                message: String(localized: "It disappeared from the list while the dialog was open, so nothing was changed.")
            )
            return nil
        }
        return vm
    }

    func createSnapshot(named name: String, on machineID: VirtualMachine.ID) async {
        guard let vm = machine(machineID), let library else { return }
        await run(Activity(
            title: String(localized: "Saving “\(name)”…"),
            detail: String(localized: "Writing a restore point to \(vm.disks.count == 1 ? "the disk" : "\(vm.disks.count) disks").")
        )) {
            try await library.createSnapshot(named: name, on: vm)
            await MainActor.run {
                self.updateLineage(for: vm.id) { $0.recordSnapshot(named: name) }
                self.lastOutcome = String(localized: "Saved “\(name)”.")
            }
        }
        await refresh()
    }

    /// The core loop of this app: shut the machine down if needed, roll it back,
    /// and start it again — as one operation with one confirmation, instead of
    /// three trips to UTM and back.
    func restore(
        _ snapshot: Snapshot,
        on machineID: VirtualMachine.ID,
        keepingSafetyCopy: Bool,
        restartAfter: Bool
    ) async {
        guard let vm = machine(machineID), let library else { return }

        await run(Activity(title: String(localized: "Preparing…"))) {
            var machine = vm

            if !machine.state.allowsDiskWrites, machine.canStop, let uuid = machine.uuid {
                await self.setActivity(Activity(
                    title: String(localized: "Shutting “\(machine.name)” down…"),
                    detail: String(localized: "A disk cannot be rolled back while the machine is using it.")
                ))
                try await UTMControl.stop(machineWith: uuid, method: .request)
                try await self.waitForStop(uuid: uuid)
                machine = machine.with(state: .stopped)
            }

            if keepingSafetyCopy {
                let safetyName = self.uniqueName(
                    base: String(localized: "Automatic backup"), in: machine
                )
                await self.setActivity(Activity(
                    title: String(localized: "Saving the current state…"),
                    detail: String(localized: "So this step stays reversible.")
                ))
                try await library.createSnapshot(named: safetyName, on: machine)
                await MainActor.run {
                    self.updateLineage(for: machine.id) { $0.recordSnapshot(named: safetyName) }
                }
            }

            await self.setActivity(Activity(
                title: String(localized: "Restoring “\(snapshot.name)”…"),
                detail: String(localized: "Rolling \(machine.disks.count == 1 ? "the disk" : "all \(machine.disks.count) disks") back.")
            ))
            try await library.restore(snapshot, on: machine)

            if restartAfter, let uuid = machine.uuid, machine.isRegisteredWithUTM {
                await self.setActivity(Activity(title: String(localized: "Starting “\(machine.name)” again…")))
                try await UTMControl.start(machineWith: uuid)
            }

            await MainActor.run {
                self.updateLineage(for: machine.id) { $0.recordRestore(to: snapshot.name) }
                self.lastOutcome = String(
                    localized: "“\(machine.name)” is back at “\(snapshot.name)” (\(snapshot.absoluteDate))."
                )
            }
        }
        await refresh()
    }

    func delete(_ snapshot: Snapshot, on machineID: VirtualMachine.ID) async {
        guard let vm = machine(machineID), let library else { return }
        await run(Activity(title: String(localized: "Deleting “\(snapshot.name)”…"))) {
            try await library.delete(snapshot, on: vm)
            await MainActor.run {
                if self.baselines[vm.id] == snapshot.name { self.setBaseline(nil, for: vm) }
                self.updateLineage(for: vm.id) { $0.forget(snapshot.name) }
                self.lastOutcome = String(localized: "Deleted “\(snapshot.name)”.")
            }
        }
        await refresh()
    }

    // MARK: - Read-only tools

    func verifyDisks(on machineID: VirtualMachine.ID) async {
        guard let vm = machine(machineID), let library else { return }
        var lines: [String] = []
        await run(Activity(
            title: String(localized: "Checking “\(vm.name)”…"),
            detail: String(localized: "Reading every block of \(vm.disks.count == 1 ? "the disk" : "\(vm.disks.count) disks"). Nothing is modified."),
            isCancellable: false
        )) {
            let reports = await library.check(vm)
            lines = reports.map { report in
                let mark = report.isHealthy ? "✔︎" : "✖︎"
                return "\(mark) \(report.disk.fileName)\n\(report.detail)"
            }
        }
        if !lines.isEmpty { sheet = .checkReport(lines) }
    }

    func exportSnapshot(_ snapshot: Snapshot, on machineID: VirtualMachine.ID) async {
        guard let vm = machine(machineID), let library,
              let disk = snapshot.presentOn.first else { return }

        let panel = NSSavePanel()
        panel.title = String(localized: "Export Restore Point")

        // On a multi-disk machine this writes one disk, not the machine. Saying
        // so here is the difference between a useful export and someone
        // believing they have a complete copy that they do not.
        let isMultiDisk = vm.disks.count > 1
        let diskLabel = isMultiDisk
            ? (vm.disks.firstIndex(of: disk).map { disk.displayName(index: $0, total: vm.disks.count) } ?? disk.fileName)
            : ""

        panel.message = isMultiDisk
            ? String(localized: "Writes “\(snapshot.name)” from \(diskLabel) as a standalone qcow2 image. “\(vm.name)” has \(vm.disks.count) disks — this exports one of them, and only reads the original.")
            : String(localized: "Writes “\(snapshot.name)” as a standalone qcow2 image. The machine is only read.")

        panel.nameFieldStringValue = isMultiDisk
            ? "\(vm.name) — \(snapshot.name) — \(diskLabel).qcow2"
            : "\(vm.name) — \(snapshot.name).qcow2"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        await run(Activity(
            title: String(localized: "Exporting “\(snapshot.name)”…"),
            detail: String(localized: "This writes a full copy and can take a while.")
        )) {
            try await library.exportSnapshot(snapshot, from: disk, to: url)
            await MainActor.run {
                self.lastOutcome = String(localized: "Exported to \(url.lastPathComponent).")
            }
        }
    }

    // MARK: - Navigation helpers

    func revealInFinder(_ vm: VirtualMachine) {
        NSWorkspace.shared.activateFileViewerSelecting([vm.url])
    }

    func openUTM() {
        guard let url = UTMControl.applicationURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func openPrivacySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")
    }

    func openAutomationSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
    }

    private func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }

    // MARK: - Names

    func suggestedSnapshotName() -> String {
        guard let vm = selectedMachine else { return String(localized: "State") }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("d MMM yyyy HH:mm")
        return uniqueName(base: formatter.string(from: Date()), in: vm)
    }

    func validationMessage(for name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return String(localized: "Give the restore point a name.") }
        if trimmed.count > 100 { return String(localized: "That name is too long.") }
        if Int(trimmed) != nil {
            // qemu-img resolves a bare number as a snapshot ID before trying it
            // as a name, so a restore point called "2" can shadow a different
            // one entirely.
            return String(localized: "The name cannot be digits only — qemu would read it as an internal ID.")
        }
        if trimmed.lowercased() == VMLibrary.suspendTag {
            return String(localized: "This name is reserved by UTM.")
        }
        if let vm = selectedMachine, vm.snapshots.contains(where: { $0.name == trimmed }) {
            return String(localized: "A restore point with this name already exists.")
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

    // MARK: - Plumbing

    private func setActivity(_ new: Activity) async {
        await MainActor.run { self.activity = new }
    }

    /// One place where every long operation gets its progress overlay, its
    /// error handling and its guarantee that the overlay comes down again.
    private func run(_ initial: Activity, _ work: @escaping () async throws -> Void) async {
        activity = initial
        lastOutcome = nil
        defer { activity = nil }
        do {
            try await work()
        } catch {
            present(error)
        }
    }

    private func present(_ error: Error) {
        if let appError = error as? AppError {
            alert = AppAlert(
                title: appError.errorDescription ?? String(localized: "Something went wrong"),
                message: appError.recoverySuggestion ?? "",
                isCritical: appError.isCritical
            )
        } else {
            alert = AppAlert(
                title: String(localized: "Something went wrong"),
                message: error.localizedDescription
            )
        }
    }
}

extension VirtualMachine {
    /// Copy with a fresh run state, for the poll that updates status without a
    /// full rescan.
    func with(state newState: RunState) -> VirtualMachine {
        VirtualMachine(
            url: url, uuid: uuid, name: name, backend: backend, disks: disks,
            snapshots: snapshots, state: newState, isRegisteredWithUTM: isRegisteredWithUTM,
            hasAccess: hasAccess, hasUnreadableDisk: hasUnreadableDisk,
            usedBytes: usedBytes, virtualBytes: virtualBytes
        )
    }
}
