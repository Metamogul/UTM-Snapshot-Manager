//
//  ContentView.swift
//  UTM Snapshot-Manager
//
//  Created by Jan Zombik on 03.03.23.
//

import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @ObservedObject private var userSettings = UserSettings()
    
    let columns: [GridItem] = [.init(.fixed(400)), .init(.fixed(400))]
    
    var body: some View {
        NavigationSplitView {
            VMGroupsList()
                .environmentObject(userSettings)
        } detail: {
            Text(LocalizedStringKey("Please select a VM group on the left to display and edit the contained VMs, images and snapshots."))
                .padding()
        }
    }
    
    private func showOpenPanel() -> [URL]? {
        let utmType = UTType(filenameExtension: "utm", conformingTo: .package)
        let openPanel = NSOpenPanel()
        
        openPanel.allowedContentTypes = [utmType!]
        openPanel.allowsMultipleSelection = true
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = true
        
        let response = openPanel.runModal()
        return response == .OK ? openPanel.urls : nil
    }
    
    private func createDemoVMGroup() {
        guard let baseUrls = self.showOpenPanel() else {
            return
        }
        
        let vmUrls = FileManager.utmPackageURLsAt(baseUrls)
        let vms = vmUrls
            .filter { FileManager.isValidUTMPackageUrl($0) }
            .map { VM(validatedUrl: $0) }
        let vmTestGroup = VMGroup(id: UUID(), name: "Test", vms: vms)
        
        self.userSettings.vmGroups.append(vmTestGroup)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
    }
}
