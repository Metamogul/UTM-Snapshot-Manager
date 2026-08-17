import Foundation

/// Which restore point each other one grew out of.
///
/// qcow2 stores snapshots as a flat list — the format has no parent link, so a
/// tree cannot be read out of the image. It can be *recorded*, though, and that
/// record is what makes the shape of the work visible: roll back to a clean
/// state, try something, save that as a new point, and it is a branch off the
/// clean state rather than the next entry in a list.
///
/// This is the app's own bookkeeping and is presented as such. If it is lost or
/// a snapshot was made elsewhere, the point simply shows up as a root — nothing
/// breaks, the picture is just flatter.
struct Lineage: Codable, Equatable {

    /// Restore point name → the point the machine was sitting on when it was
    /// taken. Absent means "no record", which reads as a root.
    var parents: [String: String] = [:]

    /// Where the machine is now: the last point restored to, or the last one
    /// taken. Nil means the machine has moved on from every recorded point.
    var current: String?

    mutating func recordSnapshot(named name: String) {
        // Taking a snapshot captures the state the machine is in, so the new
        // point hangs off wherever it currently sits — and becomes the new
        // position itself.
        if let current, current != name { parents[name] = current }
        current = name
    }

    mutating func recordRestore(to name: String) {
        current = name
    }

    mutating func forget(_ name: String) {
        parents.removeValue(forKey: name)
        // Re-attach orphans to their grandparent so deleting a point in the
        // middle collapses the chain instead of scattering it into roots.
        let grandparent = parents[name]
        for (child, parent) in parents where parent == name {
            if let grandparent { parents[child] = grandparent }
            else { parents.removeValue(forKey: child) }
        }
        if current == name { current = grandparent }
    }

    /// Keeps only names that still exist on disk.
    mutating func prune(to existing: Set<String>) {
        for name in parents.keys where !existing.contains(name) {
            parents.removeValue(forKey: name)
        }
        for (child, parent) in parents where !existing.contains(parent) {
            parents.removeValue(forKey: child)
        }
        if let current, !existing.contains(current) { self.current = nil }
    }
}

/// One node of the drawn tree.
struct LineageNode: Identifiable {
    let snapshot: Snapshot
    let children: [LineageNode]
    let depth: Int

    var id: String { snapshot.id }
}

extension Lineage {

    /// Arranges restore points into the recorded tree.
    ///
    /// Anything without a known parent — made before this app tracked lineage,
    /// or created in UTM directly — becomes a root, so every point is always
    /// visible somewhere.
    func tree(from snapshots: [Snapshot]) -> [LineageNode] {
        let byName = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.name, $0) })

        var childrenOf: [String: [String]] = [:]
        var roots: [String] = []
        for snapshot in snapshots {
            if let parent = parents[snapshot.name], byName[parent] != nil {
                childrenOf[parent, default: []].append(snapshot.name)
            } else {
                roots.append(snapshot.name)
            }
        }

        // A corrupt record could in principle contain a cycle; visiting each
        // name once means the drawing terminates regardless.
        var visited = Set<String>()

        func build(_ name: String, depth: Int) -> LineageNode? {
            guard let snapshot = byName[name], visited.insert(name).inserted else { return nil }
            let kids = (childrenOf[name] ?? [])
                .compactMap { build($0, depth: depth + 1) }
                .sorted { $0.snapshot.date < $1.snapshot.date }
            return LineageNode(snapshot: snapshot, children: kids, depth: depth)
        }

        return roots
            .compactMap { build($0, depth: 0) }
            .sorted { $0.snapshot.date < $1.snapshot.date }
    }
}
