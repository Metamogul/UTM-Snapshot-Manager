import Foundation

struct VirtualMachine: Identifiable, Hashable, Sendable {

    enum Backend: String, Sendable {
        case qemu = "QEMU"
        case apple = "Apple"
        case unknown = "Unknown"
    }

    /// Why the machine cannot be snapshotted right now. Ordered by how much the
    /// user can do about it: state first, because that is the one they can fix
    /// in ten seconds.
    enum Blocker: Hashable, Sendable {
        case noAccess
        case appleBackend
        case noSupportedDisk
        case unreadableDisk
        case notStopped(RunState)
    }

    let url: URL

    /// `Information.UUID` from `config.plist`. This is the same identifier UTM
    /// uses in its scripting interface, which is what lets us ask UTM about
    /// this exact machine instead of matching on a display name that may well
    /// occur three times on one Mac.
    let uuid: String?

    let name: String
    let backend: Backend
    let disks: [DiskImage]
    let snapshots: [Snapshot]
    let state: RunState

    /// True when UTM knows this machine. Bundles lying around in Downloads are
    /// real and snapshottable, but cannot be started from here.
    let isRegisteredWithUTM: Bool

    let hasAccess: Bool

    /// At least one disk could not be read by `qemu-img`, so sizes and the
    /// snapshot list are incomplete.
    let hasUnreadableDisk: Bool

    let usedBytes: Int64
    let virtualBytes: Int64

    var id: String { url.path }

    var blocker: Blocker? {
        if !hasAccess { return .noAccess }
        if backend == .apple { return .appleBackend }
        if disks.isEmpty { return .noSupportedDisk }
        if hasUnreadableDisk { return .unreadableDisk }
        if !state.allowsDiskWrites { return .notStopped(state) }
        return nil
    }

    /// The single gate the UI uses. Everything destructive is hidden or
    /// disabled behind this, and it is re-evaluated against UTM immediately
    /// before the write itself.
    var canModifyDisks: Bool { blocker == nil }

    /// Starting is offered only for machines UTM actually manages.
    var canStart: Bool {
        isRegisteredWithUTM && (state == .stopped || state == .suspended)
    }

    var canStop: Bool {
        isRegisteredWithUTM && (state == .running || state == .paused)
    }

    var symbolName: String {
        let lowered = name.lowercased()
        if backend == .apple { return "apple.logo" }
        if lowered.contains("windows") || lowered.contains("win") { return "pc" }
        if lowered.contains("mac") { return "macwindow" }
        if lowered.contains("debian") || lowered.contains("ubuntu") || lowered.contains("linux") {
            return "terminal"
        }
        return "desktopcomputer"
    }

    var locationDescription: String {
        let folder = url.deletingLastPathComponent().path
        return folder.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
    }

    var usedDescription: String { usedBytes.formatted(.byteCount(style: .file)) }
    var virtualDescription: String { virtualBytes.formatted(.byteCount(style: .file)) }
}

extension RunState {

    /// Short label for lists and badges. Deliberately a word, not just a colour
    /// — a coloured dot alone is invisible to a good share of users.
    var label: String {
        switch self {
        case .stopped: return String(localized: "Shut down")
        case .running: return String(localized: "Running")
        case .paused: return String(localized: "Paused")
        case .suspended: return String(localized: "Suspended")
        case .unknown: return String(localized: "State unknown")
        }
    }

    var symbolName: String {
        switch self {
        case .stopped: return "stop.circle"
        case .running: return "play.circle.fill"
        case .paused: return "pause.circle.fill"
        case .suspended: return "moon.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}
