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
        
        var vms: [VM] = []
        for url in FileManager.utmPackageURLsAt(searchUrl) {
            guard let vm = VM(url: url) else {
                continue
            }
            
            vms.append(vm)
        }
        
        for vm: VM in vms {
            NSLog(vm.url.debugDescription + "\n" + vm.images.debugDescription)
            
            for image in vm.images {
                NSLog(image.snapshots.debugDescription)
            }
        }
    }
}
