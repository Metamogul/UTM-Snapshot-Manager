import Foundation

enum QemuImgError: LocalizedError {
    case notInstalled
    case locked(vm: String)
    case failed(detail: String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return String(localized: "QEMU is not installed.")
        case .locked:
            return String(localized: "The virtual machine is currently running.")
        case .failed:
            return String(localized: "The operation could not be completed.")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .notInstalled:
            return String(localized: "Install QEMU with “brew install qemu” and restart UTM Snapshot Manager.")
        case .locked(let vm):
            return String(localized: "Shut “\(vm)” down completely in UTM — pausing is not enough — and try again.")
        case .failed(let detail):
            return detail
        }
    }
}

/// A thin, robust wrapper around `qemu-img`. Reads JSON exclusively so that
/// changes to QEMU's human-readable output can never break parsing.
enum QemuImg {

    static let candidatePaths = [
        "/opt/homebrew/bin/qemu-img",
        "/usr/local/bin/qemu-img",
        "/opt/local/bin/qemu-img",
        "/usr/bin/qemu-img"
    ]

    static func locate() -> String? {
        for path in candidatePaths where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        let result = ProcessRunner.runSync("/bin/sh", ["-lc", "command -v qemu-img"])
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.ok, !trimmed.isEmpty, FileManager.default.isExecutableFile(atPath: trimmed) {
            return trimmed
        }
        return nil
    }

    static func version(at path: String) -> String? {
        let result = ProcessRunner.runSync(path, ["--version"])
        guard result.ok else { return nil }
        return result.stdout.split(separator: "\n").first.map(String.init)
    }

    // MARK: - Reading

    /// Reads image details including snapshots. `-U` allows reading even while
    /// the VM is running — this is strictly read-only and therefore safe.
    static func info(qemuImg: String, disk: URL) async -> DiskInfo? {
        let result = await ProcessRunner.run(qemuImg, ["info", "-U", "--output=json", disk.path])
        guard result.ok, let data = result.stdout.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(DiskInfo.self, from: data)
    }

    // MARK: - Writing

    static func createSnapshot(qemuImg: String, disk: URL, name: String, vmName: String) async throws {
        try await mutate(qemuImg: qemuImg, disk: disk, arguments: ["-c", name], vmName: vmName)
    }

    static func deleteSnapshot(qemuImg: String, disk: URL, name: String, vmName: String) async throws {
        try await mutate(qemuImg: qemuImg, disk: disk, arguments: ["-d", name], vmName: vmName)
    }

    static func restoreSnapshot(qemuImg: String, disk: URL, name: String, vmName: String) async throws {
        try await mutate(qemuImg: qemuImg, disk: disk, arguments: ["-a", name], vmName: vmName)
    }

    private static func mutate(qemuImg: String, disk: URL, arguments: [String], vmName: String) async throws {
        let result = await ProcessRunner.run(qemuImg, ["snapshot"] + arguments + [disk.path])
        guard !result.ok else { return }

        let message = result.combined
        if message.lowercased().contains("lock") {
            throw QemuImgError.locked(vm: vmName)
        }
        throw QemuImgError.failed(
            detail: message.isEmpty ? String(localized: "qemu-img reported an unknown error.") : message
        )
    }
}
