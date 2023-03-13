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
    
    @State private var presentingNewSnapshotSheet = false
    @State private var newSnapshotName = ""
    
    @State private var presentingShouldRestoreAlert = false
    @State private var presentingShouldRemoveAlert = false
    
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
                    Button(action: { presentingShouldRestoreAlert = true }) {
                        Label(LocalizedStringKey("Restore Snapshot"), systemImage: "clock.arrow.circlepath")
                            .labelStyle(.titleAndIcon)
                    }
                    Button(action: { presentingShouldRemoveAlert = true }) {
                        Label(LocalizedStringKey("Remove Snapshot"), systemImage: "minus.circle")
                            .labelStyle(.titleAndIcon)
                    }
                } else {
                    Button(action: { presentingNewSnapshotSheet = true }) {
                        Label(LocalizedStringKey("Add Snapshot"), systemImage: "rectangle.stack.badge.plus")
                            .labelStyle(.titleAndIcon)
                    }
                }
            }
            .newSnapshotSheet(
                presentingSheet: $presentingNewSnapshotSheet,
                name: $newSnapshotName,
                buttonAction: addSnapshot
            )
            .snapshotManagerDialog(presentingDialog: $presentingShouldRestoreAlert,
                                   title: LocalizedStringKey("Restore selected snapshot?"),
                                   mainButtonTitle: LocalizedStringKey("Restore"),
                                   mainButtonAction: restoreSnapshot
            )
            .snapshotManagerDialog(presentingDialog: $presentingShouldRemoveAlert,
                                   title: LocalizedStringKey("Remove selected snapshot?"),
                                   mainButtonTitle: LocalizedStringKey("Remove"),
                                   mainButtonRole: .destructive,
                                   mainButtonAction: removeSnapshot
            )
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
    
    private func restoreSnapshot() {
        guard let snapshotID = self.selectedSnapshotID,
              let snapshot = self.image.snapshots.first(where: { $0.id == snapshotID }) else {
            return
        }
        
        self.image.restoreSnapshot(snapshot)
    }
    
    private func removeSnapshot() {
        guard let snapshotID = self.selectedSnapshotID,
              let snapshot = self.image.snapshots.first(where: { $0.id == snapshotID }) else {
            return
        }
        
        self.image.removeSnapshot(snapshot)
        self.selectedSnapshotID = nil
    }
    
    private func addSnapshot() {
        self.image.createSnapshot(self.newSnapshotName)
        let lastSnapshotID = self.image.snapshots.last?.id
        self.selectedSnapshotID = lastSnapshotID
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
