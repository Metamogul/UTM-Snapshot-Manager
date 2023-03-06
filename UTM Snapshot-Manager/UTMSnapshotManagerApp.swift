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
            MainView()
                .onDisappear() {
                    terminateApp()
                }
        }
    }
    
    private func terminateApp() {
        NSApplication.shared.terminate(self)
    }
}
