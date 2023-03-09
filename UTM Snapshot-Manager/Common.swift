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
    
    private static let snapshotLinePattern = /^\d+.*?\n/.anchorsMatchLineEndings()
    private static let idPattern = /^\d+/
    private static let tagPattern = /^\d+\s+(?<tag>.*?)\s/
    private static let dateTimePattern = /\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2}/
    
    let url: URL
    var id: Int { self.url.hashValue }
    var snapshots: [VMSnapshot] {
        guard let imageInfo = QemuImg.infoForImage(self) else {
            return []
        }
        
        guard imageInfo.contains("Snapshot list:") else {
            return []
        }
        
        var snapshots: [VMSnapshot] = []
        for match in imageInfo.matches(of: VMImage.snapshotLinePattern) {
            guard let snapshot = VMImage.snapshotFromString(match.output.description) else {
                continue
            }
            
            snapshots.append(snapshot)
        }
        
        return snapshots
    }
    
    init(validatedURL: URL) {
        self.url = validatedURL
    }
    
    private static func snapshotFromString(_ snapshotString: String) -> VMSnapshot? {
        guard let id = self.idFromString(snapshotString),
              let tag = self.tagFromString(snapshotString),
              let creationDate = self.creationDateFromString(snapshotString)
        else {
            return nil;
        }
        
        return VMSnapshot(id: id, tag: tag, creationDate: creationDate)
    }
    
    private static func idFromString(_ snapshotString: String) -> UInt? {
        guard let idString = try? VMImage.idPattern.firstMatch(in: snapshotString)?.description else {
            return nil
        }
        
        return UInt(idString)
    }
    
    private static func tagFromString(_ snapshotString: String) -> String? {
        guard let tagString = try? VMImage.tagPattern.firstMatch(in: snapshotString)?.tag.description else {
            return nil
        }
        
        return tagString
    }
    
    private static func creationDateFromString(_ snapshotString: String) -> Date? {
        guard let dateTimeString = try? VMImage.dateTimePattern.firstMatch(in: snapshotString)?.description else {
            return nil
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy'-'MM'-'dd' 'HH'-'mm'-'ss"
        
        return dateFormatter.date(from: dateTimeString)
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
