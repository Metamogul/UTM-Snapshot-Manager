//
//  VMsView.swift
//  UTM Snapshot-Manager
//
//  Created by Jan Zombik on 06.03.23.
//

import SwiftUI

struct VMGroupsList: View {
    @EnvironmentObject private var userSettings: UserSettings
    @State private var presentingNewGroupSheet = false
    @State private var newGroupName = ""
    
    var body: some View {
        List {
            Section(header: Text(LocalizedStringKey("VM groups"))) {
                ForEach($userSettings.vmGroups) { $vmGroup in
                    VMGroupsListEntry(vmGroup: $vmGroup)
                }
                Button(action: presentNewGroupSheet) {
                    Label(LocalizedStringKey("New…"), systemImage: "plus")
                }
                .buttonStyle(.plain )
                .sheet(isPresented: self.$presentingNewGroupSheet) {
                    Form {
                        TextField(LocalizedStringKey("Name:"), text: self.$newGroupName)
                            .frame(minWidth: 150)
                        Button(LocalizedStringKey("Create"), action: createNewGroup)
                            .keyboardShortcut(.defaultAction)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 0)
    }
    
    private func presentNewGroupSheet() {
        self.newGroupName = ""
        self.presentingNewGroupSheet = true
    }
    
    private func createNewGroup() {
        self.presentingNewGroupSheet = false;
        userSettings.vmGroups.append(VMGroup(name: !self.newGroupName.isEmpty ? self.newGroupName : NSLocalizedString("NewGroup", comment: "Default name for new group")))
    }
}

struct VMGroupsListEntry: View {
    @EnvironmentObject private var userSettings: UserSettings
    @Binding var vmGroup: VMGroup
    
    @State private var presentingShouldRemoveAlert = false
    
    @State private var presentingRenameGroupSheet = false
    @State private var newGroupName = ""
    
    var body: some View {
        NavigationLink(destination: VMGroupDetailsView(vmGroup: $vmGroup)) {
            Label(vmGroup.name, systemImage: "rectangle.on.rectangle")
        }
        .contextMenu {
            Button(action: { presentingShouldRemoveAlert = true }) {
                Label(LocalizedStringKey("Remove"), systemImage: "trash")
                    .labelStyle(.titleAndIcon)
            }
            Divider()
            Button(action: presentRenameGroupSheet ) {
                Label(LocalizedStringKey("Rename"), systemImage: "character.cursor.ibeam")
                    .labelStyle(.titleAndIcon)
            }
        }
        .nameSheet(presentingSheet: $presentingRenameGroupSheet,
                   name: $newGroupName,
                   nameFieldTitle: LocalizedStringKey("New name:"),
                   buttonTitle: LocalizedStringKey("Rename"),
                   buttonAction: renameGroup
        )
        .snapshotManagerDialog(presentingDialog: $presentingShouldRemoveAlert,
                               title: LocalizedStringKey("Remove the selected group?"),
                               mainButtonTitle: LocalizedStringKey("Remove"),
                               mainButtonRole: .destructive,
                               mainButtonAction: removeGroup)
    }
    
    private func presentRenameGroupSheet() {
        self.newGroupName = self.vmGroup.name
        self.presentingRenameGroupSheet = true
    }
    
    private func renameGroup() {
        if !newGroupName.isEmpty {
            vmGroup.name = newGroupName
        }
    }
    
    private func removeGroup() {
        userSettings.vmGroups.removeAll(where: { $0.id == self.vmGroup.id })
    }
}

struct VMsView_Previews: PreviewProvider {
    static var previews: some View {
        VMGroupsList()
            .frame(maxWidth: 200)
            .environmentObject(UserSettings())
    }
}
