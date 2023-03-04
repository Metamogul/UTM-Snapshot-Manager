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
            
            if fileURL.pathExtension == "utm" && NSWorkspace.shared.isFilePackage(atPath: fileURL.path(percentEncoded: false)){
                utmPackageURLs.append(fileURL)
            }
        }
         
        return utmPackageURLs
    }
}
