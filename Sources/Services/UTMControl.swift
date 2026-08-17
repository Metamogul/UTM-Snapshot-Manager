import AppKit
import Foundation

/// Talks to UTM through its scripting interface.
///
/// This is the app's authoritative answer to "is this machine running?". The
/// previous approach — grepping `ps` for a QEMU command line containing the disk
/// path — happens to work, but it infers a fact that UTM simply knows, and it
/// cannot see the difference between running and paused at all. Both states are
/// equally unsafe to write to, and only UTM can tell them apart.
///
/// Scripting runs through `osascript` rather than in-process `NSAppleScript` for
/// one reason: it can be given a deadline. An Apple Event to a beachballing UTM
/// blocks its thread with no way out, and freezing the app while asking whether
/// something is safe would be a poor trade.
enum UTMControl {

    static let bundleIdentifier = "com.utmapp.UTM"

    private static let queryTimeout: TimeInterval = 10
    private static let actionTimeout: TimeInterval = 30

    struct Machine: Sendable, Hashable {
        let uuid: String
        let name: String
        let state: RunState
        let backend: VirtualMachine.Backend
    }

    enum Availability: Equatable, Sendable {
        /// UTM is installed and answered.
        case ready
        /// UTM is installed but not running. Nothing it manages can be running
        /// either, so this is a perfectly good answer, not a failure.
        case notRunning
        /// Installed and running, but macOS has not granted automation access.
        case denied
        /// No UTM on this Mac.
        case notInstalled
        /// Installed and running but did not answer within the deadline.
        case unresponsive
    }

    // MARK: - Installation

    static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    static var applicationURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    /// Whether UTM is up right now.
    ///
    /// Checked before every query, because `tell application "UTM"` *launches*
    /// UTM. A snapshot manager that boots the virtualisation app on its own
    /// startup, just to ask a question, would be rude and slow.
    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    // MARK: - Reading

    /// Every machine in UTM's library with its current state.
    static func machines() async -> (machines: [Machine], availability: Availability) {
        guard isInstalled else { return ([], .notInstalled) }
        guard isRunning else { return ([], .notRunning) }

        let script = """
        tell application "UTM"
            set out to ""
            repeat with v in virtual machines
                set out to out & (id of v) & tab & ((status of v) as string) & tab & ((backend of v) as string) & tab & (name of v) & linefeed
            end repeat
            return out
        end tell
        """

        let result = await ProcessRunner.run("/usr/bin/osascript", ["-e", script], timeout: queryTimeout)

        guard result.finished else { return ([], .unresponsive) }
        guard result.ok else { return ([], availability(forError: result.message)) }

        var machines: [Machine] = []
        for line in result.stdout.split(separator: "\n") {
            let fields = line.components(separatedBy: "\t")
            guard fields.count >= 4 else { continue }
            machines.append(
                Machine(
                    uuid: fields[0].trimmingCharacters(in: .whitespaces).uppercased(),
                    // The name is last on purpose: it is the only field that can
                    // contain a tab, and joining the remainder keeps such a name
                    // intact instead of truncating it.
                    name: fields[3...].joined(separator: "\t"),
                    state: RunState(utmStatus: fields[1]),
                    backend: VirtualMachine.Backend(rawValue: fields[2].capitalized) ?? .unknown
                )
            )
        }
        return (machines, .ready)
    }

    /// The state of one machine, asked fresh. Used as the final gate right
    /// before a write, where a list built seconds ago is not good enough.
    static func state(ofMachineWith uuid: String) async -> RunState {
        guard isValidUUID(uuid) else { return .unknown }
        guard isInstalled else { return .unknown }
        // UTM not running means nothing it manages is running.
        guard isRunning else { return .stopped }

        let script = """
        tell application "UTM" to get (status of virtual machine id "\(uuid)") as string
        """
        let result = await ProcessRunner.run("/usr/bin/osascript", ["-e", script], timeout: queryTimeout)

        guard result.finished else { return .unknown }
        if !result.ok {
            // -1728 means UTM does not know this machine, which for a bundle
            // sitting outside its library is the expected answer, not an error.
            if result.message.contains("-1728") { return .stopped }
            return .unknown
        }
        return RunState(utmStatus: result.stdout)
    }

    /// IP addresses of a running guest. Requires the QEMU guest agent, so an
    /// empty result is normal rather than an error.
    static func ipAddresses(ofMachineWith uuid: String) async -> [String] {
        guard isValidUUID(uuid), isInstalled, isRunning else { return [] }
        let script = """
        tell application "UTM" to query ip of virtual machine id "\(uuid)"
        """
        let result = await ProcessRunner.run("/usr/bin/osascript", ["-e", script], timeout: queryTimeout)
        guard result.ok else { return [] }
        return result.stdout
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Writing

    enum StopMethod: String {
        /// Ask the guest OS to shut down. The only method that lets the guest
        /// flush its file system, so it is the default everywhere in the UI.
        case request
        /// Cut the power at the backend. Equivalent to pulling the plug.
        case force
    }

    static func start(machineWith uuid: String) async throws {
        try await perform(
            "start virtual machine id \"\(uuid)\"",
            uuid: uuid,
            what: String(localized: "Starting the machine")
        )
    }

    static func stop(machineWith uuid: String, method: StopMethod) async throws {
        try await perform(
            "stop virtual machine id \"\(uuid)\" by \(method.rawValue)",
            uuid: uuid,
            what: String(localized: "Stopping the machine")
        )
    }

    /// Parks the machine's memory state and quits QEMU. UTM writes this into the
    /// image's reserved `suspend` snapshot, which is exactly why a suspended
    /// machine still counts as unsafe to write to.
    static func suspend(machineWith uuid: String) async throws {
        try await perform(
            "suspend virtual machine id \"\(uuid)\" saving true",
            uuid: uuid,
            what: String(localized: "Suspending the machine")
        )
    }

    static func revealInUTM(machineWith uuid: String) {
        guard let url = applicationURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private static func perform(_ command: String, uuid: String, what: String) async throws {
        guard isInstalled else { throw AppError.utmMissing }
        guard isValidUUID(uuid) else { throw AppError.toolFailed(reason: String(localized: "This machine has no identifier UTM recognises.")) }

        let result = await ProcessRunner.run(
            "/usr/bin/osascript",
            ["-e", "tell application \"UTM\" to \(command)"],
            timeout: actionTimeout
        )

        guard result.finished else {
            throw AppError.timedOut(what: what, seconds: Int(actionTimeout))
        }
        guard result.ok else {
            if availability(forError: result.message) == .denied { throw AppError.automationDenied }
            throw AppError.toolFailed(reason: result.message)
        }
    }

    // MARK: - Helpers

    /// Interpolating anything into an AppleScript source string deserves a hard
    /// look. Only identifiers that are literally a UUID ever reach the script,
    /// so a machine name — which is user-controlled and may contain quotes — can
    /// never break out of the literal.
    static func isValidUUID(_ value: String) -> Bool {
        UUID(uuidString: value) != nil
    }

    private static func availability(forError message: String) -> Availability {
        // -1743: the user has not allowed this app to control UTM.
        // -600 / -609: UTM is not running after all.
        if message.contains("-1743") || message.lowercased().contains("not allowed") { return .denied }
        if message.contains("-600") || message.contains("-609") { return .notRunning }
        return .unresponsive
    }
}
