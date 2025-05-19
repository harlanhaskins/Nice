//
//  AuthenticatorTests.swift
//  Nice
//
//  Created by Harlan Haskins on 5/4/25.
//

import Foundation
import Hummingbird
@testable import Nice
import SQLite
import Testing

@Suite
struct AuthenticatorTests {
    
    @Test
    func testExtractToken() throws {
        let db = try Connection(.inMemory)
        let controller = UserController(db: db, passwordHasher: SHA256PasswordHasher())
        let authenticator = Authenticator(userController: controller)
        
        let headers: HTTPFields = [.authorization: "Bearer token123"]
        let token = try authenticator.extractToken(from: headers)
        
        #expect(token == "token123")
    }
    
    @Test
    func testMissingAuthorizationHeader() throws {
        let db = try Connection(.inMemory)
        let controller = UserController(db: db, passwordHasher: SHA256PasswordHasher())
        let authenticator = Authenticator(userController: controller)
        
        let headers: HTTPFields = [:]

        #expect(throws: AuthenticatorError.missingAuthorizationHeader) {
            _ = try authenticator.extractToken(from: headers)
        }
    }
    
    @Test
    func testInvalidAuthorizationHeader() throws {
        let db = try Connection(.inMemory)
        let controller = UserController(db: db, passwordHasher: SHA256PasswordHasher())
        let authenticator = Authenticator(userController: controller)
        
        let headers: HTTPFields = [.authorization: "InvalidHeader"]

        #expect(throws: AuthenticatorError.invalidAuthorizationHeader) {
            _ = try authenticator.extractToken(from: headers)
        }
        
        let headers2: HTTPFields = [.authorization: "Basic abc123"]

        #expect(throws: AuthenticatorError.invalidAuthorizationHeader) {
            _ = try authenticator.extractToken(from: headers2)
        }
    }

    @Test
    func testAuthenticatedUser() throws {
        let db = try Connection(.inMemory)
        let controller = UserController(db: db, passwordHasher: SHA256PasswordHasher())
        try controller.createTables()
        let authenticator = Authenticator(userController: controller)
        
        // Create a user and get a token
        let (createdUser, token) = try controller.create(username: "homestar", password: "RunnerPassword123", location: nil)

        // Create token auth headers
        let headers: HTTPFields = [.authorization: "Bearer \(token.content)"]

        // Test getting authenticated user
        let auth = try authenticator.authentication(headers: headers)
        #expect(auth.user.id == createdUser.id)
        #expect(auth.user.username == "homestar")
    }
}
