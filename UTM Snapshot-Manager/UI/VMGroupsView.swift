//
//  VMsView.swift
//  UTM Snapshot-Manager
//
//  Created by Jan Zombik on 06.03.23.
//

import SwiftUI

struct VMGroupsView: View {
    @EnvironmentObject private var userSettings: UserSettings
    
    var body: some View {
        Section(header: Text("VM Groups")) {
            ForEach($userSettings.vmGroups) { $vmGroup in
                NavigationLink(destination: VMGroupDetailsView(vmGroup: $vmGroup)) {
                    Label(vmGroup.name, systemImage: "server.rack")
                }.contextMenu {
                    Button("Remove") {
                        userSettings.vmGroups.removeAll(where: { $0.id == vmGroup.id })
                    }
                }
            }
        }
    }
}

struct VMsView_Previews: PreviewProvider {
    static var previews: some View {
        VMGroupsView()
    }
}
