import Foundation

/// Finds `.utm` bundles on this Mac and reads what their configuration says.
///
/// Two independent sources feed the result: Spotlight, which knows about every
/// indexed bundle, and a deliberately narrow walk of the folders UTM actually
/// uses. Both are time-boxed, so a disabled Spotlight index or a stale network
/// mount can slow one of them down but never the app.
///
/// This type does not touch `qemu-img` and knows nothing about snapshots — it
/// answers "which machines exist and how are they configured", and stops there.
enum VMDiscovery {

    private static let spotlightTimeout: Double = 8
    /// Per root, not for the walk as a whole.
    private static let perRootTimeout: Double = 8

    struct Found: Sendable {
        var bundles: [BundleInfo]
        /// The folder walk hit its deadline, so this list may be short.
        var wasCutShort: Bool
        /// Standard folders macOS refused to let us read.
        var restrictedFolders: [String]
        /// A consent dialog is on screen and unanswered. Reading a folder blocks
        /// for as long as it stands, which is indistinguishable from a slow scan
        /// unless the app says which of the two it is.
        var permissionPending: Bool
    }

    /// A bundle plus everything its own `config.plist` tells us.
    struct BundleInfo: Sendable, Hashable {
        let url: URL
        let uuid: String?
        let name: String
        let backend: VirtualMachine.Backend
        let disks: [DiskImage]
        let isReadable: Bool
    }

    /// UTM's default storage location. Everything else under `~/Library` is off
    /// limits, but this exact folder is where a stock UTM install keeps every
    /// machine, so it is allowed explicitly.
    static var utmContainerRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.utmapp.UTM/Data/Documents")
    }

    // MARK: - Entry point

    static func scan() async -> Found {
        // The permission probe runs on its own short deadline, separate from the
        // walk. Tying the two together meant that a walk which ran out of time —
        // the usual symptom of an unanswered permission dialog — also threw away
        // the very diagnosis that would have explained the short list.
        // `nil` means the probe never came back, which on macOS means a consent
        // dialog is open and unanswered — a different situation from "access was
        // denied", and one the user can fix in a second if we say so.
        async let restricted = ProcessRunner.timeboxed(4, fallback: [String]?.none) {
            restrictedStandardFolders()
        }
        async let spotlight = ProcessRunner.timeboxed(spotlightTimeout, fallback: Set<String>()) {
            spotlightPaths()
        }
        async let walked = walkAllRoots()

        let indexed = await spotlight
        let walk = await walked

        var paths = indexed
        for path in walk.bundles { paths.insert(path) }

        let urls = paths
            .map { URL(fileURLWithPath: $0) }
            .filter(isAllowed)
            .filter { FileManager.default.fileExists(atPath: $0.path) }

        let bundles = urls
            .map(read(bundle:))
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        let probe = await restricted
        return Found(
            bundles: bundles,
            wasCutShort: walk.wasCutShort,
            restrictedFolders: probe ?? [],
            permissionPending: probe == nil
        )
    }

    // MARK: - Reading a bundle

    static func read(bundle: URL) -> BundleInfo {
        let configURL = bundle.appendingPathComponent("config.plist")
        let dataURL = bundle.appendingPathComponent("Data")

        guard let data = try? Data(contentsOf: configURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            return BundleInfo(
                url: bundle,
                uuid: nil,
                name: bundle.deletingPathExtension().lastPathComponent,
                backend: .unknown,
                disks: [],
                isReadable: false
            )
        }

        let information = plist["Information"] as? [String: Any]
        let name = (information?["Name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? bundle.deletingPathExtension().lastPathComponent
        let uuid = (information?["UUID"] as? String)?.uppercased()
        let backend = (plist["Backend"] as? String)
            .flatMap(VirtualMachine.Backend.init(rawValue:)) ?? .unknown

        return BundleInfo(
            url: bundle,
            uuid: uuid,
            name: name,
            backend: backend,
            disks: disks(fromConfig: plist, dataURL: dataURL),
            isReadable: true
        )
    }

    /// Reads the drive list from the machine's configuration.
    ///
    /// Scanning `Data/` for `*.qcow2` instead — as this app used to — gets two
    /// things wrong that matter: an installer ISO attached as a qcow2 CD image
    /// looks exactly like a system disk, and a drive UTM marks read-only would
    /// end up in the write path. The configuration states both outright.
    private static func disks(fromConfig plist: [String: Any], dataURL: URL) -> [DiskImage] {
        guard let drives = plist["Drive"] as? [[String: Any]] else {
            return legacyDiskScan(dataURL: dataURL)
        }

        var result: [DiskImage] = []
        for drive in drives {
            guard (drive["ImageType"] as? String) == "Disk" else { continue }
            guard (drive["ReadOnly"] as? Bool) != true else { continue }
            guard let imageName = drive["ImageName"] as? String, !imageName.isEmpty else { continue }

            let url = dataURL.appendingPathComponent(imageName)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }

            result.append(
                DiskImage(
                    identifier: (drive["Identifier"] as? String) ?? imageName,
                    url: url,
                    interface: drive["Interface"] as? String
                )
            )
        }

        // A configuration without any usable Drive entry is more likely to be a
        // format this app does not understand than a machine with no disks.
        return result.isEmpty ? legacyDiskScan(dataURL: dataURL) : result
    }

    /// Fallback for bundles whose configuration cannot be parsed.
    private static func legacyDiskScan(dataURL: URL) -> [DiskImage] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: dataURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []

        return contents
            .filter { ["qcow2", "qcow"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { DiskImage(identifier: $0.lastPathComponent, url: $0, interface: nil) }
    }

    // MARK: - Locating

    private static func spotlightPaths() -> Set<String> {
        let result = ProcessRunner.runSync("/usr/bin/mdfind", ["kMDItemFSName == '*.utm'"], timeout: 8)
        var paths = Set<String>()
        for line in result.stdout.split(separator: "\n") where line.hasSuffix(".utm") {
            paths.insert(String(line))
        }
        return paths
    }

    struct WalkResult: Sendable {
        var bundles: Set<String> = []
        var wasCutShort = false
    }

    /// Walks each root under its own deadline.
    ///
    /// One shared budget meant a single root blocking on an unanswered
    /// permission dialog ate the whole allowance, and the roots after it were
    /// never visited at all. Per-root deadlines cost the same in the worst case
    /// and lose only the folder that actually stalled.
    private static func walkAllRoots() async -> WalkResult {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots: [(URL, Int)] = [
            (utmContainerRoot, 1),
            (home.appendingPathComponent("Documents"), 2),
            (home.appendingPathComponent("Downloads"), 1),
            (home.appendingPathComponent("Desktop"), 1),
            (home.appendingPathComponent("Virtual Machines"), 1),
            (home, 1)
        ]

        var result = WalkResult()
        for (root, depth) in roots {
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            let found = await ProcessRunner.timeboxed(perRootTimeout, fallback: Set<String>?.none) {
                walk(root, depth: depth)
            }
            if let found {
                result.bundles.formUnion(found)
            } else {
                result.wasCutShort = true
            }
        }
        return result
    }

    /// Fast, standalone permission probe.
    ///
    /// Runs before the scan so the window can say what it is waiting for within
    /// seconds. Folded into the scan it would only surface once every other step
    /// had also finished — and an unanswered dialog is exactly what makes those
    /// steps slow, so the explanation would arrive a minute after it was needed.
    ///
    /// `pending` means the probe never returned: a consent dialog is on screen.
    static func probePermissions() async -> (restricted: [String], pending: Bool) {
        let probe = await ProcessRunner.timeboxed(4, fallback: [String]?.none) {
            restrictedStandardFolders()
        }
        return (probe ?? [], probe == nil)
    }

    /// Standard folders that exist but cannot be listed — which means macOS
    /// denied access. Once a permission dialog has been denied it never
    /// reappears on its own, so without this the app would just quietly list
    /// fewer machines than the user has and look broken for no visible reason.
    private static func restrictedStandardFolders() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var restricted: [String] = []
        for name in ["Documents", "Downloads", "Desktop"] {
            let url = home.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            if (try? FileManager.default.contentsOfDirectory(atPath: url.path)) == nil {
                restricted.append(name)
            }
        }
        return restricted
    }

    private static func walk(_ root: URL, depth: Int) -> Set<String> {
        guard depth >= 0, isSafeToEnter(root) else { return [] }
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var found = Set<String>()
        for entry in entries {
            if entry.pathExtension == "utm" {
                found.insert(entry.path)
                continue
            }
            guard depth > 0 else { continue }
            let values = try? entry.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
            )
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
            // Descend into plain folders only. Filtering on "has no extension"
            // instead — as this used to — skipped ordinary folders like
            // "VMs v2.0", while still walking into application bundles.
            guard values?.isPackage != true else { continue }
            found.formUnion(walk(entry, depth: depth - 1))
        }
        return found
    }

    /// Folders this app has no business looking into. Two reasons, both
    /// user-visible: entering `Pictures` or `Music` makes macOS pop a Photos or
    /// Media permission dialog that has nothing to do with virtual machines, and
    /// entering a cloud folder can block in the kernel until the network answers.
    private static let blockedFolderNames: Set<String> = [
        "Library",            // but see utmContainerRoot, which is exempt
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

    /// Whether a bundle found by any source may be used.
    ///
    /// Spotlight happily reports bundles inside protected folders, and touching
    /// those would trigger the very permission dialogs the walk avoids. The one
    /// exception is UTM's own container: it sits under `~/Library`, which is
    /// otherwise excluded wholesale, and excluding it made a stock UTM install —
    /// where every machine lives in exactly that folder — come up empty.
    private static func isAllowed(_ bundle: URL) -> Bool {
        if bundle.path.hasPrefix(utmContainerRoot.path + "/") { return true }

        var parent = bundle.deletingLastPathComponent()
        let home = FileManager.default.homeDirectoryForCurrentUser
        while parent.path.count > 1 {
            if !isSafeToEnter(parent) { return false }
            if parent == home { break }
            parent = parent.deletingLastPathComponent()
        }
        return true
    }

    /// Skips protected folders, network volumes and anything that isn't a plain
    /// local directory. Reading a directory on an unreachable share blocks in
    /// the kernel with no way to cancel it, which a timeout alone cannot undo.
    private static func isSafeToEnter(_ url: URL) -> Bool {
        if url.path.hasPrefix(utmContainerRoot.path) { return true }

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
}
