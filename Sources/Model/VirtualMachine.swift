import Foundation

struct VirtualMachine: Identifiable, Hashable, Sendable {

    enum Backend: String, Sendable {
        case qemu = "QEMU"
        case apple = "Apple"
        case unknown = "Unknown"
    }

    /// Why a VM cannot be snapshotted right now.
    enum Blocker: Hashable, Sendable {
        case running
        case suspended
        case appleBackend
        case noSupportedDisk
        case noAccess
    }

    let url: URL
    let name: String
    let backend: Backend
    let disks: [URL]
    let snapshots: [Snapshot]
    let isRunning: Bool
    let isSuspended: Bool
    let hasAccess: Bool
    let usedBytes: Int64
    let virtualBytes: Int64

    var id: String { url.path }

    var blocker: Blocker? {
        if !hasAccess { return .noAccess }
        if backend == .apple { return .appleBackend }
        if disks.isEmpty { return .noSupportedDisk }
        if isRunning { return .running }
        if isSuspended { return .suspended }
        return nil
    }

    var canSnapshot: Bool { blocker == nil }

    var symbolName: String {
        let lowered = name.lowercased()
        if backend == .apple { return "apple.logo" }
        if lowered.contains("windows") || lowered.contains("win") { return "pc" }
        if lowered.contains("mac") { return "macwindow" }
        return "desktopcomputer"
    }

    var locationDescription: String {
        let folder = url.deletingLastPathComponent().path
        return folder.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
    }

    var usedDescription: String {
        usedBytes.formatted(.byteCount(style: .file))
    }

    var virtualDescription: String {
        virtualBytes.formatted(.byteCount(style: .file))
    }
}
