# UTM Snapshot Manager

Restore points for [UTM](https://mac.getutm.app) virtual machines — as a proper Mac app.

UTM has no snapshot interface of its own; the feature request was
[closed as *not planned*](https://github.com/utmapp/UTM/issues/6020). The QEMU backend
underneath it *does* support snapshots on `qcow2` disks, it just has no face. This app is
that face: it finds your machines by itself, shows their restore points on a timeline, and
refuses to do anything dangerous behind your back.

## Install

```sh
git clone https://github.com/nurkert/UTM-Snapshot-Manager.git
cd UTM-Snapshot-Manager
./install.sh
```

That's it. The script installs what's missing (QEMU via Homebrew, XcodeGen), builds the app
and puts it into `/Applications`. Requires macOS 14 or newer and Xcode.

## What it does

**Finds your machines by itself.** No adding, no groups, no configuration. Spotlight plus a
scan of the usual folders turns up every `.utm` bundle on the Mac, wherever it lives. Two
machines with the same name are told apart by their folder.

**Keeps you from breaking your VM.** Snapshotting a *running* machine is the fastest way to
a corrupted file system: caches never reach the disk, and the image is captured mid-write.
The app detects running and suspended machines, disables every write action, and explains
why in plain words instead of showing a greyed-out button. It re-checks a second time right
before writing, because a machine can be started between the scan and your click. `qemu-img`'s
own file lock is the final backstop.

**Makes restoring reversible.** Restoring throws away everything since the snapshot, so the
confirmation dialog offers — checked by default — to save the current state first. One
misclick doesn't cost you a day's work.

**Handles multi-disk machines.** Snapshots are created, restored and deleted across all disks
of a machine as one unit. If a restore point is missing on one disk, it's flagged as
incomplete rather than silently pretending to be fine.

## How it works

Everything goes through `qemu-img`, the tool that ships with QEMU:

| Action | Command |
| --- | --- |
| Read | `qemu-img info -U --output=json <disk>` |
| Create | `qemu-img snapshot -c <name> <disk>` |
| Restore | `qemu-img snapshot -a <name> <disk>` |
| Delete | `qemu-img snapshot -d <name> <disk>` |

Reading uses `-U`, which is read-only and safe even while a machine runs — that's how the
snapshot list stays visible for a running VM. Only the write operations are gated.

Snapshots live *inside* the `qcow2` file. They cost almost nothing when created and grow only
as the disk diverges from them. UTM's own `suspend` snapshot is hidden from the list and its
name is reserved, so it can never be overwritten.

## Requirements

- macOS 14 or newer
- [UTM](https://mac.getutm.app) with QEMU-backend machines (Apple Virtualization uses a disk
  format that has no snapshots — those machines are shown, but marked as unsupported)
- `qemu-img` (`brew install qemu`) — the app walks you through this if it's missing

## Building manually

```sh
brew install xcodegen qemu
swift Tools/MakeIcon.swift        # regenerates the app icon
xcodegen generate                 # writes the .xcodeproj from project.yml
open "UTM Snapshot Manager.xcodeproj"
```

The Xcode project is generated from `project.yml`, so it never shows up as noise in diffs.
`Tools/MakeIcon.swift` draws the icon from an SF Symbol, so it stays reproducible.

## Relationship to the original

This is a fork of [Metamogul/UTM-Snapshot-Manager](https://github.com/Metamogul/UTM-Snapshot-Manager),
rewritten from scratch. The original was explicitly a proof of concept and listed a number of
known issues; this rewrite is aimed at being a finished product. Concretely:

| Original | Here |
| --- | --- |
| VMs had to be added manually and sorted into groups | Found automatically, no setup |
| Warned about running VMs in the README | Detects them and blocks the action, twice |
| Snapshot list parsed from `qemu-img` text output with regexes | Parsed from `--output=json` |
| Rows often needed two or three clicks to select | Whole row is one hit target |
| Deleting a group left the create button stuck highlighted | Standard `List` selection, no custom hit handling |
| AttributeGraph cycle warnings when deleting a snapshot | Sheets dismiss before state changes; one observable model, refreshed as a whole |
| Restore was irreversible | Optional automatic safety snapshot, on by default |
| No app icon of its own (used UTM's) | Own icon, generated from an SF Symbol |

The UI is currently English only. Every string goes through `String(localized:)` or
`LocalizedStringKey`, so adding a String Catalog is a small, self-contained change.

## Caveats

- **Shut the machine down first.** Not paused, not suspended — off.
- Snapshots are not backups. They live inside the same disk image; if that file is lost, so
  are they.
- Live snapshots (including memory state) are out of scope. That needs QEMU's monitor, not
  `qemu-img`.

## License

Apache 2.0, same as the original project.
