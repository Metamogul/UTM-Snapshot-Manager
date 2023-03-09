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
    
    @State private var selectedSnapshotID: VMSnapshot.ID?
    //StateObject private var snapshots: [VMSnapshot]
    
    var body: some View {
        Label(image.url.lastPathComponent, systemImage: "externaldrive")
            .foregroundColor(Color.black.opacity(0.6))
            .padding(.leading, VMSectionView.insetNormal)
            .padding(.bottom, VMSectionView.bottomPadding / 2)
            .padding(.top, VMSectionView.bottomPadding / 2)
        
        let snapshots = image.snapshots
        if snapshots.count == 0 {
            Text("This image does not contain any snapshots.")
                .padding(.leading, VMSectionView.insetDeep)
                .padding(.bottom, VMSectionView.bottomPadding)
                .font(Font.system(size: 11))
        } else {
            Table(snapshots, selection: $selectedSnapshotID) {
                TableColumn("ID") { Text($0.id.description) }
                TableColumn("Tag") { Text($0.tag) }
                TableColumn("Creation date") { Text($0.creationDate.formatted()) }
            }
            .frame(height: CGFloat(snapshots.count) * 24 + 24 + 33)
            .padding(.bottom, VMSectionView.bottomPadding)
            .scrollDisabled(true)
            .contextMenu {
                Button(action: removeSnapshot(snapshotID: selectedSnapshotID, fromImage: image)) {
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
    
    private func removeSnapshot(snapshotID: VMSnapshot.ID?, fromImage image: VMImage) -> () -> () {
        guard let snapshotID = snapshotID else {
            return {}
        }
        
        return {
            NSLog(snapshotID.description)
        }
    }
}

struct VMImageView_Previews: PreviewProvider {
    static var previews: some View {
        if let vm = UserSettings().vmGroups.last?.vms.first,
           let image = vm.images.first {
            VMImageView(vm: vm, image: image)
        }
    }
}
