//
//  Common.swift
//  UTM Snapshot-Manager
//
//  Created by Jan Zombik on 04.03.23.
//

import Foundation

struct VMSnapshot {
    let id: UInt
    let tag: String
    let creationDate: Date
}

struct VMImage {
    private static let snapshotLinePattern = /^\d+.*?\n/.anchorsMatchLineEndings()
    private static let idPattern = /^\d+/
    private static let tagPattern = /^\d+\s+(?<tag>.*?)\s/
    private static let dateTimePattern = /\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2}/
    
    let url: URL
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
    
    static func validateURL(_ url: URL) -> Bool {
        if !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            return false
        }
        
        if !FileManager.default.isReadableFile(atPath: url.path(percentEncoded: false)) {
            return false
        }
        
        if !FileManager.default.isWritableFile(atPath: url.path(percentEncoded: false)) {
            return false
        }
        
        if url.pathExtension != "qcow2" {
            return false
        }
        
        return true
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

struct VM {
    let url: URL
    var images: [VMImage] {
        return FileManager.qcow2FileURLsAt(url)
            .filter { VMImage.validateURL($0) }
            .map { VMImage(validatedURL: $0) }
    }
    
    init?(url: URL) {
        var isDirectory = ObjCBool(false)
        
        if !FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory:&isDirectory) {
            return nil
        }
        
        if !isDirectory.boolValue {
            return nil
        }
        
        self.url = url
    }
}
