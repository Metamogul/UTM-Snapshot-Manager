//
//  QemuAdapter.swift
//  UTM Snapshot-Manager
//
//  Created by Jan Zombik on 04.03.23.
//

import Foundation

class QemuImg {
    static let qemuImgPath = "/opt/homebrew/bin/qemu-img"
    
    static func infoForImage(_ image: VMImage) -> String? {
        let qemuImgCommandBase = "\(qemuImgPath) info"
        let qemuImgParameter = image.url.path(percentEncoded: false)
        
        let qemuImgCommand = "\(qemuImgCommandBase) \"\(qemuImgParameter)\""
        
        return try? self.runCommandInShell(qemuImgCommand)
    }
    
    @discardableResult
    private static func runCommandInShell(_ command: String) throws -> String {
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
