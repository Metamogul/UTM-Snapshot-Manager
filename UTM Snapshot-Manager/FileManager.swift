//
//  FileSystemAdapter.swift
//  UTM Snapshot-Manager
//
//  Created by Jan Zombik on 04.03.23.
//

import Foundation
import Cocoa

extension FileManager {
    static func qcow2FileURLsAt(_ url: URL?) -> [URL] {
        guard let urlUnwrapped = url else {
            return []
        }
         
        let resourceKeys = Set<URLResourceKey>([.nameKey, .isDirectoryKey])
        let directoryEnumerator = FileManager.default.enumerator(at: urlUnwrapped, includingPropertiesForKeys: Array(resourceKeys), options: .skipsHiddenFiles)!
         
        var qcow2FileURLs: [URL] = []
        for case let fileURL as URL in directoryEnumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: resourceKeys),
                let isDirectory = resourceValues.isDirectory,
                let name = resourceValues.name
                else {
                    continue
            }
            
            if isDirectory {
                if name == "_extras" {
                    directoryEnumerator.skipDescendants()
                }
                continue
            }
            
            if fileURL.pathExtension == "qcow2" {
                qcow2FileURLs.append(fileURL)
            }
        }
         
        return qcow2FileURLs
    }
    
    static func utmPackageURLsAt(_ url: URL?) -> [URL] {
        guard let urlUnwrapped = url else {
            return []
        }
        
        if self.isValidUTMPackageUrl(urlUnwrapped) {
            return [urlUnwrapped]
        }
         
        let resourceKeys = Set<URLResourceKey>([.nameKey, .isDirectoryKey])
        let directoryEnumerator = FileManager.default.enumerator(at: urlUnwrapped, includingPropertiesForKeys: Array(resourceKeys), options: .skipsHiddenFiles)!
         
        var utmPackageURLs: [URL] = []
        for case let fileURL as URL in directoryEnumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: resourceKeys),
                let isDirectory = resourceValues.isDirectory,
                let name = resourceValues.name
                else {
                    continue
            }
            
            if isDirectory && name == "_extras" {
                directoryEnumerator.skipDescendants()
                continue
            }
            
            if self.isValidUTMPackageUrl(fileURL) {
                utmPackageURLs.append(fileURL)
            }
        }
         
        return utmPackageURLs
    }
    
    static func utmPackageURLsAt(_ urls: [URL]) -> [URL] {
        var utmPackageURLs: [URL] = []
        
        for url in urls {
            utmPackageURLs.append(contentsOf: self.utmPackageURLsAt(url))
        }
        
        return utmPackageURLs
    }
    
    static func isValidQcow2ImageUrl(_ url: URL) -> Bool {
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
    
    static func isValidUTMPackageUrl(_ url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        if !FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory) {
            return false
        }
        
        if !isDirectory.boolValue {
            return false;
        }
        
        if !FileManager.default.isReadableFile(atPath: url.path(percentEncoded: false)) {
            return false
        }
        
        if !FileManager.default.isWritableFile(atPath: url.path(percentEncoded: false)) {
            return false
        }
        
        if url.pathExtension != "utm" {
            return false
        }
        
        if !NSWorkspace.shared.isFilePackage(atPath: url.path(percentEncoded: false)) {
            return false
        }
        
        return true
    }
}
