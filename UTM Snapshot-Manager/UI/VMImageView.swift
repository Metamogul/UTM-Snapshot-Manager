//
//  VMImageView.swift
//  UTM Snapshot-Manager
//
//  Created by Jan Zombik on 09.03.23.
//

import SwiftUI

struct VMImageView: View {
    var vm: VM
    @StateObject var image: VMImage
    
    @State private var selectedSnapshotID: VMSnapshot.ID?
    
    var body: some View {
        Label(image.url.lastPathComponent, systemImage: "externaldrive")
            .foregroundColor(Color.black.opacity(0.6))
            .padding(.leading, VMSectionView.insetNormal)
            .padding(.bottom, VMSectionView.bottomPadding / 2)
            .padding(.top, VMSectionView.bottomPadding / 2)
        
        if image.snapshots.count == 0 {
            Text(LocalizedStringKey("This image does not contain any snapshots."))
                .padding(.leading, VMSectionView.insetDeep)
                .padding(.bottom, VMSectionView.bottomPadding)
                .font(Font.system(size: 11))
        } else {
            Table(image.snapshots, selection: $selectedSnapshotID) {
                TableColumn(LocalizedStringKey("ID")) { Text($0.id.description) }
                TableColumn(LocalizedStringKey("Tag")) { Text($0.tag) }
                TableColumn(LocalizedStringKey("Creation date")) { Text($0.creationDate.formatted()) }
            }
            .frame(height: CGFloat(image.snapshots.count) * 24 + 24 + 33)
            .padding(.bottom, VMSectionView.bottomPadding)
            .scrollDisabled(true)
            .contextMenu {
                if selectedSnapshotID != nil {
                    Button(action: restoreSnapshot(snapshotID: selectedSnapshotID, atImage: image)) {
                        Label(LocalizedStringKey("Restore Snapshot"), systemImage: "gobackward")
                            .labelStyle(.titleAndIcon)
                    }
                    Button(action: removeSnapshot(snapshotID: selectedSnapshotID, fromImage: image)) {
                        Label(LocalizedStringKey("Remove Snapshot"), systemImage: "trash")
                            .labelStyle(.titleAndIcon)
                    }
                } else {
                    Button(action: addSnapshot(toImage: image)) {
                        Label(LocalizedStringKey("Add Snapshot"), systemImage: "rectangle.stack.badge.plus")
                            .labelStyle(.titleAndIcon)
                    }
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
    
    private func restoreSnapshot(snapshotID: VMSnapshot.ID?, atImage image: VMImage) -> () -> () {
        guard let snapshotID = snapshotID else {
            return {}
        }
        
        return {
            if let snapshot = image.snapshots.first(where: { $0.id == snapshotID }) {
                image.restoreSnapshot(snapshot)
            }
        }
    }
    
    private func removeSnapshot(snapshotID: VMSnapshot.ID?, fromImage image: VMImage) -> () -> () {
        guard let snapshotID = snapshotID else {
            return {}
        }
        
        return {
            if let snapshot = image.snapshots.first(where: { $0.id == snapshotID }) {
                image.removeSnapshot(snapshot)
                self.selectedSnapshotID = nil
            }
        }
    }
    
    private func addSnapshot(toImage image: VMImage) -> () -> () {{
        image.createSnapshot()
        let lastSnapshotID = image.snapshots.last?.id
        self.selectedSnapshotID = lastSnapshotID
    }}
}

struct VMImageView_Previews: PreviewProvider {
    static var previews: some View {
        if let vm = UserSettings().vmGroups.last?.vms.first,
           let image = vm.images.first {
            VMImageView(vm: vm, image: image)
        }
    }
}
