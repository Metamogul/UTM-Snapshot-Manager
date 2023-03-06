//
//  VMsView.swift
//  UTM Snapshot-Manager
//
//  Created by Jan Zombik on 06.03.23.
//

import SwiftUI

struct VMGroupsView: View {
    @ObservedObject private var userSettings = UserSettings()
    
    var body: some View {
        Section(header: Text("VM Groups")) {
            ForEach($userSettings.vmGroups) {_ in 
                
            }
            /*ForEach($userSettings.vmGroups) { vmGroupName in
                NavigationLink(destination: VMGroupDetailsView(config: $userSettings.vmGroups[vmGroupName])).scrollable()) {
                    Label("Display", systemImage: "rectangle.on.rectangle")
                }.contextMenu {
                    Button("Remove") {
                        // config.displays.removeAll(where: { $0.id == display.id })
                        userSettings.vmGroups.removeValue(forKey: $vmGroupName)
                    }
                }
            }*/
        }
    }
}

struct VMsView_Previews: PreviewProvider {
    static var previews: some View {
        VMGroupsView()
    }
}
