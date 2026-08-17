import SwiftUI

/// Restore points drawn as the tree they actually form.
///
/// The shape comes from the app's own record of what grew out of what — see
/// `Lineage`. It is the view that matches how the machine is used: a clean
/// baseline, a branch per experiment, and a marker for where the machine is
/// sitting right now.
///
/// Deliberately not a list with indentation. A branch only reads as a branch if
/// you can see it leave its parent, so the connectors are drawn as real curves
/// and each point is a card rather than a row.
struct SnapshotTreeView: View {
    @EnvironmentObject private var model: AppModel
    let vm: VirtualMachine

    private var lineage: Lineage { model.lineage(for: vm) }

    var body: some View {
        VStack(spacing: 0) {
            actionBar
            Divider()

            ScrollView {
                GlassGroup(spacing: 18) {
                    VStack(alignment: .leading, spacing: TreeMetrics.siblingGap) {
                        let roots = lineage.tree(from: vm.snapshots)
                        ForEach(Array(roots.enumerated()), id: \.element.id) { index, node in
                            TreeBranch(
                                node: node,
                                vm: vm,
                                current: lineage.current,
                                isLastSibling: index == roots.count - 1
                            )
                        }

                        if lineage.current == nil && !vm.snapshots.isEmpty {
                            unmarkedStateNote
                        }
                        if lineage.parents.isEmpty && vm.snapshots.count > 1 {
                            flatHistoryNote
                        }
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(alignment: .top) {
                // A faint wash so the cards sit on something rather than
                // floating on the window's bare background.
                LinearGradient(
                    colors: [.accentColor.opacity(0.06), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 220)
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: 10) {
            if vm.canModifyDisks {
                Button {
                    model.beginNewSnapshot()
                } label: {
                    Label("Save Current State", systemImage: "camera.aperture")
                }
                .primaryActionStyle()
                .help("Save where the machine is right now as a new restore point (⌘N)")
            }

            if vm.canStart {
                Button { Task { await model.start(vm) } } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .secondaryActionStyle()
                .help("Start this machine in UTM (⇧⌘S)")
            }

            if vm.canStop {
                Button { Task { await model.stop(vm, method: .request) } } label: {
                    Label("Shut Down", systemImage: "stop.fill")
                }
                .secondaryActionStyle()
                .help("Ask the guest to shut down (⇧⌘P)")
            }

            Spacer()

            if let current = lineage.current {
                Label("At “\(current)”", systemImage: "location.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Notes

    private var unmarkedStateNote: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(.tint.opacity(0.18)).frame(width: 26, height: 26)
                Circle().fill(.tint).frame(width: 9, height: 9)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Current state")
                    .font(.callout.weight(.medium))
                Text("Not saved to any restore point yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }

    private var flatHistoryNote: some View {
        Text("These points sit side by side because nothing is recorded about what grew out of what. Restore one and save from there, and the branch appears here.")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 480, alignment: .leading)
            .padding(.top, 16)
    }
}

// MARK: - Layout constants

private enum TreeMetrics {
    /// Width of the column the connector curve is drawn in.
    static let connectorWidth: CGFloat = 34
    /// Vertical centre of a card's dot, measured from the card's top.
    static let dotCentre: CGFloat = 27
    static let siblingGap: CGFloat = 10
}

// MARK: - Connector

/// The line from a parent card down to one child.
///
/// Draws the vertical drop, an eased corner, and the horizontal run into the
/// child's dot. When more siblings follow, the vertical continues past the
/// corner so the whole family hangs off one spine.
private struct BranchConnector: Shape {
    let isLast: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let x = rect.minX + 15
        let corner: CGFloat = 12
        let y = rect.minY + TreeMetrics.dotCentre

        path.move(to: CGPoint(x: x, y: rect.minY))
        path.addLine(to: CGPoint(x: x, y: y - corner))
        path.addQuadCurve(
            to: CGPoint(x: x + corner, y: y),
            control: CGPoint(x: x, y: y)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: y))

        if !isLast {
            path.move(to: CGPoint(x: x, y: y - corner))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
        }
        return path
    }
}

/// One node plus everything descended from it.
private struct TreeBranch: View {
    let node: LineageNode
    let vm: VirtualMachine
    let current: String?
    let isLastSibling: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: TreeMetrics.siblingGap) {
            TreeNodeCard(
                snapshot: node.snapshot,
                vm: vm,
                isCurrent: current == node.snapshot.name,
                hasChildren: !node.children.isEmpty
            )

            ForEach(Array(node.children.enumerated()), id: \.element.id) { index, child in
                HStack(alignment: .top, spacing: 0) {
                    BranchConnector(isLast: index == node.children.count - 1)
                        .stroke(
                            .quaternary,
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                        )
                        .frame(width: TreeMetrics.connectorWidth)

                    TreeBranch(
                        node: child,
                        vm: vm,
                        current: current,
                        isLastSibling: index == node.children.count - 1
                    )
                }
                // The connector starts at the parent's baseline, so the gap
                // above each child belongs to the drawing, not to the spacing.
                .padding(.top, -TreeMetrics.siblingGap)
            }
        }
    }
}

// MARK: - Node

private struct TreeNodeCard: View {
    @EnvironmentObject private var model: AppModel

    let snapshot: Snapshot
    let vm: VirtualMachine
    let isCurrent: Bool
    let hasChildren: Bool

    @State private var isHovering = false

    private var isBaseline: Bool { model.isBaseline(snapshot, in: vm) }
    private var isSelected: Bool { model.selectedSnapshotID == snapshot.id }

    private var accent: Color {
        if isCurrent { return .accentColor }
        if isBaseline { return .accentColor }
        return .secondary
    }

    var body: some View {
        HStack(spacing: 14) {
            marker

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(snapshot.name)
                        .font(.body.weight(isCurrent ? .semibold : .medium))
                        .lineLimit(1)

                    if isBaseline {
                        TagLabel(text: String(localized: "Baseline"),
                                 symbol: "flag.fill", tint: .accentColor)
                    }
                    if !snapshot.isComplete {
                        TagLabel(text: String(localized: "Incomplete"),
                                 symbol: "exclamationmark.triangle.fill", tint: .orange)
                    }
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            actions
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 560, alignment: .leading)
        .glassCard(cornerRadius: 13, tint: isCurrent ? .accentColor : nil)
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(
                    isSelected ? AnyShapeStyle(Color.accentColor)
                               : (isCurrent ? AnyShapeStyle(Color.accentColor.opacity(0.45))
                                            : AnyShapeStyle(Color.clear)),
                    lineWidth: isSelected ? 2 : 1.5
                )
        }
        .shadow(color: .black.opacity(isCurrent ? 0.14 : 0.07),
                radius: isCurrent ? 10 : 5, y: 3)
        .contentShape(Rectangle())
        .onTapGesture { model.selectedSnapshotID = snapshot.id }
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovering)
        .animation(.easeOut(duration: 0.18), value: isCurrent)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    /// The dot on the spine. Filled and haloed where the machine actually is.
    private var marker: some View {
        ZStack {
            if isCurrent {
                Circle().fill(Color.accentColor.opacity(0.18)).frame(width: 30, height: 30)
            }
            Circle()
                .strokeBorder(accent.opacity(isCurrent ? 1 : 0.45), lineWidth: 2)
                .frame(width: 16, height: 16)
            if isCurrent {
                Circle().fill(Color.accentColor).frame(width: 8, height: 8)
            } else if isBaseline {
                Image(systemName: "flag.fill")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.tint)
            }
        }
        .frame(width: 30, height: 30)
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 6) {
            if isCurrent {
                Text("You are here")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tint)
            } else {
                Button("Restore") {
                    model.sheet = .restore(snapshot, machine: vm.id, restartAfter: false)
                }
                .secondaryActionStyle()
                .controlSize(.small)
                .disabled(!vm.canModifyDisks || !snapshot.isComplete)
                .help("Roll the disk back to this point")
            }

            Menu {
                Button("Restore and Start…") {
                    model.sheet = .restore(snapshot, machine: vm.id, restartAfter: true)
                }
                .disabled(!vm.canModifyDisks || !vm.isRegisteredWithUTM || !snapshot.isComplete)

                Button(isBaseline ? "Remove as Baseline" : "Set as Baseline") {
                    model.setBaseline(isBaseline ? nil : snapshot, for: vm)
                }
                Button("Export…") { Task { await model.exportSnapshot(snapshot, on: vm.id) } }

                Divider()

                Button("Delete…", role: .destructive) {
                    model.sheet = .delete(snapshot, machine: vm.id)
                }
                .disabled(!vm.canModifyDisks)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22)
            .accessibilityLabel("More actions for \(snapshot.name)")
        }
    }

    private var subtitle: String {
        var parts = [snapshot.relativeDate]
        if vm.disks.count > 1 {
            parts.append(String(localized: "\(snapshot.diskCount) of \(vm.disks.count) disks"))
        }
        if hasChildren { parts.append(String(localized: "branches from here")) }
        return parts.joined(separator: " · ")
    }

    private var accessibilityLabel: String {
        var text = snapshot.name
        if isCurrent { text += ", " + String(localized: "current position") }
        if isBaseline { text += ", " + String(localized: "baseline") }
        text += ", " + snapshot.absoluteDate
        return text
    }
}

private struct TagLabel: View {
    let text: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.15)))
    }
}
