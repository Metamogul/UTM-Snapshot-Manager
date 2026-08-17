import Foundation

/// One writable disk of a machine.
///
/// Which files these are is read from the machine's own `config.plist` rather
/// than guessed from the file extension. UTM lists every drive with an
/// `ImageType`, so a mounted installer ISO in qcow2 format — which a directory
/// scan happily mistakes for a system disk — is excluded by construction, and
/// read-only drives never end up in a write path.
struct DiskImage: Identifiable, Hashable, Sendable {

    /// UTM's drive identifier from `config.plist`, or the file name when the
    /// disk had to be discovered without a readable configuration.
    let identifier: String

    let url: URL

    /// The interface UTM attaches this drive to (VirtIO, NVMe, …). Display only.
    let interface: String?

    var id: String { url.path }

    var fileName: String { url.lastPathComponent }

    /// A name a human can tell apart. UTM names its images after a UUID, which
    /// is useless in a list, so multi-disk machines get "Disk 1", "Disk 2".
    func displayName(index: Int, total: Int) -> String {
        guard total > 1 else { return String(localized: "Disk") }
        if let interface, !interface.isEmpty {
            return String(localized: "Disk \(index + 1) (\(interface))")
        }
        return String(localized: "Disk \(index + 1)")
    }
}

/// What `qemu-img info` reported for one disk, plus the snapshots on it.
struct DiskState: Sendable {
    let disk: DiskImage
    let virtualBytes: Int64
    let actualBytes: Int64
    let snapshots: [RawSnapshot]

    /// True when `qemu-img info` failed for this disk. Sizes and snapshots are
    /// then meaningless and must not be mistaken for "this disk has none" —
    /// that mistake turns a complete restore point into an apparently
    /// incomplete one, and the reverse.
    let isReadable: Bool

    var snapshotNames: Set<String> { Set(snapshots.map(\.name)) }

    func snapshot(named name: String) -> RawSnapshot? {
        snapshots.first { $0.name == name }
    }

    static func unreadable(_ disk: DiskImage) -> DiskState {
        DiskState(disk: disk, virtualBytes: 0, actualBytes: 0, snapshots: [], isReadable: false)
    }
}
