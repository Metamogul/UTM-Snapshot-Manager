//
//  UTM_Snapshot_ManagerApp.swift
//  UTM Snapshot-Manager
//
//  Created by Jan Zombik on 03.03.23.
//

import SwiftUI

@main
struct UTMSnapshotManagerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onDisappear() {
                    terminateApp()
                }
        }
    }
    
    private func terminateApp() {
        NSApplication.shared.terminate(self)
    }
    
    init() {
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        let searchUrl = URL(string: "Documents/dev/Virtual%20Machines.localized", relativeTo: homeURL)
        let utmPackageURLs = FileManager.utmPackageURLsAt(searchUrl)
        let vms = utmPackageURLs.map { VM(url: $0) }
        
        for vm in vms {
            var vmDebugDescription = ""
            if let vmUnwrapped = vm {
                vmDebugDescription = vmUnwrapped.url.debugDescription + "\n"
            }
            let imagesDebugDescription = vm?.images.debugDescription ?? ""
            NSLog(vmDebugDescription + imagesDebugDescription)
        }
    }
}
