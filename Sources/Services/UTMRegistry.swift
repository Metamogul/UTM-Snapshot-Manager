import Foundation

/// Reads UTM's own record of which bundle is which.
///
/// UTM's scripting interface identifies machines by UUID and offers no way to
/// ask where one lives on disk. That is a problem the moment a `.utm` bundle is
/// duplicated — a copy keeps the original's UUID, so a backup sitting in
/// Downloads looks exactly like the machine UTM is running. Acting on the
/// scripting identifier alone would then start, stop, or judge the state of the
/// wrong machine entirely.
///
/// UTM's preferences hold the missing half: a registry keyed by UUID with the
/// bundle path. Reading it is best-effort — another app's container may be off
/// limits — and everything that depends on it degrades to "treat as unmanaged"
/// rather than to a guess.
enum UTMRegistry {

    struct Entry: Sendable, Hashable {
        let uuid: String
        let path: String
        let name: String
        /// UTM's own note that this machine has a parked memory state.
        let isSuspended: Bool
    }

    private static var preferencesURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Containers/com.utmapp.UTM/Data/Library/Preferences/com.utmapp.UTM.plist"
            )
    }

    /// UUID → entry, or `nil` when the registry could not be read at all.
    ///
    /// The distinction matters: an empty registry means UTM manages nothing, and
    /// `nil` means we do not know — and those two lead to different decisions.
    static func entries() -> [String: Entry]? {
        guard let data = try? Data(contentsOf: preferencesURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any],
              let registry = plist["Registry"] as? [String: Any]
        else { return nil }

        var result: [String: Entry] = [:]
        for (key, value) in registry {
            guard let record = value as? [String: Any] else { continue }
            let package = record["Package"] as? [String: Any]
            guard let path = package?["Path"] as? String, !path.isEmpty else { continue }

            let uuid = ((record["UUID"] as? String) ?? key).uppercased()
            result[uuid] = Entry(
                uuid: uuid,
                path: path,
                name: (record["Name"] as? String) ?? URL(fileURLWithPath: path)
                    .deletingPathExtension().lastPathComponent,
                isSuspended: (record["Suspended"] as? Bool) ?? false
            )
        }
        return result
    }
}

/// Finds QEMU processes and the images they hold open.
///
/// This is the backstop for machines UTM does not manage: a `.utm` bundle
/// started by hand, or one left running by a UTM that has since quit. It works
/// on the actual file path in the command line, so unlike a UUID it cannot
/// confuse a copy with the original.
enum ProcessTable {

    /// Whether an image is currently held open by a process.
    ///
    /// The third case is the point. Returning an empty list when `ps` itself
    /// failed would make "I could not check" look exactly like "nothing is
    /// running", and that is the one confusion this whole check exists to
    /// prevent — it would clear a machine for writing on the strength of a
    /// question that was never answered.
    enum DiskUse {
        case inUse
        case free
        case unknown
    }

    /// Full command lines of running QEMU processes, or `nil` if the process
    /// table could not be read.
    static func qemuCommandLines() async -> [String]? {
        let result = await ProcessRunner.run("/bin/ps", ["-Ao", "args="], timeout: 10)
        guard result.ok else { return nil }
        // Case-insensitive on purpose: UTM's own helper is QEMUHelper /
        // QEMULauncher, which a lowercase match misses entirely.
        return result.stdout
            .split(separator: "\n")
            .filter { $0.range(of: "qemu", options: .caseInsensitive) != nil }
            .map(String.init)
    }

    static func diskUse(of disks: [DiskImage], commandLines: [String]?) -> DiskUse {
        guard let commandLines else { return .unknown }
        let inUse = disks.contains { disk in
            // The full path is the reliable match, but a process started from
            // inside the machine's folder lists its image relatively. UTM names
            // images after a UUID, so the bare file name is specific enough to
            // be worth checking too.
            commandLines.contains {
                $0.contains(disk.url.path) || $0.contains(disk.url.lastPathComponent)
            }
        }
        return inUse ? .inUse : .free
    }
}
