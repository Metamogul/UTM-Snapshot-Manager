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
                Section(header: Text(vm.url.lastPathComponent)) {
                    VStack {
                        ForEach(vm.images) { image in
                            let snaphots = image.snapshots
                            Label(image.url.lastPathComponent, systemImage: "externaldrive")
                                .frame(maxWidth: .infinity, alignment: Alignment.leading)
                                .font(Font.system(size: 11))
                                .padding(.leading, 15)
                            Table(of: VMSnapshot.self) {
                                TableColumn("ID") { Text($0.id.description) }
                                TableColumn("Tag") { Text($0.tag) }
                                TableColumn("Creation date") { Text($0.creationDate.formatted()) }
                            } rows: {
                                ForEach(snaphots) { TableRow($0) }
                            }
                            .frame(height: CGFloat(snaphots.count) * 28 + 28)
                            .padding(.bottom, 10)
                            .scrollDisabled(true)
                        }
                        Button("Remove VM", action: removeVM(vm))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.trailing, 11)
                            .buttonStyle(RemoveButtonStyle())
                    }
                    .padding(.top, 12)
                }
            }
        }
        .id(self.vmGroup)
        .toolbar {
            ToolbarItemGroup(placement: .principal) {
                Button(action: popSnapshot) {
                    Label("Remove latest snapshot", systemImage: "rectangle.stack.badge.minus")
                }
                .help("Remove the latest snapshot for all VMs in group")
                Button(action: pushSnapshot) {
                    Label("Create new snapshot", systemImage: "rectangle.stack.badge.plus")
                }
                .help("Create a new snapshot for all VMs in group")
            }
            ToolbarItem(placement: .secondaryAction) {
                Button(action: addVMs) {
                    Label("Create new snapshot", systemImage: "plus")
                }
                .help("Add more VMs")
            }
        }
        .navigationTitle(vmGroup.name)
    }
    
    private func removeVM(_ vm: VM) -> () -> () {
        return {
            vmGroup.vms.removeAll { $0 == vm }
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
        
    }
    
    private func popSnapshot() {
        
    }
    
    private struct RemoveButtonStyle: ButtonStyle {
        func makeBody(configuration: Self.Configuration) -> some View {
            configuration.label
                .padding([.trailing, .leading], 9)
                .padding([.top, .bottom], 5)
                .foregroundColor(configuration.isPressed ? Color.white : Color.pink)
                .background(configuration.isPressed ? Color.pink : Color.pink.opacity(0.2))
                .cornerRadius(6.0)
                .clipShape(ContainerRelativeShape())
        }
    }
}

struct VMGroupDetailsView_Previews: PreviewProvider {
    @State static private var vmGroup = VMGroup()
    
    static var previews: some View {
        VMGroupDetailsView(vmGroup: $vmGroup)
    }
}
