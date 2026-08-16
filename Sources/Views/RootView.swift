import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.isReady {
                MainSplitView()
            } else {
                SetupView()
            }
        }
        .frame(minWidth: 780, minHeight: 500)
        .alert(
            model.alert?.title ?? "",
            isPresented: Binding(
                get: { model.alert != nil },
                set: { if !$0 { model.alert = nil } }
            )
        ) {
            Button("OK", role: .cancel) { model.alert = nil }
        } message: {
            Text(model.alert?.message ?? "")
        }
        .sheet(isPresented: $model.showsWelcome, onDismiss: { model.markWelcomeSeen() }) {
            WelcomeView()
        }
    }
}

struct MainSplitView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if !model.restrictedFolders.isEmpty {
                PermissionBar(folders: model.restrictedFolders)
                Divider()
            }
            splitView
        }
    }

    private var splitView: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 250, ideal: 280, max: 360)
        } detail: {
            detail
        }
        .overlay { BusyOverlay(title: model.busyTitle) }
        .sheet(isPresented: $model.isCreatingSnapshot) {
            NewSnapshotSheet().environmentObject(model)
        }
        .sheet(item: $model.snapshotPendingRestore) { snapshot in
            RestoreSheet(snapshot: snapshot).environmentObject(model)
        }
        .sheet(item: $model.snapshotPendingDeletion) { snapshot in
            DeleteSheet(snapshot: snapshot).environmentObject(model)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let vm = model.selected {
            VMDetailView(vm: vm)
                .id(vm.id)
        } else if model.isScanning {
            ProgressView("Looking for virtual machines…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.awaitingPermission {
            ContentUnavailableView {
                Label("Waiting for Permission", systemImage: "hand.raised")
            } description: {
                Text("macOS is asking whether UTM Snapshot Manager may read your folders. Click “Allow” in the dialog — it only needs this to find your virtual machines. If you dismissed it, grant access under System Settings › Privacy & Security › Files and Folders.")
            } actions: {
                Button("Try Again") { Task { await model.refresh() } }
                    .buttonStyle(.borderedProminent)
                Button("Open Privacy Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        } else {
            ContentUnavailableView {
                Label("No Virtual Machines Found", systemImage: "desktopcomputer.trianglebadge.exclamationmark")
            } description: {
                Text("Your Mac was searched automatically, but no UTM machine turned up. Create one in UTM — or grant access to the folder it lives in under System Settings › Privacy & Security.")
            } actions: {
                Button("Search Again") { Task { await model.refresh() } }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

/// Shown when macOS blocks folders the app needs. A denied permission dialog
/// never reappears on its own, so this is the only way the user finds out why
/// machines are missing from the list.
struct PermissionBar: View {
    @EnvironmentObject private var model: AppModel
    let folders: [String]

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("macOS is blocking \(folders.formatted(.list(type: .and)))")
                    .font(.callout.weight(.medium))
                Text("Virtual machines in there stay invisible until you allow access.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings…") { model.openPrivacySettings() }
            Button("Check Again") { Task { await model.refresh() } }
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.orange.opacity(0.12))
    }
}

/// Blocks the interface while a write is in flight, so two snapshot
/// operations can never run against the same disk at once.
struct BusyOverlay: View {
    let title: String?

    var body: some View {
        if let title {
            ZStack {
                Rectangle()
                    .fill(.black.opacity(0.08))
                VStack(spacing: 14) {
                    ProgressView()
                        .controlSize(.large)
                    Text(title)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                }
                .padding(28)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(radius: 20, y: 8)
            }
            .ignoresSafeArea()
            .transition(.opacity)
        }
    }
}
