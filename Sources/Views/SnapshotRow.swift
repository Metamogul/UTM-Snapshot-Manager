import SwiftUI

struct SnapshotRow: View {
    @EnvironmentObject private var model: AppModel
    @State private var isHovering = false

    let snapshot: Snapshot
    let canRestore: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 18))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(snapshot.relativeDate)
                    Text("·")
                    Text(snapshot.absoluteDate)
                    if !snapshot.isComplete {
                        Text("·")
                        Label("Incomplete", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .help("This snapshot is missing on at least one disk of the machine.")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button("Restore") {
                model.snapshotPendingRestore = snapshot
            }
            .buttonStyle(.bordered)
            .disabled(!canRestore)
            .opacity(isHovering ? 1 : 0.5)

            Menu {
                Button("Restore…") { model.snapshotPendingRestore = snapshot }
                    .disabled(!canRestore)
                Divider()
                Button("Delete…", role: .destructive) { model.snapshotPendingDeletion = snapshot }
                    .disabled(!canRestore)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 24)
        }
        .padding(.vertical, 2)
        // Makes the whole row clickable — the original app needed two or three
        // clicks to select a row or open its context menu.
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovering)
        .contextMenu {
            Button("Restore…") { model.snapshotPendingRestore = snapshot }
                .disabled(!canRestore)
            Button("Delete…", role: .destructive) { model.snapshotPendingDeletion = snapshot }
                .disabled(!canRestore)
        }
    }
}
