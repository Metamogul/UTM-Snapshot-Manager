//
//  UserSettings.swift
//  UTM Snapshot-Manager
//
//  Created by Jan Zombik on 06.03.23.
//

import Foundation

class UserSettings: ObservableObject {
    private static let vmGroupsEncodedKey = "vmGroupsEncoded"
    
    @Published var vmGroups: [VMGroup] {
        didSet {
            let encoder = JSONEncoder()
            if let vmGroupsEncoded = try? encoder.encode(vmGroups) {
                UserDefaults.standard.set(vmGroupsEncoded, forKey: UserSettings.vmGroupsEncodedKey)
            }
            
        }
    }
    
    init() {
        guard let vmGroupsEncoded = UserDefaults.standard.object(forKey: UserSettings.vmGroupsEncodedKey) as? Data else {
            self.vmGroups = []
            return
        }
        
        let decoder = JSONDecoder()
        guard let vmGroups = try? decoder.decode([VMGroup].self, from: vmGroupsEncoded) else {
            self.vmGroups = []
            return
        }
        
        self.vmGroups = vmGroups;
    }
}
