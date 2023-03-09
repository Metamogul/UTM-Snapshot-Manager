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
    
    private static let bottomPadding: CGFloat = 10
    private static let insetNormal: CGFloat = 15
    private static let insetDeep: CGFloat = 18

    var body: some View {
        List {
            ForEach($vmGroup.vms) { $vm in
                Section {
                    VStack(alignment: .leading, spacing: 0) {
                        if vm.images.count == 0 {
                            Text("This VM does not contain any images.")
                                .padding(.leading, Self.insetNormal)
                                .padding(.bottom, Self.bottomPadding)
                        }
                        ForEach(vm.images) { image in
                            Label(image.url.lastPathComponent, systemImage: "externaldrive")
                                .foregroundColor(Color.black.opacity(0.6))
                                .padding(.leading, Self.insetNormal)
                                .padding(.bottom, Self.bottomPadding / 2)
                                .padding(.top, Self.bottomPadding / 2)
                            
                            let snaphots = image.snapshots
                            if snaphots.count == 0 {
                                Text("This image does not contain any snapshots.")
                                    .padding(.leading, Self.insetDeep)
                                    .padding(.bottom, Self.bottomPadding)
                                    .font(Font.system(size: 11))
                            } else {
                                Table(of: VMSnapshot.self) {
                                    TableColumn("ID") { Text($0.id.description) }
                                    TableColumn("Tag") { Text($0.tag) }
                                    TableColumn("Creation date") { Text($0.creationDate.formatted()) }
                                } rows: {
                                    ForEach(snaphots) { TableRow($0) }
                                }
                                .frame(height: CGFloat(snaphots.count) * 28 + 26)
                                .padding(.bottom, Self.bottomPadding)
                                .scrollDisabled(true)
                            }
                            if vm.images.last != image {
                                if vm.images.last?.snapshots.count ?? 0 > 0 {
                                    Divider()
                                        .padding(.bottom, Self.bottomPadding + 4)
                                } else {
                                    Divider()
                                        .padding(.leading, Self.insetDeep)
                                        .padding(.bottom, Self.bottomPadding + 4)
                                }
                            }
                        }
                        if vmGroup.vms.last != vm {
                            Divider()
                                .padding(.leading, Self.insetNormal)
                                .padding(.bottom, Self.bottomPadding)
                        }
                    }
                } header: {
                    HStack {
                        Button(action: removeVM(vm)) {
                            Label("Remove VM", systemImage: "trash")
                                .labelStyle(.iconOnly)
                        }
                        .padding(6)
                        .buttonStyle(RemoveButtonStyle())
                        Text(vm.url.lastPathComponent)
                            .font(Font.system(size: 13, weight: Font.Weight.medium))
                            .foregroundColor(Color.black)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                    }
                }
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
                .font(Font.system(size: 11, weight: Font.Weight.regular))
                .fontWeight(Font.Weight.regular)
        }
    }
}

struct VMGroupDetailsView_Previews: PreviewProvider {
    @State static private var vmGroup = VMGroup()
    
    static var previews: some View {
        VMGroupDetailsView(vmGroup: $vmGroup)
    }
}
