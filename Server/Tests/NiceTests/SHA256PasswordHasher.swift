//
//  SHA256PasswordHasher.swift
//  Nice
//
//  Created by Harlan Haskins on 5/4/25.
//

import Foundation
import CryptoSwift
@testable import Nice

/// A fast password hasher for testing that uses SHA256 instead of scrypt
struct SHA256PasswordHasher: PasswordHashing {
    func computePasswordHash(password: String, salt: String) throws -> String {
        let saltBytes = [UInt8](hex: salt)
        let passwordBytes = [UInt8](password.utf8)
        
        // Combine password and salt
        let combined = passwordBytes + saltBytes
        
        // Hash with SHA256 (much faster than scrypt)
        let digest = SHA2(variant: .sha256).calculate(for: combined)
        return digest.toHexString()
    }
}
