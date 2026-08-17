import Foundation

/// What a machine is doing right now.
///
/// Every disk-modifying action in this app hinges on this one value, so it has
/// a single rule: only `.stopped` permits a write, and anything we could not
/// determine counts as "do not touch". UTM is asked first because it actually
/// knows; the process table is only a backstop for machines UTM has not
/// registered in its library.
enum RunState: String, Sendable, Hashable, Codable {

    /// Shut down. The only state in which the disk may be modified.
    case stopped

    /// Running, starting or stopping — QEMU has the image open.
    case running

    /// Paused by UTM. Memory lives in the QEMU process, the disk is still open.
    case paused

    /// UTM parked the memory state in the image's reserved `suspend` snapshot
    /// and quit. No process holds the file, but rolling the disk back now would
    /// leave UTM resuming an old memory state onto a changed disk.
    case suspended

    /// UTM could not be asked and the process table was inconclusive.
    case unknown

    /// The single gate for every destructive operation.
    var allowsDiskWrites: Bool { self == .stopped }

    /// How confident we are. Used to decide whether to say "is running" or the
    /// more honest "could not be determined".
    var isDefinite: Bool { self != .unknown }
}

extension RunState {

    /// Maps UTM's own status vocabulary. UTM reports transitional states
    /// (`starting`, `stopping`, `pausing`, `resuming`) which are all just as
    /// unsafe as the state they lead to.
    init(utmStatus raw: String) {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "stopped":
            self = .stopped
        case "started", "starting", "stopping":
            self = .running
        case "paused", "pausing", "resuming":
            self = .paused
        default:
            self = .unknown
        }
    }
}
