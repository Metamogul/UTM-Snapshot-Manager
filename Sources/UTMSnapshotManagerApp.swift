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
        .defaultSize(width: 1000, height: 660)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Take Snapshot…") { model.beginNewSnapshot() }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(model.selected?.canSnapshot != true)
            }
            CommandGroup(after: .sidebar) {
                Divider()
                Button("Search for Virtual Machines") {
                    Task { await model.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
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
    }
}
