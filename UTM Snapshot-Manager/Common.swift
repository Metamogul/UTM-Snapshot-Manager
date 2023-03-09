//
//  Common.swift
//  UTM Snapshot-Manager
//
//  Created by Jan Zombik on 04.03.23.
//

import Foundation

struct VMSnapshot: Identifiable {
    let id: UInt
    let tag: String
    let creationDate: Date
}

class VMImage: Identifiable, Equatable, ObservableObject {
    static func == (lhs: VMImage, rhs: VMImage) -> Bool {
        return lhs.id == rhs.id;
    }
    
    let url: URL
    var id: Int { self.url.hashValue }
    @Published var snapshots: [VMSnapshot]
    
    init(validatedURL: URL) {
        self.url = validatedURL
        self.snapshots = QemuImg.snapshotsForImageUrl(self.url)
    }
    
    func createSnapshot(_ snapshotTag: String = "") {
        QemuImg.createSnapshotForImageUrl(self.url, snapshotTag: snapshotTag)
        self.updateSnapshots()
    }
    
    func removeSnapshot(_ snapshot: VMSnapshot) {
        QemuImg.deleteSnapshotForImageUrl(self.url, snapshotTag: snapshot.tag)
        self.updateSnapshots()
    }
    
    func restoreSnapshot(_ snapshot: VMSnapshot) {
        QemuImg.restoreSnapshotForImageUrl(self.url, snapshotTag: snapshot.tag)
        self.updateSnapshots()
    }
    
    func updateSnapshots() {
        self.snapshots = QemuImg.snapshotsForImageUrl(self.url)
    }
}

struct VM : Identifiable, Codable, Equatable {
    static func == (lhs: VM, rhs: VM) -> Bool {
        return lhs.id == rhs.id;
    }
    
    let url: URL
    var id: Int { self.url.hashValue }
    let images: [VMImage]
    
    private enum CodingKeys: String, CodingKey {
        case url
    }
    
    init(validatedUrl: URL) {
        self.url = validatedUrl
        self.images = FileManager.qcow2FileURLsAt(url)
            .filter { FileManager.isValidQcow2ImageUrl($0) }
            .map { VMImage(validatedURL: $0) }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.url = try container.decode(URL.self, forKey: .url)
        self.images = FileManager.qcow2FileURLsAt(url)
            .filter { FileManager.isValidQcow2ImageUrl($0) }
            .map { VMImage(validatedURL: $0) }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.url, forKey: .url)
    }
}

struct VMGroup : Identifiable, Codable, Hashable {
    static func == (lhs: VMGroup, rhs: VMGroup) -> Bool {
        return lhs.id == rhs.id;
    }
    
    let id: UUID
    var name: String
    var vms: [VM]
    
    init(id: UUID = UUID(), name: String = "VMGroup", vms: [VM] = []) {
        self.id = id
        self.name = name
        self.vms = vms
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(self.id)
    }
}
