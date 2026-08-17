import Foundation

/// A thin, robust wrapper around `qemu-img`.
///
/// Reads JSON exclusively, so changes to QEMU's human-readable output cannot
/// break parsing, and passes every argument as a separate array element, so a
/// machine called `"; rm -rf ~"` is just an awkward name rather than a problem.
enum QemuImg {

    /// Snapshot operations rewrite metadata across a large image and can take
    /// minutes on a slow disk, so they get considerably longer than a query.
    private static let queryTimeout: TimeInterval = 20
    private static let mutateTimeout: TimeInterval = 600
    private static let checkTimeout: TimeInterval = 900

    static let candidatePaths = [
        "/opt/homebrew/bin/qemu-img",
        "/usr/local/bin/qemu-img",
        "/opt/local/bin/qemu-img",
        "/usr/bin/qemu-img",
        "/run/current-system/sw/bin/qemu-img"
    ]

    static func locate() -> String? {
        for path in candidatePaths where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        // Last resort: ask a login shell, which picks up a PATH the app itself
        // never sees when launched from Finder.
        let result = ProcessRunner.runSync("/bin/sh", ["-lc", "command -v qemu-img"], timeout: 10)
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.ok, !trimmed.isEmpty, FileManager.default.isExecutableFile(atPath: trimmed) {
            return trimmed
        }
        return nil
    }

    static func version(at path: String) -> String? {
        let result = ProcessRunner.runSync(path, ["--version"], timeout: 10)
        guard result.ok else { return nil }
        return result.stdout.split(separator: "\n").first.map(String.init)
    }

    // MARK: - Reading

    /// Reads image details including snapshots.
    ///
    /// `-U` skips the image lock. That is safe here and nowhere else: this
    /// command only reads, and without it every query against a running machine
    /// would fail — which is precisely when the user most wants to look.
    static func info(qemuImg: String, disk: URL) async -> DiskInfo? {
        let result = await ProcessRunner.run(
            qemuImg, ["info", "-U", "--output=json", disk.path], timeout: queryTimeout
        )
        guard result.ok, let data = result.stdout.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(DiskInfo.self, from: data)
    }

    /// Verifies the internal consistency of an image. Read-only, and the one
    /// diagnostic that can tell a user whether a machine that stopped booting
    /// has a damaged disk or a damaged guest.
    struct CheckReport: Sendable {
        let disk: DiskImage
        let isHealthy: Bool
        let detail: String
    }

    static func check(qemuImg: String, disk: DiskImage) async -> CheckReport {
        let result = await ProcessRunner.run(
            qemuImg, ["check", "-U", "--output=json", disk.url.path], timeout: checkTimeout
        )

        guard result.finished else {
            return CheckReport(
                disk: disk,
                isHealthy: false,
                detail: String(localized: "The check did not finish within \(Int(checkTimeout / 60)) minutes.")
            )
        }

        // qemu-img check exits 0 for a clean image, 3 when it found leaked
        // clusters (harmless, wastes space) and other non-zero codes for real
        // corruption. Reporting "damaged" for leaked clusters would send people
        // rebuilding perfectly good machines.
        let leaksOnly = result.status == 3
        let healthy = result.status == 0 || leaksOnly

        var detail = String(localized: "No problems found.")
        if leaksOnly {
            detail = String(localized: "No corruption. Some space is marked as used but is not referenced any more — harmless.")
        } else if !healthy {
            detail = result.message.isEmpty
                ? String(localized: "qemu-img reported a problem but gave no detail.")
                : result.message
        }
        return CheckReport(disk: disk, isHealthy: healthy, detail: detail)
    }

    // MARK: - Writing

    static func createSnapshot(qemuImg: String, disk: DiskImage, name: String) async throws {
        try await mutate(qemuImg: qemuImg, disk: disk, arguments: ["-c", name])
    }

    static func deleteSnapshot(qemuImg: String, disk: DiskImage, name: String) async throws {
        try await mutate(qemuImg: qemuImg, disk: disk, arguments: ["-d", name])
    }

    static func restoreSnapshot(qemuImg: String, disk: DiskImage, name: String) async throws {
        try await mutate(qemuImg: qemuImg, disk: disk, arguments: ["-a", name])
    }

    /// Writes one snapshot out as a standalone qcow2 image, leaving the original
    /// untouched. The source is only read, which makes this the safest way to
    /// get a copy of a past state out of a machine.
    static func exportSnapshot(
        qemuImg: String,
        disk: DiskImage,
        snapshot: String,
        to destination: URL
    ) async throws {
        let result = await ProcessRunner.run(
            qemuImg,
            ["convert", "-U", "-l", "snapshot.name=\(snapshot)", "-O", "qcow2",
             disk.url.path, destination.path],
            timeout: mutateTimeout
        )
        guard result.finished else {
            throw AppError.timedOut(what: String(localized: "The export"), seconds: Int(mutateTimeout))
        }
        guard result.ok else {
            throw AppError.toolFailed(reason: result.message)
        }
    }

    private static func mutate(qemuImg: String, disk: DiskImage, arguments: [String]) async throws {
        // Deliberately without -U. If another process holds the image lock the
        // write must fail; forcing past a lock is how disks get corrupted.
        let result = await ProcessRunner.run(
            qemuImg, ["snapshot"] + arguments + [disk.url.path], timeout: mutateTimeout
        )

        guard result.finished else {
            throw AppError.timedOut(what: String(localized: "The operation"), seconds: Int(mutateTimeout))
        }
        guard !result.ok else { return }

        let message = result.message
        if message.lowercased().contains("lock") || message.lowercased().contains("in use") {
            throw AppError.toolFailed(
                reason: String(localized: "Another program is holding \(disk.fileName) open. Shut the machine down in UTM and try again.\n\n\(message)")
            )
        }
        throw AppError.toolFailed(
            reason: message.isEmpty ? String(localized: "qemu-img reported an unknown error.") : message
        )
    }
}
