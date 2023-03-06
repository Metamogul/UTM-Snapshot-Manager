//
//  VMGroupDetailsView.swift
//  UTM Snapshot-Manager
//
//  Created by Jan Zombik on 06.03.23.
//

import SwiftUI

struct VMGroupDetailsView: View {
    @Binding var vms: [VM]
    
    var body: some View {
        Text("Hello, World!")
    }
}

struct VMGroupDetailsView_Previews: PreviewProvider {
    @State static private var vms: [VM] = []
    
    static var previews: some View {
        VMGroupDetailsView(vms: $vms)
    }
}
