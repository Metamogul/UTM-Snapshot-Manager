//
//  VMImageView.swift
//  UTM Snapshot-Manager
//
//  Created by Jan Zombik on 09.03.23.
//

import SwiftUI

struct VMImageView: View {
    var vm: VM
    var image: VMImage
    
    @State private var selectedSnapshot: VMSnapshot = VMSnapshot(id: 0, tag: "", creationDate: Date.now)
    
    var body: some View {
        Label(image.url.lastPathComponent, systemImage: "externaldrive")
            .foregroundColor(Color.black.opacity(0.6))
            .padding(.leading, VMSectionView.insetNormal)
            .padding(.bottom, VMSectionView.bottomPadding / 2)
            .padding(.top, VMSectionView.bottomPadding / 2)
        
        let snaphots = image.snapshots
        if snaphots.count == 0 {
            Text("This image does not contain any snapshots.")
                .padding(.leading, VMSectionView.insetDeep)
                .padding(.bottom, VMSectionView.bottomPadding)
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
            .padding(.bottom, VMSectionView.bottomPadding)
            .scrollDisabled(true)
            .contextMenu {
                Button(action: removeSnapshot(selectedSnapshot, fromImage: image)) {
                    Label("Remove", systemImage: "trash")
                        .labelStyle(.titleAndIcon)
                }
            }
        }
        if vm.images.last != image {
            if vm.images.last?.snapshots.count ?? 0 > 0 {
                Divider()
                    .padding(.bottom, VMSectionView.bottomPadding + 4)
            } else {
                Divider()
                    .padding(.leading, VMSectionView.insetDeep)
                    .padding(.bottom, VMSectionView.bottomPadding + 4)
            }
        }
    }
    
    private func removeSnapshot(_ snapshot: VMSnapshot, fromImage iamge: VMImage) -> () -> () {
        return {
            // TODO: Stub, implement
        }
    }
}

struct VMImageView_Previews: PreviewProvider {
    static var previews: some View {
        if let vm = UserSettings().vmGroups.first?.vms.first,
           let image = vm.images.first {
            VMImageView(vm: vm, image: image)
        }
    }
}
