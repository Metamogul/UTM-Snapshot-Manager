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
    
    @State private var presentingNewSnapshotSheet = false
    @State private var newSnapshotName = ""
    
    @State private var presentingShouldRestoreAlert = false
    @State private var presentingShouldRemoveAlert = false
    
    var body: some View {
        if vmGroup.vms.isEmpty {
            Text(LocalizedStringKey("There are no VMs in this group so far. Use the + button in the navigation area of the menu bar to add VMs."))
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button(action: addVMs) {
                            Label(LocalizedStringKey("Add more VMs"), systemImage: "plus")
                        }
                        .help(LocalizedStringKey("Add more VMs to this group"))
                    }
                }
        } else {
            List {
                ForEach($vmGroup.vms) { $vm in
                    VMSectionView(vmGroup: $vmGroup, vm: $vm)
                }
            }
            .id(self.vmGroup)
            .toolbar {
                ToolbarItemGroup(placement: .principal) {
                    Button(action: { presentingShouldRestoreAlert = true }) {
                        Label(LocalizedStringKey("Restore latest snapshot"), systemImage: "clock.arrow.circlepath")
                    }
                    .help(LocalizedStringKey("Restore the latest snapshot for all images in this group"))
                    Button(action: { presentingShouldRemoveAlert = true }) {
                        Label(LocalizedStringKey("Remove latest snapshot"), systemImage: "minus.circle")
                    }
                    .help(LocalizedStringKey("Remove the latest snapshot for all images in this group"))
                    Button(action: { presentingNewSnapshotSheet = true }) {
                        Label(LocalizedStringKey("Create new snapshot"), systemImage: "plus.circle")
                    }
                    .help(LocalizedStringKey("Create a new snapshot for all images in this group"))
                }
                ToolbarItem(placement: .navigation) {
                    Button(action: addVMs) {
                        Label(LocalizedStringKey("Add more VMs"), systemImage: "plus")
                    }
                    .help(LocalizedStringKey("Add more VMs to this group"))
                }
            }
            .navigationTitle(vmGroup.name)
            .newSnapshotSheet(
                presentingSheet: $presentingNewSnapshotSheet,
                name: $newSnapshotName,
                buttonAction: pushSnapshot
            )
            .snapshotManagerDialog(presentingDialog: $presentingShouldRestoreAlert,
                                   title: LocalizedStringKey("Restore latest snapshot for all images in this group?"),
                                   mainButtonTitle: LocalizedStringKey("Restore"),
                                   mainButtonAction: restoreLatestSnapshot
            )
            .snapshotManagerDialog(presentingDialog: $presentingShouldRemoveAlert,
                                   title: LocalizedStringKey("Remove latest snapshot for all images in this group?"),
                                   mainButtonTitle: LocalizedStringKey("Remove"),
                                   mainButtonRole: .destructive,
                                   mainButtonAction: popSnapshot)
        }
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
                image.createSnapshot(self.newSnapshotName)
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
