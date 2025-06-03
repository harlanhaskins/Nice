//
//  UserDefaultsKey.swift
//  Nice
//
//  Created by Harlan Haskins on 5/30/25.
//

import Foundation

/// Type-safe keys for UserDefaults storage
/// Prevents string literal errors and provides centralized key management
enum UserDefaultsKey: String {
    /// Device push notification token
    case deviceToken
    /// API authentication token
    case apiToken
}

extension UserDefaults {
    /// Type-safe string getter using UserDefaultsKey
    func string(forKey key: UserDefaultsKey) -> String? {
        string(forKey: key.rawValue)
    }

    /// Type-safe string setter using UserDefaultsKey
    func set(_ string: String?, forKey key: UserDefaultsKey) {
        set(string, forKey: key.rawValue)
    }

    /// Convenience property for API authentication token
    var apiToken: String? {
        get {
            string(forKey: .apiToken)
        } set {
            set(newValue, forKey: .apiToken)
        }
    }

    /// Convenience property for push notification token
    var pushToken: String? {
        get {
            string(forKey: .deviceToken)
        } set {
            set(newValue, forKey: .deviceToken)
        }
    }
}
