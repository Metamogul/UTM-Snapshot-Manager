import SwiftUI

@main
struct UTMSnapshotManagerApp: App {

    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .task { await model.bootstrap() }
        }
        .defaultSize(width: 1080, height: 720)
        .commands { AppCommands(model: model) }
    }
}

/// Every action in the app is reachable from the menu bar, and everything worth
/// repeating has a shortcut.
///
/// This matters more here than in most apps: the workflow it is built for is a
/// loop — roll back, run something, roll back again — and a loop driven by
/// hunting for buttons with the mouse is a slow loop.
struct AppCommands: Commands {

    @ObservedObject var model: AppModel

    private var vm: VirtualMachine? { model.selectedMachine }
    private var snapshot: Snapshot? { model.selectedSnapshot }
    private var isBusy: Bool { model.activity != nil }

    var body: some Commands {

        CommandGroup(replacing: .newItem) {
            Button("Take Snapshot…") { model.beginNewSnapshot() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(vm?.canModifyDisks != true || isBusy)
        }

        CommandMenu("Machine") {
            Button("Start") {
                if let vm { Task { await model.start(vm) } }
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(vm?.canStart != true || isBusy)

            Button("Shut Down") {
                if let vm { Task { await model.stop(vm, method: .request) } }
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(vm?.canStop != true || isBusy)

            Button("Suspend") {
                if let vm { Task { await model.suspend(vm) } }
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
            .disabled(vm?.state != .running || isBusy)

            // Deliberately without a shortcut: this is the equivalent of
            // pulling the power cable and should take a moment of aiming.
            Button("Force Off…") {
                if let vm { Task { await model.stop(vm, method: .force) } }
            }
            .disabled(vm?.canStop != true || isBusy)

            Divider()

            Button("Verify Disks…") {
                if let vm { Task { await model.verifyDisks(on: vm.id) } }
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .disabled(vm == nil || isBusy)

            Divider()

            Button("Open in UTM") { model.openUTM() }
                .keyboardShortcut("u", modifiers: .command)
                .disabled(!UTMControl.isInstalled)

            Button("Show in Finder") {
                if let vm { model.revealInFinder(vm) }
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .disabled(vm == nil)
        }

        CommandMenu("Restore Point") {
            Button("Restore…") {
                if let snapshot, let vm { model.sheet = .restore(snapshot, machine: vm.id, restartAfter: false) }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(snapshot == nil || vm == nil || isBusy)

            Button("Reset to Baseline…") {
                if let baseline = model.baselineSnapshot, let vm {
                    model.sheet = .restore(baseline, machine: vm.id, restartAfter: true)
                }
            }
            .keyboardShortcut(.return, modifiers: [.command, .shift])
            .disabled(model.baselineSnapshot == nil || isBusy)

            Divider()

            Button(isSelectedBaseline ? "Remove as Baseline" : "Set as Baseline") {
                guard let vm, let snapshot else { return }
                model.setBaseline(isSelectedBaseline ? nil : snapshot, for: vm)
            }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(snapshot == nil || vm == nil)

            Button("Export…") {
                if let snapshot, let vm { Task { await model.exportSnapshot(snapshot, on: vm.id) } }
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(snapshot == nil || isBusy)

            Divider()

            Button("Delete…") {
                if let snapshot, let vm { model.sheet = .delete(snapshot, machine: vm.id) }
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(snapshot == nil || vm?.canModifyDisks != true || isBusy)
        }

        CommandGroup(after: .sidebar) {
            Divider()
            Button("Rescan for Machines") {
                Task { await model.refresh() }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model.isScanning || isBusy)
        }

        CommandGroup(replacing: .help) {
            Button("Quick Introduction") { model.showsWelcome = true }
            Divider()
            Button("Project Page on GitHub") {
                if let url = URL(string: "https://github.com/nurkert/UTM-Snapshot-Manager") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private var isSelectedBaseline: Bool {
        guard let vm, let snapshot else { return false }
        return model.isBaseline(snapshot, in: vm)
    }
}
