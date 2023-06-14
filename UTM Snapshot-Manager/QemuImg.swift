//
//  QemuAdapter.swift
//  UTM Snapshot-Manager
//
//  Created by Jan Zombik on 04.03.23.
//

import Foundation

class QemuImg {
    private static let qemuImgPath = FileManager.default.fileExists(atPath:"/usr/local/bin/qemu-img") ? "/usr/local/bin/qemu-img" : "/opt/homebrew/bin/qemu-img"

    private static let snapshotLinePattern = /^\d+.*?\n/.anchorsMatchLineEndings()
    private static let idPattern = /^\d+/
    private static let tagPattern = /^\d+\s+(?<tag>.*?)\s/
    private static let dateTimePattern = /\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2}/
    
    private enum QemuImgCommand: String {
        case info = "info"
        case snapshot = "snapshot"
    }
    
    private enum QemuImgSnapshotSubcommand: String {
        case none
        case create = "-c"
        case delete = "-d"
        case restore = "-a"
    }
    
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
            
            // "suspend" is a reserved name for UTM suspension snapshots
            if (snapshot.tag != "suspend") {
                snapshots.append(snapshot)
            }
        }
        
        return snapshots
    }
    
    static func createSnapshotForImageUrl(_ url: URL, snapshotTag: String = "") {
        var snapshotTag = snapshotTag
        
        if (snapshotTag.isEmpty) {
            var hasher = Hasher()
            
            hasher.combine(url)
            hasher.combine(Date.now)
            
            let hash = hasher.finalize()
            let hexString = String(format: "%02X", hash)
            snapshotTag = String(hexString.prefix(8))
        }
        
        self.runQemuImgCommand(.snapshot, snapshotSubCommand: .create, snapshotTag: snapshotTag, imageUrl: url)
    }
    
    static func deleteSnapshotForImageUrl(_ url: URL, snapshotTag: String) {
        self.runQemuImgCommand(.snapshot, snapshotSubCommand: .delete, snapshotTag: snapshotTag, imageUrl: url)
    }
    
    static func restoreSnapshotForImageUrl(_ url: URL, snapshotTag: String) {
        self.runQemuImgCommand(.snapshot, snapshotSubCommand: .restore, snapshotTag: snapshotTag, imageUrl: url)
    }
    
    private static func infoForImageUrl(_ url: URL) -> String? {
        return self.runQemuImgCommand(.info, imageUrl: url)
    }
    
    private static func snapshotFromString(_ snapshotString: String) -> VMSnapshot? {
        guard let id = self.idFromString(snapshotString),
              let tag = self.tagFromString(snapshotString),
              let creationDate = self.creationDateFromString(snapshotString)
        else {
            return nil
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
    
    @discardableResult private static func runQemuImgCommand(_ command: QemuImgCommand, snapshotSubCommand: QemuImgSnapshotSubcommand = .none, snapshotTag: String = "", imageUrl: URL) -> String? {
        guard command != .snapshot || (snapshotSubCommand != .none && !snapshotTag.isEmpty) else {
            return nil
        }
        
        var commandComponents: [String] = [Self.qemuImgPath, command.rawValue]
        if command == .snapshot {
            commandComponents.append(snapshotSubCommand.rawValue)
            commandComponents.append(snapshotTag)
        }
        commandComponents.append("\"\(imageUrl.path(percentEncoded: false))\"")
        
        let qemuImgCommand = commandComponents.joined(separator: " ")
        
        return try? self.runCommandInShell(qemuImgCommand)
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
