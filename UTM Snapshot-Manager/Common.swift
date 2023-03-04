//
//  Common.swift
//  UTM Snapshot-Manager
//
//  Created by Jan Zombik on 04.03.23.
//

import Foundation

struct VMSnapShot {
    let tag: String
    let creationDate: Date
}

struct VMImage {
    let url: URL
    var snapshots: [String: VMSnapShot] {
        get {
            return [:]
        }
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
}

struct VM {
    let url: URL
    var images: [VMImage] {
        get {
            return FileManager.qcow2FileURLsAt(url)
                .filter { VMImage.validateURL($0) }
                .map { VMImage(validatedURL: $0) }
        }
    }
    
    init?(url: URL) {
        var isDirectory = ObjCBool(false)
        
        if !FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory:&isDirectory) {
            return nil;
        }
        
        if !isDirectory.boolValue {
            return nil;
        }
        
        self.url = url
    }
}
