import Foundation

/// Finds UTM machines automatically - the user never has to add anything by hand.
///
/// Two independent sources feed the result: Spotlight, which knows about every
/// indexed `.utm` bundle on the machine, and a deliberately narrow walk of the
/// folders UTM actually uses. Both are time-boxed. A blocking network mount or a
/// disabled Spotlight index can slow one of them down, never the whole app.
enum VMDiscovery {

    private static let suspendTag = "suspend"
    private static let spotlightTimeout: Double = 8
    private static let walkTimeout: Double = 20
    private static let diskListTimeout: Double = 8

    struct ScanResult: Sendable {
        var machines: [VirtualMachine]
        /// The folder scan hit its deadline - almost always a pending macOS
        /// permission dialog the user has not answered yet.
        var awaitingPermission: Bool
        /// Standard folders macOS refused to let us read. Once a permission
        /// dialog has been denied it is never shown again, so without this the
        /// app would just quietly list fewer machines than the user has.
        var restrictedFolders: [String]
    }

    static func scan(qemuImg: String) async -> ScanResult {
        let (bundles, blocked, restricted) = await bundleURLs()
        let running = await runningDiskPaths()

        var machines: [VirtualMachine] = []
        for bundle in bundles {
            if let vm = await inspect(bundle: bundle, qemuImg: qemuImg, runningDisks: running) {
                machines.append(vm)
            }
        }
        return ScanResult(
            machines: machines.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
            awaitingPermission: (blocked || machines.contains { !$0.hasAccess })
                && !machines.contains { $0.hasAccess },
            restrictedFolders: restricted
        )
    }

    // MARK: - Locating

    private static func bundleURLs() async -> (urls: [URL], blocked: Bool, restricted: [String]) {
        async let spotlight = timeboxed(spotlightTimeout, fallback: Set<String>()) {
            spotlightPaths()
        }
        async let walked = timeboxed(walkTimeout, fallback: WalkResult?.none) {
            walkKnownRoots()
        }

        let indexed = await spotlight
        let walkResult = await walked

        // Spotlight only ever reports real bundles, so a hit is trusted even when
        // the contents can't be read yet - that machine is then shown with a
        // "no access" hint instead of silently vanishing from the list, which is
        // what made three of four machines disappear before permission was granted.
        var paths = indexed
        for path in walkResult?.bundles ?? [] {
            let config = URL(fileURLWithPath: path).appendingPathComponent("config.plist")
            if FileManager.default.fileExists(atPath: config.path) { paths.insert(path) }
        }

        let urls = paths
            .map { URL(fileURLWithPath: $0) }
            .filter { isAllowed($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        return (urls, walkResult == nil, walkResult?.restricted ?? [])
    }

    /// Spotlight happily reports bundles inside protected folders too. Touching
    /// those would trigger the very permission dialogs we avoid while walking.
    private static func isAllowed(_ bundle: URL) -> Bool {
        var parent = bundle.deletingLastPathComponent()
        let home = FileManager.default.homeDirectoryForCurrentUser
        while parent.path.count > 1 {
            if !isSafeToEnter(parent) { return false }
            if parent == home { break }
            parent = parent.deletingLastPathComponent()
        }
        return true
    }

    private static func spotlightPaths() -> Set<String> {
        let result = ProcessRunner.runSync("/usr/bin/mdfind", ["kMDItemFSName == '*.utm'"])
        var paths = Set<String>()
        for line in result.stdout.split(separator: "\n") where line.hasSuffix(".utm") {
            paths.insert(String(line))
        }
        return paths
    }

    /// The folders UTM itself uses, plus the handful of places people actually
    /// keep VMs. Deliberately NOT the whole home directory: walking `~/Library`
    /// or a cloud-storage folder can block for minutes on a stale network mount.
    struct WalkResult: Sendable {
        var bundles: Set<String>
        var restricted: [String]
    }

    private static func walkKnownRoots() -> WalkResult {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots: [(URL, Int)] = [
            (home.appendingPathComponent("Library/Containers/com.utmapp.UTM/Data/Documents"), 1),
            (home.appendingPathComponent("Documents"), 2),
            (home.appendingPathComponent("Downloads"), 1),
            (home.appendingPathComponent("Desktop"), 1),
            (home, 1)
        ]

        var found = Set<String>()
        for (root, depth) in roots {
            found.formUnion(walk(root, depth: depth))
        }

        // A folder that exists but cannot be listed means macOS denied access.
        // Spotlight results are filtered by the same rules, so this is the only
        // way to tell "you have no VMs there" apart from "you can't see them".
        var restricted: [String] = []
        for name in ["Documents", "Downloads", "Desktop"] {
            let url = home.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            if (try? FileManager.default.contentsOfDirectory(atPath: url.path)) == nil {
                restricted.append(name)
            }
        }
        return WalkResult(bundles: found, restricted: restricted)
    }

    private static func walk(_ root: URL, depth: Int) -> Set<String> {
        guard depth >= 0, isSafeToEnter(root) else { return [] }
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var found = Set<String>()
        for entry in entries {
            if entry.pathExtension == "utm" {
                found.insert(entry.path)
                continue
            }
            guard depth > 0, entry.pathExtension.isEmpty else { continue }
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
            found.formUnion(walk(entry, depth: depth - 1))
        }
        return found
    }

    /// Folders this app has no business looking into. Two reasons, both of them
    /// user-visible: entering `Pictures` or `Music` makes macOS pop a Photos or
    /// Media permission dialog that has nothing to do with virtual machines, and
    /// entering a cloud folder can block in the kernel until the network answers.
    /// UTM never stores machines in any of them.
    private static let blockedFolderNames: Set<String> = [
        "Library",            // includes CloudStorage and Mobile Documents (iCloud Drive)
        "Pictures",           // Photos library - triggers a Photos permission prompt
        "Music",              // triggers a Media & Apple Music prompt
        "Movies",
        "Applications",
        "Public",
        ".Trash",
        "mnt",
        "iCloud Drive",
        "Dropbox",
        "OneDrive",
        "Google Drive",
        "Creative Cloud Files"
    ]

    /// Skips protected folders, network volumes and anything that isn't a plain
    /// local directory. Reading a directory on an unreachable share blocks in the
    /// kernel with no way to cancel it, which a timeout alone cannot undo.
    private static func isSafeToEnter(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if blockedFolderNames.contains(name) { return false }
        if name.hasPrefix("iCloud") || name.hasPrefix("com~apple~") { return false }
        if url.path.hasPrefix("/Volumes/.timemachine") { return false }
        if url.pathExtension == "photoslibrary" || url.pathExtension == "photolibrary" { return false }

        guard let values = try? url.resourceValues(forKeys: [.volumeIsLocalKey, .isSymbolicLinkKey]) else {
            return true
        }
        if values.isSymbolicLink == true { return false }
        if values.volumeIsLocal == false { return false }
        return true
    }

    /// Re-checks right before a write whether the machine is running.
    /// Minutes may have passed between the last scan and the click.
    static func isRunning(_ vm: VirtualMachine) async -> Bool {
        let running = await runningDiskPaths()
        return vm.disks.contains { disk in
            running.contains { $0.contains(disk.path) }
        }
    }

    /// Disk paths currently in use by a running QEMU process.
    private static func runningDiskPaths() async -> [String] {
        let result = await ProcessRunner.run("/bin/ps", ["-Ao", "args="])
        return result.stdout
            .split(separator: "\n")
            .filter { $0.contains("qemu") }
            .map(String.init)
    }

    // MARK: - Inspecting

    private static func inspect(bundle: URL, qemuImg: String, runningDisks: [String]) async -> VirtualMachine? {
        let config = bundle.appendingPathComponent("config.plist")
        let name = displayName(bundle: bundle, config: config)
        let backend = self.backend(config: config)

        let dataURL = bundle.appendingPathComponent("Data")
        var hasAccess = FileManager.default.isReadableFile(atPath: config.path)
        var disks: [URL] = []

        let contents = await timeboxed(diskListTimeout, fallback: [URL]?.none) {
            try? FileManager.default.contentsOfDirectory(
                at: dataURL, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]
            )
        }
        if let contents {
            disks = contents
                .filter { ["qcow2", "qcow"].contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } else {
            hasAccess = false
        }
        if !hasAccess { disks = [] }

        let isRunning = disks.contains { disk in
            runningDisks.contains { $0.contains(disk.path) }
        }

        var snapshotsByName: [String: (dates: [Date], size: Int64, count: Int)] = [:]
        var used: Int64 = 0
        var virtual: Int64 = 0
        var suspended = false

        for disk in disks {
            guard let info = await QemuImg.info(qemuImg: qemuImg, disk: disk) else { continue }
            used += info.actualSize
            virtual += info.virtualSize

            for raw in info.snapshots ?? [] {
                if raw.name == suspendTag {
                    suspended = true
                    continue
                }
                var entry = snapshotsByName[raw.name] ?? (dates: [], size: 0, count: 0)
                entry.dates.append(raw.date)
                entry.size += raw.vmStateSize
                entry.count += 1
                snapshotsByName[raw.name] = entry
            }
        }

        let snapshots = snapshotsByName
            .map { name, entry in
                Snapshot(
                    name: name,
                    date: entry.dates.min() ?? Date(),
                    stateBytes: entry.size,
                    diskCount: entry.count,
                    isComplete: entry.count == disks.count
                )
            }
            .sorted { $0.date > $1.date }

        return VirtualMachine(
            url: bundle,
            name: name,
            backend: backend,
            disks: disks,
            snapshots: snapshots,
            isRunning: isRunning,
            isSuspended: suspended,
            hasAccess: hasAccess,
            usedBytes: used,
            virtualBytes: virtual
        )
    }

    private static func displayName(bundle: URL, config: URL) -> String {
        if let data = try? Data(contentsOf: config),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let info = plist["Information"] as? [String: Any],
           let name = info["Name"] as? String,
           !name.isEmpty {
            return name
        }
        return bundle.deletingPathExtension().lastPathComponent
    }

    private static func backend(config: URL) -> VirtualMachine.Backend {
        guard let data = try? Data(contentsOf: config),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let raw = plist["Backend"] as? String else {
            return .unknown
        }
        return VirtualMachine.Backend(rawValue: raw) ?? .unknown
    }

    // MARK: - Timeout

    /// Runs blocking work with a hard deadline.
    ///
    /// A task group cannot do this: cancelling a child task does not interrupt a
    /// blocking syscall, and the group only returns once every child has finished.
    /// A permission dialog or an unreachable network share would freeze the app
    /// for as long as it stays open. Here the caller is released on the deadline
    /// and the abandoned thread is left to finish on its own.
    static func timeboxed<T: Sendable>(
        _ seconds: Double,
        fallback: T,
        work: @escaping @Sendable () -> T
    ) async -> T {
        await withCheckedContinuation { continuation in
            let gate = ResumeGate()
            DispatchQueue.global(qos: .userInitiated).async {
                let value = work()
                if gate.claim() { continuation.resume(returning: value) }
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + seconds) {
                if gate.claim() { continuation.resume(returning: fallback) }
            }
        }
    }

    /// Makes sure a continuation is resumed exactly once.
    private final class ResumeGate: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed = false

        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if claimed { return false }
            claimed = true
            return true
        }
    }
}
