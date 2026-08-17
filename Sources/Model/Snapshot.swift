import Foundation

/// A restore point, merged across every disk of a machine.
///
/// qcow2 snapshots are per-image and flat — there is no tree in the format, and
/// pretending otherwise would invent a hierarchy that does not exist. What is
/// real, and what the app shows instead, is that one restore point spans
/// several disks and may be missing on some of them.
struct Snapshot: Identifiable, Hashable, Sendable {

    let name: String

    /// Earliest timestamp across the disks it was found on.
    let date: Date

    /// Sum of the stored VM state across all disks.
    let stateBytes: Int64

    /// The disks this snapshot exists on, in the machine's disk order.
    let presentOn: [DiskImage]

    /// The disks it is missing from. Non-empty means restoring it would leave
    /// the machine with disks from different points in time.
    let missingFrom: [DiskImage]

    var id: String { name }

    var isComplete: Bool { missingFrom.isEmpty }

    var diskCount: Int { presentOn.count }
    var totalDiskCount: Int { presentOn.count + missingFrom.count }

    /// Created by this app's "save the current state first" step. Worth marking
    /// so a list of twenty restore points stays readable.
    var isAutomaticBackup: Bool {
        name.hasPrefix(String(localized: "Automatic backup"))
    }

    var relativeDate: String {
        // A snapshot taken a moment ago would otherwise read "in 0 seconds",
        // because the rounding can land just on the future side of now.
        let age = Date().timeIntervalSince(date)
        if age < 60 { return String(localized: "Just now") }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.locale = Locale.current
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var absoluteDate: String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    var stateDescription: String {
        guard stateBytes > 0 else { return String(localized: "Disk only") }
        return stateBytes.formatted(.byteCount(style: .file))
    }
}

/// Raw snapshot data as reported by `qemu-img info --output=json`.
struct RawSnapshot: Decodable, Sendable {
    let id: String
    let name: String
    let vmStateSize: Int64
    let dateSec: Int64
    let dateNsec: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case vmStateSize = "vm-state-size"
        case dateSec = "date-sec"
        case dateNsec = "date-nsec"
    }

    var date: Date {
        Date(timeIntervalSince1970: Double(dateSec) + Double(dateNsec) / 1_000_000_000)
    }
}

/// Output of `qemu-img info --output=json`.
struct DiskInfo: Decodable, Sendable {
    let format: String
    let virtualSize: Int64
    let actualSize: Int64
    let snapshots: [RawSnapshot]?

    enum CodingKeys: String, CodingKey {
        case format
        case virtualSize = "virtual-size"
        case actualSize = "actual-size"
        case snapshots
    }
}
