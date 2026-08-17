import Foundation

/// Every failure the user can see, in one place.
///
/// Each case carries what the user needs to decide what to do next: what
/// failed, and — for the partial-write cases — exactly which disks were already
/// changed. A generic "operation failed" would be worse than useless here,
/// because the recovery step depends entirely on how far the write got.
enum AppError: LocalizedError, Equatable {

    /// `qemu-img` could not be found anywhere.
    case qemuMissing

    /// The machine is not shut down. Carries the state we actually observed.
    case notStopped(vm: String, state: RunState)

    /// A restore point is missing on at least one disk, so applying it would
    /// desynchronise the machine. Refused before anything is written.
    case incompleteSnapshot(name: String, present: Int, total: Int)

    /// A multi-disk write failed partway and the disks are now inconsistent.
    /// This is the one error the user must not be allowed to shrug off.
    case partialWrite(operation: String, succeeded: [String], failed: String, reason: String)

    /// A multi-disk create failed but the already-written snapshots were
    /// removed again, so the machine is back where it started.
    case rolledBack(operation: String, reason: String)

    /// A create failed partway and the leftovers could not be cleaned up. The
    /// machine's own state is untouched — only an unusable restore point remains.
    case strandedSnapshot(name: String, onDisks: [String], reason: String)

    /// A delete removed the restore point from some disks but not all.
    case partialDelete(name: String, removedFrom: [String], failedOn: String, reason: String)

    /// The machine's disks are not what the last scan saw.
    case diskLayoutChanged(vm: String)

    /// `qemu-img` exited non-zero.
    case toolFailed(reason: String)

    /// An external command did not finish within its deadline.
    case timedOut(what: String, seconds: Int)

    /// UTM refused the Apple Event, usually because automation was denied.
    case automationDenied

    /// UTM is not installed, so the machine cannot be controlled from here.
    case utmMissing

    var errorDescription: String? {
        switch self {
        case .qemuMissing:
            return String(localized: "QEMU is not installed.")
        case .notStopped(let vm, let state):
            switch state {
            case .running: return String(localized: "“\(vm)” is running.")
            case .paused: return String(localized: "“\(vm)” is paused.")
            case .suspended: return String(localized: "“\(vm)” is suspended.")
            default: return String(localized: "“\(vm)” is not shut down.")
            }
        case .incompleteSnapshot(let name, _, _):
            return String(localized: "“\(name)” is not a complete restore point.")
        case .partialWrite:
            return String(localized: "The machine's disks are now out of sync.")
        case .rolledBack:
            return String(localized: "The operation was undone.")
        case .strandedSnapshot(let name, _, _):
            return String(localized: "“\(name)” was only partly created.")
        case .partialDelete(let name, _, _, _):
            return String(localized: "“\(name)” was only partly deleted.")
        case .diskLayoutChanged(let vm):
            return String(localized: "The disks of “\(vm)” have changed.")
        case .toolFailed:
            return String(localized: "qemu-img could not complete the operation.")
        case .timedOut(let what, _):
            return String(localized: "\(what) took too long and was stopped.")
        case .automationDenied:
            return String(localized: "UTM did not allow this app to control it.")
        case .utmMissing:
            return String(localized: "UTM is not installed.")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .qemuMissing:
            return String(localized: "Install QEMU with “brew install qemu”, then click Check Again.")

        case .notStopped(let vm, let state):
            switch state {
            case .paused:
                return String(localized: "A paused machine still holds its disk open. Resume “\(vm)” in UTM and shut it down properly.")
            case .suspended:
                return String(localized: "UTM parked the memory state of “\(vm)” on disk. Start it, then shut it down from inside the guest.")
            case .unknown:
                return String(localized: "The state of “\(vm)” could not be determined, so nothing was changed. Make sure it is shut down in UTM.")
            default:
                return String(localized: "Shut “\(vm)” down completely in UTM — pausing is not enough.")
            }

        case .incompleteSnapshot(let name, let present, let total):
            return String(localized: "“\(name)” exists on \(present) of \(total) disks. Applying it would leave the machine with disks from different points in time, so it was refused.")

        case .partialWrite(let operation, let succeeded, let failed, let reason):
            let list = succeeded.formatted(.list(type: .and))
            return String(localized: "\(operation) succeeded on \(list) but failed on \(failed): \(reason)\n\nDo not start this machine. Restore the same point on the remaining disks, or restore the automatic backup taken beforehand.")

        case .rolledBack(let operation, let reason):
            return String(localized: "\(operation) failed on one disk (\(reason)), so the changes to the other disks were removed again. The machine is unchanged.")

        case .strandedSnapshot(let name, let disks, let reason):
            let list = disks.formatted(.list(type: .and))
            // Explicitly *not* the advice given for a failed restore. Nothing
            // about the machine's current state was touched here, and telling
            // someone to "restore the same point on the remaining disks" would
            // roll back a perfectly good machine to clean up a bookkeeping mess.
            return String(localized: "Creating it failed partway (\(reason)), and the parts already written to \(list) could not be removed again.\n\nThe machine itself is untouched and safe to start. “\(name)” is incomplete, cannot be restored, and is best deleted.")

        case .partialDelete(let name, let removed, let failed, let reason):
            let list = removed.formatted(.list(type: .and))
            return String(localized: "“\(name)” was removed from \(list) but not from \(failed): \(reason)\n\nThe machine's current state is untouched. The restore point is now incomplete and can no longer be used — try deleting it again once \(failed) is writable.")

        case .diskLayoutChanged(let vm):
            return String(localized: "“\(vm)” now has a different set of disks than when the list was built — one was probably added or removed in UTM. Nothing was changed, because acting on the old list would have left the new disk behind. Search again and retry.")

        case .toolFailed(let reason):
            return reason

        case .timedOut(_, let seconds):
            return String(localized: "No response after \(seconds) seconds. The disk may be on a network volume or another program is holding it open.")

        case .automationDenied:
            return String(localized: "Allow UTM Snapshot Manager under System Settings › Privacy & Security › Automation. Until then the app cannot read the running state reliably and will not write to any disk.")

        case .utmMissing:
            return String(localized: "Install UTM from getutm.app to start and stop machines from here. Snapshots keep working without it.")
        }
    }

    /// True when the machine may have been left in a broken state and the user
    /// has to act. These are shown as a blocking alert that cannot be styled
    /// away as a routine hiccup.
    var isCritical: Bool {
        switch self {
        case .partialWrite: return true
        default: return false
        }
    }
}
