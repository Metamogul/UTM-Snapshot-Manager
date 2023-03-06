//
//  UserSettings.swift
//  UTM Snapshot-Manager
//
//  Created by Jan Zombik on 06.03.23.
//

import Foundation

class UserSettings: ObservableObject {
    private static let vmGroupsKey = "vmGroups"
    
    @Published var vmGroups: [String:[VM]] {
        didSet {
            let vmPathGroups = vmGroups.mapValues { $0.map { $0.url.path() } }
            UserDefaults.standard.set(vmPathGroups, forKey: UserSettings.vmGroupsKey)
        }
    }
    
    init() {
        var vmGroups: [String:[VM]] = [:]
        
        if let vmPathGroups = UserDefaults.standard.object(forKey: UserSettings.vmGroupsKey) as? [String: [String]] {
            vmGroups = UserSettings.vmGroupsFromPathGroups(vmPathGroups)
        }
        
        self.vmGroups = vmGroups
    }
    
    private static func vmGroupsFromPathGroups(_ vmPathGroups: [String: [String]]) -> [String:[VM]] {
        return vmPathGroups
            .mapValues { $0
                .filter { URL(string: $0) != nil }
                .map { URL(string: $0)! }
                .filter { FileManager.isValidUTMPackageUrl($0) }
                .map { VM(validatedUrl: $0) }
            }
    }
}
