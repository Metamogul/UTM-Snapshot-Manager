import Foundation

// Integration test: exercises the real write paths against real qcow2 images.

func say(_ s: String) { fputs(s + "\n", stderr) }

guard let qemuImg = QemuImg.locate() else {
    say("qemu-img not found"); exit(1)
}

let fm = FileManager.default
let lib = VMLibrary(qemuImgPath: qemuImg)
let root = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("usm-itest-\(ProcessInfo.processInfo.processIdentifier)")

final class Tally: @unchecked Sendable {
    var passed = 0
    var failed = 0
    func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        if ok { passed += 1; say("  PASS  \(name)") }
        else { failed += 1; say("  FAIL  \(name)  \(detail)") }
    }
}
let t = Tally()

@discardableResult
func runTool(_ path: String, _ args: [String]) throws -> String {
    let r = ProcessRunner.runSync(path, args, timeout: 60)
    guard r.ok else {
        throw NSError(domain: "tool", code: 1, userInfo: [NSLocalizedDescriptionKey: r.message])
    }
    return r.stdout
}

/// Builds a fake `.utm` bundle, including a CD-ROM that is itself a qcow2 —
/// which a directory scan would happily mistake for a system disk.
func makeBundle(name: String, diskCount: Int) throws -> URL {
    let bundle = root.appendingPathComponent("\(name).utm")
    let data = bundle.appendingPathComponent("Data")
    try fm.createDirectory(at: data, withIntermediateDirectories: true)

    try runTool(qemuImg, ["create", "-f", "qcow2",
                          data.appendingPathComponent("installer.qcow2").path, "64M"])
    var drives: [[String: Any]] = [[
        "ImageType": "CD", "Identifier": "cd-0", "ImageName": "installer.qcow2",
        "Interface": "USB", "ReadOnly": true
    ]]

    for i in 0..<diskCount {
        let file = "disk-\(i).qcow2"
        try runTool(qemuImg, ["create", "-f", "qcow2",
                              data.appendingPathComponent(file).path, "64M"])
        drives.append([
            "ImageType": "Disk", "Identifier": "disk-\(i)", "ImageName": file,
            "Interface": "VirtIO", "ReadOnly": false
        ])
    }

    let plist: [String: Any] = [
        "Backend": "QEMU",
        "ConfigurationVersion": 4,
        "Information": ["Name": name, "UUID": UUID().uuidString],
        "Drive": drives
    ]
    try PropertyListSerialization
        .data(fromPropertyList: plist, format: .xml, options: 0)
        .write(to: bundle.appendingPathComponent("config.plist"))
    return bundle
}

func machine(from bundle: URL) -> VirtualMachine {
    let info = VMDiscovery.read(bundle: bundle)
    return VirtualMachine(
        url: info.url, uuid: info.uuid, name: info.name, backend: info.backend,
        disks: info.disks, snapshots: [], state: .stopped, isRegisteredWithUTM: false,
        hasAccess: true, hasUnreadableDisk: false, usedBytes: 0, virtualBytes: 0
    )
}

func names(on disk: DiskImage) async -> Set<String> {
    guard let info = await QemuImg.info(qemuImg: qemuImg, disk: disk.url) else { return [] }
    return Set((info.snapshots ?? []).map(\.name))
}

func point(_ name: String, on disks: [DiskImage], missing: [DiskImage] = []) -> Snapshot {
    Snapshot(name: name, date: Date(), stateBytes: 0, presentOn: disks, missingFrom: missing)
}

let sem = DispatchSemaphore(value: 0)
Task {
    defer { sem.signal() }
    try? fm.removeItem(at: root)
    try! fm.createDirectory(at: root, withIntermediateDirectories: true)

    // ---------------------------------------------------------------------
    say("\n[1] Disks come from config.plist, not from a directory scan")
    let single = try! makeBundle(name: "Single", diskCount: 1)
    let info = VMDiscovery.read(bundle: single)
    t.check("a qcow2 CD-ROM is not treated as a disk", info.disks.count == 1,
            "got \(info.disks.map(\.fileName))")
    t.check("name and UUID read from the config", info.name == "Single" && info.uuid != nil)

    // ---------------------------------------------------------------------
    say("\n[2] Create, restore and delete on a single disk")
    let vm = machine(from: single)
    do {
        try await lib.createSnapshot(named: "base", on: vm)
        t.check("restore point created", await names(on: vm.disks[0]).contains("base"))
    } catch { t.check("restore point created", false, "\(error)") }

    do {
        try await lib.restore(point("base", on: vm.disks), on: vm)
        t.check("restore succeeded", true)
    } catch { t.check("restore succeeded", false, "\(error)") }

    do {
        try await lib.delete(point("base", on: vm.disks), on: vm)
        t.check("restore point deleted", await !names(on: vm.disks[0]).contains("base"))
    } catch { t.check("restore point deleted", false, "\(error)") }

    // ---------------------------------------------------------------------
    say("\n[3] Multi-disk machines are handled as one unit")
    let multi = try! makeBundle(name: "Multi", diskCount: 3)
    let mvm = machine(from: multi)
    t.check("three disks detected", mvm.disks.count == 3, "got \(mvm.disks.count)")

    do {
        try await lib.createSnapshot(named: "all", on: mvm)
        var everywhere = true
        for d in mvm.disks where await !names(on: d).contains("all") { everywhere = false }
        t.check("written to every disk", everywhere)
    } catch { t.check("written to every disk", false, "\(error)") }

    // ---------------------------------------------------------------------
    say("\n[4] An incomplete restore point is refused before anything is written")
    try? await QemuImg.deleteSnapshot(qemuImg: qemuImg, disk: mvm.disks[2], name: "all")

    let incomplete = point("all", on: [mvm.disks[0], mvm.disks[1]], missing: [mvm.disks[2]])
    t.check("the model marks it incomplete", !incomplete.isComplete)
    do {
        try await lib.restore(incomplete, on: mvm)
        t.check("refused", false, "it went through")
    } catch let e as AppError {
        if case .incompleteSnapshot = e { t.check("refused with the right error", true) }
        else { t.check("refused with the right error", false, "\(e)") }
    } catch { t.check("refused with the right error", false, "\(error)") }

    // A caller claiming completeness must not be believed.
    do {
        try await lib.restore(point("all", on: mvm.disks), on: mvm)
        t.check("a false 'complete' claim is caught by the disk re-check", false, "it went through")
    } catch { t.check("a false 'complete' claim is caught by the disk re-check", true) }

    // ---------------------------------------------------------------------
    say("\n[5] A failed create rolls the other disks back")
    let rb = try! makeBundle(name: "Rollback", diskCount: 3)
    let rvm = machine(from: rb)
    try! fm.setAttributes([.posixPermissions: 0o444], ofItemAtPath: rvm.disks[2].url.path)
    do {
        try await lib.createSnapshot(named: "doomed", on: rvm)
        t.check("the create failed as set up", false, "it succeeded unexpectedly")
    } catch let e as AppError {
        if case .rolledBack = e { t.check("reported as rolled back", true) }
        else { t.check("reported as rolled back", false, "\(e)") }
    } catch { t.check("reported as rolled back", false, "\(error)") }

    var leftovers: [String] = []
    for d in [rvm.disks[0], rvm.disks[1]] where await names(on: d).contains("doomed") {
        leftovers.append(d.fileName)
    }
    t.check("no half-made restore point survives", leftovers.isEmpty, "left on \(leftovers)")
    try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: rvm.disks[2].url.path)

    // ---------------------------------------------------------------------
    say("\n[6] UTM's reserved suspend state blocks writes")
    let susp = try! makeBundle(name: "Susp", diskCount: 1)
    let svm = machine(from: susp)
    try! await QemuImg.createSnapshot(qemuImg: qemuImg, disk: svm.disks[0], name: "suspend")
    do {
        try await lib.createSnapshot(named: "after", on: svm)
        t.check("a suspended machine is refused", false, "it went through")
    } catch let e as AppError {
        if case .notStopped(_, let st) = e, st == .suspended {
            t.check("a suspended machine is refused", true)
        } else { t.check("a suspended machine is refused", false, "\(e)") }
    } catch { t.check("a suspended machine is refused", false, "\(error)") }

    // ---------------------------------------------------------------------
    say("\n[7] Read-only tools")
    let reports = await lib.check(vm)
    t.check("integrity check reports healthy", reports.allSatisfy(\.isHealthy),
            reports.map(\.detail).joined(separator: " | "))

    try? await QemuImg.createSnapshot(qemuImg: qemuImg, disk: vm.disks[0], name: "exportme")
    let out = root.appendingPathComponent("exported.qcow2")
    do {
        try await lib.exportSnapshot(point("exportme", on: vm.disks), from: vm.disks[0], to: out)
        let ok = await QemuImg.info(qemuImg: qemuImg, disk: out) != nil
        t.check("export produced a readable image", ok)
    } catch { t.check("export produced a readable image", false, "\(error)") }

    // ---------------------------------------------------------------------
    say("\n[8] Names with characters that would break a shell")
    let awkward = "; rm -rf ~ && echo \"pwned\" 'x'"
    do {
        try await lib.createSnapshot(named: awkward, on: vm)
        t.check("a hostile name is stored verbatim, not executed",
                await names(on: vm.disks[0]).contains(awkward))
        t.check("home directory still intact",
                fm.fileExists(atPath: fm.homeDirectoryForCurrentUser.path))
        try await lib.delete(point(awkward, on: vm.disks), on: vm)
    } catch { t.check("a hostile name is stored verbatim, not executed", false, "\(error)") }

    // ---------------------------------------------------------------------
    say("\n[9] Telling a duplicated bundle from the machine UTM manages")
    // A copied .utm keeps the original's UUID, so identity alone cannot decide
    // which one UTM would start.
    let sharedUUID = UUID().uuidString.uppercased()
    let originalPath = root.appendingPathComponent("Original.utm")
    let copyPath = root.appendingPathComponent("Copy.utm")

    func bundleInfo(_ url: URL) -> VMDiscovery.BundleInfo {
        VMDiscovery.BundleInfo(url: url, uuid: sharedUUID, name: "Shared",
                               backend: .qemu, disks: [], isReadable: true)
    }
    let original = bundleInfo(originalPath)
    let copy = bundleInfo(copyPath)
    let registry = [sharedUUID: UTMRegistry.Entry(
        uuid: sharedUUID, path: originalPath.path, name: "Shared", isSuspended: false
    )]

    t.check("the bundle at UTM's recorded path is managed",
            VMLibrary.isManagedByUTM(bundle: original, registry: registry))

    t.check("a copy with the same UUID elsewhere is not",
            !VMLibrary.isManagedByUTM(bundle: copy, registry: registry))

    // The regression this replaced: a lone copy found by an incomplete scan
    // looked unique, and "UTM knows this UUID" was taken as proof of identity.
    // Identity now requires the recorded path, so an unreadable registry can
    // never produce a false claim, however the scan went.
    t.check("without the registry nothing claims to be managed",
            !VMLibrary.isManagedByUTM(bundle: original, registry: nil)
            && !VMLibrary.isManagedByUTM(bundle: copy, registry: nil))

    t.check("a UUID the registry does not list is not managed",
            !VMLibrary.isManagedByUTM(bundle: original, registry: [:]))

    // Trailing slashes and symlink-free normalisation must not defeat the
    // path comparison.
    let oddlyWritten = VMDiscovery.BundleInfo(
        url: URL(fileURLWithPath: root.path + "/./Original.utm"), uuid: sharedUUID,
        name: "Shared", backend: .qemu, disks: [], isReadable: true
    )
    t.check("the path comparison is normalised",
            VMLibrary.isManagedByUTM(bundle: oddlyWritten, registry: registry))

    // ---------------------------------------------------------------------
    say("\n[10] A disk added since the last scan stops the write")
    // The model carries the disk list from the last scan. Adding a disk in UTM
    // and then restoring must not roll back the known disks and quietly leave
    // the new one in the present.
    let grown = try! makeBundle(name: "Grown", diskCount: 1)
    let staleModel = machine(from: grown)
    try! await QemuImg.createSnapshot(qemuImg: qemuImg, disk: staleModel.disks[0], name: "before")

    // Add a second disk to the configuration behind the model's back.
    let data = grown.appendingPathComponent("Data")
    try! runTool(qemuImg, ["create", "-f", "qcow2",
                           data.appendingPathComponent("disk-1.qcow2").path, "64M"])
    var plist = try! PropertyListSerialization.propertyList(
        from: Data(contentsOf: grown.appendingPathComponent("config.plist")),
        format: nil) as! [String: Any]
    var drives = plist["Drive"] as! [[String: Any]]
    drives.append(["ImageType": "Disk", "Identifier": "disk-1", "ImageName": "disk-1.qcow2",
                   "Interface": "VirtIO", "ReadOnly": false])
    plist["Drive"] = drives
    try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        .write(to: grown.appendingPathComponent("config.plist"))

    t.check("the freshly read config now has two disks",
            VMDiscovery.read(bundle: grown).disks.count == 2)

    do {
        try await lib.createSnapshot(named: "after", on: staleModel)
        t.check("creating against a stale disk list is refused", false, "it went through")
    } catch let e as AppError {
        if case .diskLayoutChanged = e { t.check("creating against a stale disk list is refused", true) }
        else { t.check("creating against a stale disk list is refused", false, "\(e)") }
    } catch { t.check("creating against a stale disk list is refused", false, "\(error)") }

    do {
        try await lib.restore(point("before", on: staleModel.disks), on: staleModel)
        t.check("restoring against a stale disk list is refused", false, "it went through")
    } catch let e as AppError {
        if case .diskLayoutChanged = e { t.check("restoring against a stale disk list is refused", true) }
        else { t.check("restoring against a stale disk list is refused", false, "\(e)") }
    } catch { t.check("restoring against a stale disk list is refused", false, "\(error)") }

    // ---------------------------------------------------------------------
    say("\n[11] The safeguard against a genuinely running machine")
    // Needs a real, running machine, so it is opt-in rather than hardcoded to
    // one developer's Mac:
    //   USM_RUNNING_VM="/path/to/Machine.utm" Scripts/run-tests.sh
    let realPath = ProcessInfo.processInfo.environment["USM_RUNNING_VM"]
    let real = URL(fileURLWithPath: realPath ?? "")
    if realPath != nil, fm.fileExists(atPath: real.path) {
        let rvm2 = machine(from: real)
        let lines = await ProcessTable.qemuCommandLines()
        let use = ProcessTable.diskUse(of: rvm2.disks, commandLines: lines)
        say("      observed disk use: \(use)")
        if use == .inUse {
            do {
                try await lib.verifyWritable(rvm2)
                t.check("a running machine is refused", false, "verifyWritable let it through")
            } catch { t.check("a running machine is refused", true) }
        } else {
            say("      (not running right now — this check needs a running VM)")
        }
    } else {
        say("      (skipped — set USM_RUNNING_VM to a running machine's .utm bundle)")
    }

    try? fm.removeItem(at: root)
}
sem.wait()

say("\n=====================================")
say("  \(t.passed) passed, \(t.failed) failed")
say("=====================================")
exit(t.failed == 0 ? 0 : 1)
