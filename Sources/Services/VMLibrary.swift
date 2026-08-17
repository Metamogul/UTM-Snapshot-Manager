import Foundation

/// Builds the picture of what is on this Mac, and performs every disk-modifying
/// operation.
///
/// Three sources are combined: the bundles on disk, what UTM says about their
/// state, and what `qemu-img` reads out of each image. Keeping that join in one
/// place is what lets every write share the same pre-flight check, instead of
/// each call site remembering to do it.
struct VMLibrary: Sendable {

    let qemuImgPath: String

    /// How many machines are inspected at once. Each one occupies roughly three
    /// dispatch workers while its commands run, and the global pool has 64.
    private static let maxConcurrentInspections = 6

    struct Scan: Sendable {
        var machines: [VirtualMachine] = []
        var wasCutShort = false
        var restrictedFolders: [String] = []
        var permissionPending = false
        var utmAvailability: UTMControl.Availability = .notInstalled
        /// UTM's registry could not be read, so no machine can be shown to be
        /// the one UTM manages — starting and stopping are unavailable.
        var utmLibraryUnreadable = false
    }

    // MARK: - Scanning

    func scan() async -> Scan {
        async let discovered = VMDiscovery.scan()
        async let utm = UTMControl.machines()
        async let processes = ProcessTable.qemuCommandLines()

        let found = await discovered
        let (utmMachines, availability) = await utm
        let commandLines = await processes

        var statesByUUID: [String: RunState] = [:]
        for machine in utmMachines { statesByUUID[machine.uuid] = machine.state }

        // UTM's registry is the only thing that answers the question actually
        // being asked.
        //
        // An earlier version tried to skip this read — it triggers a
        // broad-sounding macOS prompt — and fell back to "UTM's scripting
        // interface lists this UUID". That answers a different question. UTM
        // reports UUIDs, not paths, and a duplicated bundle carries the
        // original's UUID, so the fallback cannot tell the copy from the
        // machine UTM would actually start.
        //
        // The guard around it was worse: it skipped the read whenever the scan
        // "looked complete", but the completeness flags only ever reported a
        // timed-out folder walk. A silent Spotlight failure, a machine on an
        // external volume, or a bundle discarded by the folder filter all leave
        // those flags looking perfectly healthy while the original is missing
        // from the results — and the copy then looks unique.
        //
        // So the read is unconditional now. If it is denied, no bundle claims
        // to be managed: snapshots keep working and only starting and stopping
        // is unavailable, which the UI explains.
        let registry = UTMRegistry.entries()

        // Inspecting a machine launches qemu-img per disk, which is slow but
        // independent — so it runs in parallel, with a hard cap on how many at
        // once.
        //
        // The cap is not a nicety. Each external command occupies a dispatch
        // worker plus two more for draining its pipes, and the global pool tops
        // out at 64 threads. Spawning one task per bundle meant that a Mac with
        // enough .utm bundles starved the pool: the pipe readers never got
        // scheduled, every command "timed out" while actually finishing, and the
        // app declared most of the disks unreadable. Measured: fine at 62
        // concurrent, total collapse at 64.
        var machines: [VirtualMachine] = []
        await withTaskGroup(of: VirtualMachine?.self) { group in
            var iterator = found.bundles.makeIterator()
            var inFlight = 0

            func addNext() -> Bool {
                guard let bundle = iterator.next() else { return false }
                let isRegistered = Self.isManagedByUTM(bundle: bundle, registry: registry)
                group.addTask {
                    await inspect(
                        bundle: bundle,
                        state: isRegistered ? bundle.uuid.flatMap { statesByUUID[$0] } : nil,
                        isRegistered: isRegistered,
                        registryEntry: bundle.uuid.flatMap { registry?[$0] },
                        commandLines: commandLines,
                        utmAvailability: availability
                    )
                }
                return true
            }

            while inFlight < Self.maxConcurrentInspections, addNext() { inFlight += 1 }

            while let machine = await group.next() {
                if let machine { machines.append(machine) }
                if !addNext() { inFlight -= 1 }
            }
        }

        machines.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        return Scan(
            machines: machines,
            wasCutShort: found.wasCutShort,
            restrictedFolders: found.restrictedFolders,
            permissionPending: found.permissionPending,
            utmAvailability: availability,
            utmLibraryUnreadable: registry == nil && UTMControl.isInstalled
        )
    }

    /// Whether this exact bundle is the one UTM manages under its UUID.
    ///
    /// Decided on the path UTM recorded, never on the identifier alone.
    /// Duplicating a `.utm` copies its UUID too, so identity is not identity —
    /// only the recorded location distinguishes the machine UTM would start
    /// from a backup of it sitting in Downloads.
    ///
    /// Without the registry the question is unanswerable, and unanswerable
    /// means no. The cost is a greyed-out Start button; the alternative is
    /// shutting down someone's running machine because its copy was selected.
    static func isManagedByUTM(
        bundle: VMDiscovery.BundleInfo,
        registry: [String: UTMRegistry.Entry]?
    ) -> Bool {
        guard let uuid = bundle.uuid, let registry, let entry = registry[uuid] else { return false }
        return URL(fileURLWithPath: entry.path).standardizedFileURL.path
            == bundle.url.standardizedFileURL.path
    }

    private func inspect(
        bundle: VMDiscovery.BundleInfo,
        state utmState: RunState?,
        isRegistered: Bool,
        registryEntry: UTMRegistry.Entry?,
        commandLines: [String]?,
        utmAvailability: UTMControl.Availability
    ) async -> VirtualMachine? {

        var diskStates: [DiskState] = []
        for disk in bundle.disks {
            if let info = await QemuImg.info(qemuImg: qemuImgPath, disk: disk.url) {
                diskStates.append(
                    DiskState(
                        disk: disk,
                        virtualBytes: info.virtualSize,
                        actualBytes: info.actualSize,
                        snapshots: info.snapshots ?? [],
                        isReadable: true
                    )
                )
            } else {
                // Must not be silently skipped: a disk we could not read has an
                // unknown snapshot list, and treating that as "has none" would
                // mark complete restore points as incomplete — or worse, the
                // reverse.
                diskStates.append(.unreadable(disk))
            }
        }

        let snapshots = mergeSnapshots(bundle: bundle, diskStates: diskStates)
        let hasSuspendState = diskStates.contains { $0.snapshotNames.contains(Self.suspendTag) }

        return VirtualMachine(
            url: bundle.url,
            uuid: bundle.uuid,
            name: bundle.name,
            backend: bundle.backend,
            disks: bundle.disks,
            snapshots: snapshots,
            state: resolveState(
                utmState: utmState,
                isRegistered: isRegistered,
                hasSuspendState: hasSuspendState || (registryEntry?.isSuspended ?? false),
                diskUse: ProcessTable.diskUse(of: bundle.disks, commandLines: commandLines),
                utmAvailability: utmAvailability
            ),
            isRegisteredWithUTM: isRegistered,
            hasAccess: bundle.isReadable,
            hasUnreadableDisk: diskStates.contains { !$0.isReadable },
            usedBytes: diskStates.reduce(0) { $0 + $1.actualBytes },
            virtualBytes: diskStates.reduce(0) { $0 + $1.virtualBytes }
        )
    }

    /// UTM's reserved snapshot. It holds a suspended machine's memory image, is
    /// never a user restore point, and its presence is what makes a machine
    /// "suspended" even though no process is running.
    static let suspendTag = "suspend"

    /// Decides the one value every destructive action is gated on.
    ///
    /// The order matters. UTM's answer wins when we have it. A machine UTM does
    /// not manage cannot be running under UTM, but a leftover QEMU process could
    /// still hold it, so that case falls back to the process table. And when UTM
    /// is installed, running, and refuses to answer, the honest result is
    /// `.unknown` — which blocks writes rather than guessing "probably fine".
    private func resolveState(
        utmState: RunState?,
        isRegistered: Bool,
        hasSuspendState: Bool,
        diskUse: ProcessTable.DiskUse,
        utmAvailability: UTMControl.Availability
    ) -> RunState {
        if let utmState, utmState != .stopped { return utmState }

        // A process holding one of this bundle's own images outranks anything
        // UTM says. It is matched on the file path, so it stays right even when
        // two bundles share a UUID, and it catches a QEMU started by hand or
        // left behind by a UTM that has since quit.
        if diskUse == .inUse { return .running }

        // A parked memory state outranks "stopped": no process holds the image,
        // but rolling it back now would leave UTM resuming stale memory onto a
        // changed disk.
        if hasSuspendState { return .suspended }

        // UTM manages this machine and says it is off. That is authoritative,
        // whatever the process table did or did not manage to tell us.
        if utmState == .stopped { return .stopped }

        // From here on UTM had nothing to say about this bundle, so the process
        // table was the only remaining source — and if it failed, we genuinely
        // do not know.
        if diskUse == .unknown { return .unknown }

        switch utmAvailability {
        case .notInstalled, .notRunning:
            return .stopped
        case .denied, .unresponsive:
            // Only machines UTM actually manages could be running under it. For
            // the rest the process check above is a complete answer.
            return isRegistered ? .unknown : .stopped
        case .ready:
            // UTM answered and does not manage this bundle, so it is not running
            // it either.
            return .stopped
        }
    }

    /// Folds per-disk snapshots into restore points that span the machine.
    private func mergeSnapshots(
        bundle: VMDiscovery.BundleInfo,
        diskStates: [DiskState]
    ) -> [Snapshot] {

        let readable = diskStates.filter(\.isReadable)
        guard !readable.isEmpty else { return [] }

        // A disk we could not read has an unknown snapshot list. Dropping it
        // from the comparison would let a point present on one of two disks
        // report itself as complete — the exact claim that decides whether a
        // rollback is allowed to proceed.
        let unreadable = diskStates.filter { !$0.isReadable }.map(\.disk)

        var names = Set<String>()
        for state in readable { names.formUnion(state.snapshotNames) }
        names.remove(Self.suspendTag)

        var result: [Snapshot] = []
        for name in names {
            let present = readable.filter { $0.snapshotNames.contains(name) }
            let missing = readable.filter { !$0.snapshotNames.contains(name) }

            let entries = present.compactMap { $0.snapshot(named: name) }

            result.append(
                Snapshot(
                    name: name,
                    // The earliest write across the disks. They are taken in a
                    // loop milliseconds apart, and showing the first is what
                    // matches "when did I press the button".
                    date: entries.map(\.date).min() ?? Date(),
                    stateBytes: entries.reduce(0) { $0 + $1.vmStateSize },
                    presentOn: present.map(\.disk),
                    missingFrom: missing.map(\.disk) + unreadable
                )
            )
        }

        // Newest first: the restore point someone reaches for is almost always
        // the most recent one, or the pinned baseline that the UI floats to the
        // top regardless of age.
        return result.sorted { $0.date > $1.date }
    }

    // MARK: - Pre-flight

    /// The final gate before anything is written.
    ///
    /// The machine list is a snapshot of the past — minutes may have passed, and
    /// starting a VM in UTM takes one click. So the state is fetched fresh from
    /// UTM here, and anything other than a definite "stopped" refuses the write.
    /// Crucially, an inconclusive answer refuses too: not knowing is a reason to
    /// stop, not a reason to proceed.
    func verifyWritable(_ vm: VirtualMachine) async throws {
        guard vm.hasAccess else {
            throw AppError.toolFailed(reason: String(localized: "This machine's folder cannot be read."))
        }
        guard !vm.disks.isEmpty else {
            throw AppError.toolFailed(reason: String(localized: "This machine has no disk this app can work with."))
        }

        // Re-read the reserved suspend snapshot straight from disk. UTM writes
        // it and exits, so no process is running and only the image knows.
        for disk in vm.disks {
            guard let info = await QemuImg.info(qemuImg: qemuImgPath, disk: disk.url) else {
                throw AppError.toolFailed(
                    reason: String(localized: "\(disk.fileName) could not be read, so the machine's state is unknown. Nothing was changed.")
                )
            }
            if (info.snapshots ?? []).contains(where: { $0.name == Self.suspendTag }) {
                throw AppError.notStopped(vm: vm.name, state: .suspended)
            }
        }

        // The disk list came from the last scan, and a disk added in UTM since
        // then would simply be skipped — rolling back the disks we know about
        // and leaving the new one in the present, while reporting success. So
        // the configuration is re-read and any disagreement stops the write.
        let fresh = VMDiscovery.read(bundle: vm.url)
        guard fresh.isReadable else {
            throw AppError.toolFailed(
                reason: String(localized: "This machine's configuration could not be read, so its disks are unknown. Nothing was changed.")
            )
        }
        guard Set(fresh.disks.map(\.url.path)) == Set(vm.disks.map(\.url.path)) else {
            throw AppError.diskLayoutChanged(vm: vm.name)
        }

        // Matched on the image path, so this holds even for a duplicated bundle
        // that shares its UUID with a machine UTM is running.
        let commandLines = await ProcessTable.qemuCommandLines()
        switch ProcessTable.diskUse(of: vm.disks, commandLines: commandLines) {
        case .inUse:
            throw AppError.notStopped(vm: vm.name, state: .running)
        case .unknown:
            // The process table could not be read. That is not permission to
            // write — it is the absence of the answer this check exists to get.
            throw AppError.notStopped(vm: vm.name, state: .unknown)
        case .free:
            break
        }

        guard let uuid = vm.uuid, UTMControl.isValidUUID(uuid) else { return }

        // Ask UTM about any bundle whose identifier it lists — deliberately not
        // only the ones proven to be in its library.
        //
        // Proving library membership needs UTM's registry, and macOS can refuse
        // that read. Gating the *safety* question on it meant one denied
        // permission silently switched off the best source of "is this running".
        // Asking on the identifier alone can only over-block: for a copy, UTM
        // answers about the original, and a refused write on a copy costs a
        // click, while a write to a running machine costs a file system.
        let (utmMachines, availability) = await UTMControl.machines()

        if let match = utmMachines.first(where: { $0.uuid == uuid }) {
            guard match.state.allowsDiskWrites else {
                throw AppError.notStopped(vm: vm.name, state: match.state)
            }
            return
        }

        // UTM does not list this identifier. That is a real answer when UTM
        // could actually be asked; when it could not, and this bundle is one UTM
        // is known to manage, the honest state is "unknown" — which blocks.
        if vm.isRegisteredWithUTM,
           availability == .denied || availability == .unresponsive {
            throw AppError.notStopped(vm: vm.name, state: .unknown)
        }
    }

    // MARK: - Writing

    /// Creates a restore point across every disk of the machine.
    ///
    /// If a later disk fails, the snapshots already written to the earlier ones
    /// are removed again, so a half-created restore point never survives to be
    /// offered — and then partially applied — later on.
    func createSnapshot(named name: String, on vm: VirtualMachine) async throws {
        try await verifyWritable(vm)

        var written: [DiskImage] = []
        for disk in vm.disks {
            do {
                try await QemuImg.createSnapshot(qemuImg: qemuImgPath, disk: disk, name: name)
                written.append(disk)
            } catch {
                let reason = (error as? AppError)?.recoverySuggestion ?? error.localizedDescription

                // Undo what was already written. If an undo itself fails the
                // machine really does carry a half-made restore point, and
                // saying "the machine is unchanged" would then be a lie — so
                // the two outcomes are reported as the different things they are.
                var stillPresent: [String] = []
                for done in written {
                    do {
                        try await QemuImg.deleteSnapshot(qemuImg: qemuImgPath, disk: done, name: name)
                    } catch {
                        stillPresent.append(done.fileName)
                    }
                }

                if stillPresent.isEmpty {
                    throw AppError.rolledBack(
                        operation: String(localized: "Saving “\(name)”"),
                        reason: reason
                    )
                }
                throw AppError.strandedSnapshot(
                    name: name, onDisks: stillPresent, reason: reason
                )
            }
        }
    }

    /// Rolls every disk back to a restore point.
    ///
    /// Unlike creating, this cannot be undone — the previous contents are gone
    /// the moment the first disk is written. So the completeness check happens
    /// *before* anything is touched, and a mid-way failure is reported as the
    /// serious problem it is, naming exactly which disks changed.
    func restore(_ snapshot: Snapshot, on vm: VirtualMachine) async throws {
        try await verifyWritable(vm)

        guard snapshot.isComplete else {
            throw AppError.incompleteSnapshot(
                name: snapshot.name,
                present: snapshot.diskCount,
                total: vm.disks.count
            )
        }

        // Verified again against the disks themselves rather than trusting the
        // list: it may have been built before the last change.
        for disk in vm.disks {
            guard let info = await QemuImg.info(qemuImg: qemuImgPath, disk: disk.url),
                  (info.snapshots ?? []).contains(where: { $0.name == snapshot.name })
            else {
                throw AppError.incompleteSnapshot(
                    name: snapshot.name,
                    present: snapshot.diskCount,
                    total: vm.disks.count
                )
            }
        }

        var done: [String] = []
        for disk in vm.disks {
            do {
                try await QemuImg.restoreSnapshot(qemuImg: qemuImgPath, disk: disk, name: snapshot.name)
                done.append(disk.fileName)
            } catch {
                if done.isEmpty { throw error }
                throw AppError.partialWrite(
                    operation: String(localized: "Restoring “\(snapshot.name)”"),
                    succeeded: done,
                    failed: disk.fileName,
                    reason: (error as? AppError)?.recoverySuggestion ?? error.localizedDescription
                )
            }
        }
    }

    /// Removes a restore point. A partial failure here leaves the machine's
    /// current state untouched — only the restore point ends up incomplete —
    /// so it is reported as an ordinary error rather than a crisis.
    func delete(_ snapshot: Snapshot, on vm: VirtualMachine) async throws {
        try await verifyWritable(vm)

        var removed: [String] = []
        for disk in snapshot.presentOn {
            do {
                try await QemuImg.deleteSnapshot(qemuImg: qemuImgPath, disk: disk, name: snapshot.name)
                removed.append(disk.fileName)
            } catch {
                // Stopping here leaves the restore point on the remaining disks.
                // The machine's current state is untouched, but the point is now
                // unusable — and saying only "qemu-img failed" would hide that.
                guard !removed.isEmpty else { throw error }
                throw AppError.partialDelete(
                    name: snapshot.name,
                    removedFrom: removed,
                    failedOn: disk.fileName,
                    reason: (error as? AppError)?.recoverySuggestion ?? error.localizedDescription
                )
            }
        }
    }

    // MARK: - Read-only tools

    func check(_ vm: VirtualMachine) async -> [QemuImg.CheckReport] {
        var reports: [QemuImg.CheckReport] = []
        for disk in vm.disks {
            reports.append(await QemuImg.check(qemuImg: qemuImgPath, disk: disk))
        }
        return reports
    }

    func exportSnapshot(_ snapshot: Snapshot, from disk: DiskImage, to url: URL) async throws {
        try await QemuImg.exportSnapshot(
            qemuImg: qemuImgPath, disk: disk, snapshot: snapshot.name, to: url
        )
    }
}
