//
//  UserDefaultsExtension.swift
//  Roam
//
//  Created by Scott Driggers on 12/8/23.
//

import Foundation


public extension UserDefaults {
    static let roam: UserDefaults = UserDefaults(suiteName: "group.com.msdrigg.roam")!
}
