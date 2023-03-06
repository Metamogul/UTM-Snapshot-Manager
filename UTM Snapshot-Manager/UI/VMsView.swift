//
//  VMsView.swift
//  UTM Snapshot-Manager
//
//  Created by Jan Zombik on 06.03.23.
//

import SwiftUI

struct VMsView: View {
    var body: some View {
        Text(/*@START_MENU_TOKEN@*/"Hello, World!"/*@END_MENU_TOKEN@*/)
    }
    
    /*@ObservedObject var config: UTMQemuConfiguration
    @EnvironmentObject private var data: UTMData

    @State private var infoActive: Bool = true
    @State private var isResetConfig: Bool = false
    @State private var isNewDriveShown: Bool = false
    
    var body: some View {
        Section(header: Text("VM Groups")) {
            ForEach($config.displays) { $display in
                NavigationLink(destination: VMConfigDisplayView(config: $display, system: $config.system).scrollable()) {
                    Label("Display", systemImage: "rectangle.on.rectangle")
                }.contextMenu {
                    DestructiveButton("Remove") {
                        config.displays.removeAll(where: { $0.id == display.id })
                    }
                }
            }
            ForEach($config.serials) { $serial in
                NavigationLink(destination: VMConfigSerialView(config: $serial, system: $config.system).scrollable()) {
                    Label("Serial", systemImage: "rectangle.connected.to.line.below")
                }.contextMenu {
                    DestructiveButton("Remove") {
                        config.serials.removeAll(where: { $0.id == serial.id })
                    }
                }
            }
            ForEach($config.networks) { $network in
                NavigationLink(destination: VMConfigNetworkView(config: $network, system: $config.system).scrollable()) {
                    Label("Network", systemImage: "network")
                }.contextMenu {
                    DestructiveButton("Remove") {
                        config.networks.removeAll(where: { $0.id == network.id })
                    }
                }
                if #available(macOS 12, *), network.mode == .emulated {
                    NavigationLink(destination: VMConfigNetworkPortForwardView(config: $network)) {
                        Label("Port Forward", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                            .padding(.leading)
                    }
                }
            }
            ForEach($config.sound) { $sound in
                NavigationLink(destination: VMConfigSoundView(config: $sound, system: $config.system).scrollable()) {
                    Label("Sound", systemImage: "speaker.wave.2")
                }.contextMenu {
                    DestructiveButton("Remove") {
                        config.sound.removeAll(where: { $0.id == sound.id })
                    }
                }
            }
            VMSettingsAddDeviceMenuView(config: config)
        }
        Section(header: Text("Drives")) {
            VMDrivesSettingsView(drives: $config.drives, template: UTMQemuConfigurationDrive(forArchitecture: config.system.architecture, target: config.system.target))
        }
    }*/
}

struct VMsView_Previews: PreviewProvider {
    static var previews: some View {
        VMsView()
    }
}
