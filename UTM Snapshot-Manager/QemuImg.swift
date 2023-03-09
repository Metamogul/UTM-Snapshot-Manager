//
//  QemuAdapter.swift
//  UTM Snapshot-Manager
//
//  Created by Jan Zombik on 04.03.23.
//

import Foundation

class QemuImg {
    private static let qemuImgPath = "/opt/homebrew/bin/qemu-img"
    
    private static let snapshotLinePattern = /^\d+.*?\n/.anchorsMatchLineEndings()
    private static let idPattern = /^\d+/
    private static let tagPattern = /^\d+\s+(?<tag>.*?)\s/
    private static let dateTimePattern = /\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2}/
    
    static func snapshotsForImageUrl(_ url: URL) -> [VMSnapshot] {
        guard let imageInfo = QemuImg.infoForImageUrl(url),
              imageInfo.contains("Snapshot list:") else {
            return []
        }
        
        var snapshots: [VMSnapshot] = []
        for match in imageInfo.matches(of: QemuImg.snapshotLinePattern) {
            guard let snapshot = QemuImg.snapshotFromString(match.output.description) else {
                continue
            }
            
            snapshots.append(snapshot)
        }
        
        return snapshots
    }
    
    private static func infoForImageUrl(_ url: URL) -> String? {
        let qemuImgCommandBase = "\(qemuImgPath) info"
        let qemuImgParameter = url.path(percentEncoded: false)
        
        let qemuImgCommand = "\(qemuImgCommandBase) \"\(qemuImgParameter)\""
        
        return try? self.runCommandInShell(qemuImgCommand)
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
        guard let idString = try? QemuImg.idPattern.firstMatch(in: snapshotString)?.description else {
            return nil
        }
        
        return UInt(idString)
    }
    
    private static func tagFromString(_ snapshotString: String) -> String? {
        guard let tagString = try? QemuImg.tagPattern.firstMatch(in: snapshotString)?.tag.description else {
            return nil
        }
        
        return tagString
    }
    
    private static func creationDateFromString(_ snapshotString: String) -> Date? {
        guard let dateTimeString = try? QemuImg.dateTimePattern.firstMatch(in: snapshotString)?.description else {
            return nil
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy'-'MM'-'dd' 'HH'-'mm'-'ss"
        
        return dateFormatter.date(from: dateTimeString)
    }
    
    @discardableResult private static func runCommandInShell(_ command: String) throws -> String {
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", command]
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.standardInput = nil

        try task.run()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)!
        
        return output
    }
}
