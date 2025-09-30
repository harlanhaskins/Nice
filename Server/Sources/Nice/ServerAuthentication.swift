//
//  ServerAuthentication.swift
//  Nice
//
//  Created by Harlan Haskins on 5/12/25.
//

import Foundation

/// Authentication context for authenticated requests
/// Contains user information and JWT token string
struct ServerAuthentication {
    var user: User
    var tokenString: String
}
