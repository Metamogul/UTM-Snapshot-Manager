import Foundation

/// A restore point of a VM. Merges snapshots that share a name across
/// all disks of a machine into a single entry.
struct Snapshot: Identifiable, Hashable, Sendable {
    let name: String
    let date: Date
    let stateBytes: Int64
    /// On how many of the VM's disks this snapshot exists.
    let diskCount: Int
    /// Present on every disk of the VM.
    let isComplete: Bool

    var id: String { name }

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
}

/// Raw snapshot data as reported by qemu-img.
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
