//
//  VMGroupDetailsView.swift
//  UTM Snapshot-Manager
//
//  Created by Jan Zombik on 06.03.23.
//

import SwiftUI
import UniformTypeIdentifiers

struct VMGroupDetailsView: View {
    @Binding var vmGroup: VMGroup
    
    var body: some View {
        List {
            ForEach($vmGroup.vms) { $vm in
                VMSectionView(vmGroup: $vmGroup, vm: $vm)
            }
        }
        .id(self.vmGroup)
        .toolbar {
            ToolbarItemGroup(placement: .principal) {
                Button(action: addVMs) {
                    Label("Add more VMs", systemImage: "plus")
                }
                .help("Add more VMs to this group")
                
                Spacer(minLength: 10)
                
                Button(action: restoreLatestSnapshot) {
                    Label("Restore latest snapshot", systemImage: "gobackward")
                }
                .help("Restore the latest snapshot for all images in this group")
                Button(action: popSnapshot) {
                    Label("Remove latest snapshot", systemImage: "rectangle.stack.badge.minus")
                }
                .help("Remove the latest snapshot for all images in this group")
                Button(action: pushSnapshot) {
                    Label("Create new snapshot", systemImage: "rectangle.stack.badge.plus")
                }
                .help("Create a new snapshot for all images in this group")
            }
        }
        .navigationTitle(vmGroup.name)
    }
    
    private func addVMs() {
        let utmType = UTType(filenameExtension: "utm", conformingTo: .package)
        let openPanel = NSOpenPanel()
        
        openPanel.allowedContentTypes = [utmType!]
        openPanel.allowsMultipleSelection = true
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = true
        
        guard let urls = openPanel.runModal() == .OK ? openPanel.urls : nil else {
            return
        }
        
        let existingUrls = vmGroup.vms.map { $0.url }
        let newVMUrls = FileManager.utmPackageURLsAt(urls)
        for url in newVMUrls {
            guard !existingUrls.contains(url) else {
                continue
            }
            
            guard FileManager.isValidUTMPackageUrl(url) else {
                continue
            }
            
            vmGroup.vms.append( VM(validatedUrl: url))
        }
    }
    
    private func pushSnapshot() {
        for vm in self.vmGroup.vms.filter({ FileManager.isValidUTMPackageUrl($0.url) }) {
            for image in vm.images {
                image.createSnapshot()
            }
        }
    }
    
    private func popSnapshot() {
        for vm in self.vmGroup.vms.filter({ FileManager.isValidUTMPackageUrl($0.url) }) {
            for image in vm.images {
                if let latestSnapshot = image.snapshots.last {
                    image.removeSnapshot(latestSnapshot)
                }
            }
        }
    }
    
    private func restoreLatestSnapshot() {
        for vm in self.vmGroup.vms.filter({ FileManager.isValidUTMPackageUrl($0.url) }) {
            for image in vm.images {
                if let latestSnapshot = image.snapshots.last {
                    image.restoreSnapshot(latestSnapshot)
                }
            }
        }
    }
}

struct VMGroupDetailsViewPreviewWrapper<VMGroup, Content: View>: View {
    @State var vmGroup: VMGroup
    
    var content: (Binding<VMGroup>) -> Content

    var body: some View {
        content($vmGroup)
    }

    init(vmGroup: VMGroup, content: @escaping (Binding<VMGroup>) -> Content) {
        self._vmGroup = State(wrappedValue: vmGroup)
        self.content = content
    }
}

struct VMGroupDetailsView_Previews: PreviewProvider {
    static var previews: some View {
        if let vmGroup = UserSettings().vmGroups.first {
            VMGroupDetailsViewPreviewWrapper(vmGroup: vmGroup) {
                VMGroupDetailsView(vmGroup: $0)
                    .frame(minHeight: 800)
            }
        }
        
    }
}
