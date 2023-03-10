//
//  VMsView.swift
//  UTM Snapshot-Manager
//
//  Created by Jan Zombik on 06.03.23.
//

import SwiftUI

struct VMGroupsList: View {
    @EnvironmentObject private var userSettings: UserSettings
    @State private var presentingNewGroupPopover: Bool = false
    @State private var newGroupName: String = ""
    
    struct PopoverModel: Identifiable {
        var id: String { message }
        let message: String
    }
    
    var body: some View {
        List {
            Section(header: Text(LocalizedStringKey("VM Groups"))) {
                ForEach($userSettings.vmGroups) { $vmGroup in
                    NavigationLink(destination: VMGroupDetailsView(vmGroup: $vmGroup)) {
                        Label(vmGroup.name, systemImage: "rectangle.on.rectangle")
                    }
                    .contextMenu {
                        Button(action: self.removeGroup(vmGroup)) {
                            Label(LocalizedStringKey("Remove"), systemImage: "trash")
                                .labelStyle(.titleAndIcon)
                        }
                        Divider()
                        Button {
                            
                        } label: {
                            Label(LocalizedStringKey("Rename"), systemImage: "character.cursor.ibeam")
                                .labelStyle(.titleAndIcon)
                        }

                    }
                }
                Button(action: presentNewGroupPopover) {
                    Label(LocalizedStringKey("New…"), systemImage: "plus")
                }
                .buttonStyle(.plain )
                .popover(isPresented: self.$presentingNewGroupPopover) {
                    VStack {
                        TextField(LocalizedStringKey("Name"), text: self.$newGroupName)
                            .frame(minWidth: 100)
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
    
    private func presentNewGroupPopover() {
        self.newGroupName = ""
        self.presentingNewGroupPopover = true
    }
    
    private func createNewGroup() {
        self.presentingNewGroupPopover = false;
        userSettings.vmGroups.append(VMGroup(name: !self.newGroupName.isEmpty ? self.newGroupName : NSLocalizedString("NewGroup", comment: "Default name for new group")))
    }
    
    private func removeGroup(_ vmGroup: VMGroup) -> () -> () {
        return {
            userSettings.vmGroups.removeAll(where: { $0.id == vmGroup.id })
        }
    }
}

struct VMsView_Previews: PreviewProvider {
    static var previews: some View {
        VMGroupsList()
            .frame(maxWidth: 200)
            .environmentObject(UserSettings())
    }
}
