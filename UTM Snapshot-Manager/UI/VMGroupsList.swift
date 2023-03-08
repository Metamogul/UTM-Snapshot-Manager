//
//  VMsView.swift
//  UTM Snapshot-Manager
//
//  Created by Jan Zombik on 06.03.23.
//

import SwiftUI

struct VMGroupsList: View {
    @EnvironmentObject private var userSettings: UserSettings
    @State private var presentNewGroupPopover: Bool = false
    @State private var newGroupName: String = ""
    
    struct PopoverModel: Identifiable {
        var id: String { message }
        let message: String
    }
    
    var body: some View {
        List {
            Section(header: Text("VM Groups")) {
                ForEach($userSettings.vmGroups) { $vmGroup in
                    NavigationLink(destination: VMGroupDetailsView(vmGroup: $vmGroup)) {
                        Label(vmGroup.name, systemImage: "rectangle.on.rectangle")
                    }
                    .contextMenu {
                        Button("Remove") {
                            userSettings.vmGroups.removeAll(where: { $0.id == vmGroup.id })
                        }
                    }
                }
                Button {
                    self.newGroupName = ""
                    self.presentNewGroupPopover = true
                } label: {
                    Label("New…", systemImage: "plus")
                }
                .buttonStyle(.plain )
                .popover(isPresented: self.$presentNewGroupPopover) {
                    VStack {
                        TextField("Name", text: self.$newGroupName)
                            .frame(minWidth: 100)
                        Button("Create", action: createNewGroup)
                            .keyboardShortcut(.defaultAction)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 0)
    }
    
    private func createNewGroup() {
        self.presentNewGroupPopover = false;
        userSettings.vmGroups.append(VMGroup(name: !self.newGroupName.isEmpty ? self.newGroupName : "New Group"))
    }
}

struct VMsView_Previews: PreviewProvider {
    static var previews: some View {
        VMGroupsList()
            .frame(maxWidth: 200)
            .environmentObject(UserSettings())
    }
}
