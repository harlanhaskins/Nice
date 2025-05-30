//
//  UserDefaultsKey.swift
//  Nice
//
//  Created by Harlan Haskins on 5/30/25.
//

import Foundation

enum UserDefaultsKey: String {
    case deviceToken
    case apiToken
}

extension UserDefaults {
    func string(forKey key: UserDefaultsKey) -> String? {
        string(forKey: key.rawValue)
    }

    func set(_ string: String?, forKey key: UserDefaultsKey) {
        set(string, forKey: key.rawValue)
    }

    var apiToken: String? {
        get {
            string(forKey: .apiToken)
        } set {
            set(newValue, forKey: .apiToken)
        }
    }

    var pushToken: String? {
        get {
            string(forKey: .deviceToken)
        } set {
            set(newValue, forKey: .deviceToken)
        }
    }
}
