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

struct VMImage: Identifiable, Equatable {
    static func == (lhs: VMImage, rhs: VMImage) -> Bool {
        return lhs.id == rhs.id;
    }
    
    let url: URL
    var id: Int { self.url.hashValue }
    var snapshots: [VMSnapshot]
    
    init(validatedURL: URL) {
        self.url = validatedURL
        self.snapshots = QemuImg.snapshotsForImageUrl(self.url)
    }
}

struct VM : Identifiable, Codable, Equatable {
    static func == (lhs: VM, rhs: VM) -> Bool {
        return lhs.id == rhs.id;
    }
    
    let url: URL
    var id: Int { self.url.hashValue }
    var images: [VMImage] {
        return FileManager.qcow2FileURLsAt(url)
            .filter { FileManager.isValidQcow2ImageUrl($0) }
            .map { VMImage(validatedURL: $0) }
    }
    
    init(validatedUrl: URL) {
        self.url = validatedUrl
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
