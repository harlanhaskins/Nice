//
//  UserController.swift
//  Nice
//
//  Created by Harlan Haskins on 5/3/25.
//

import CryptoSwift
import NiceTypes
@preconcurrency import SQLite
import Foundation
import Hummingbird
import HummingbirdAuth
import Logging

/// Database model for user accounts
/// Stores authentication credentials with secure password hashing
struct User: Model, Codable {
    /// Database column expressions for type-safe queries
    static let id = Expression<Int64>("id")
    static let username = Expression<String>("username")
    static let passwordHash = Expression<String>("passwordHash")
    static let salt = Expression<String>("salt")

    /// Unique user identifier (auto-incrementing primary key)
    let id: Int64
    /// Normalized username (trimmed, lowercased, unique)
    var username: String
    /// Scrypt-hashed password for secure storage
    var passwordHash: String
    /// Random salt used for password hashing
    var salt: String
}

extension User {
    init(_ row: Row) {
        id = row[User.id]
        username = row[User.username]
        passwordHash = row[User.passwordHash]
        salt = row[User.salt]
    }
}

/// Database model for authentication tokens
/// Each user has at most one active token (1:1 relationship)
struct Token: Model, Codable {
    /// Database column expressions for type-safe queries
    static let id = Expression<Int64>("id")
    static let userID = Expression<Int64>("userID")
    static let content = Expression<String>("content")
    static let expires = Expression<Int64>("expires")

    /// Unique token identifier
    var id: Int64
    /// Foreign key to user table (unique constraint)
    var userID: Int64
    /// Hex-encoded token string (unique)
    var content: String
    /// Expiration timestamp (14 days from creation/refresh)
    var expires: Date

    /// Convert to DTO for API responses
    var dto: TokenDTO {
        TokenDTO(userID: userID, token: content, expires: expires)
    }
}

extension Authentication {
    init(user: User, token: Token, location: Location?) {
        self.init(
            user: UserDTO(id: user.id, username: user.username, location: location),
            token: token.dto
        )
    }
}

extension Token {
    init(_ row: Row) {
        id = row[Token.id]
        userID = row[Token.userID]
        content = row[Token.content]
        expires = Date(timeIntervalSince1970: TimeInterval(row[Token.expires]))
    }
}

/// Protocol for date operations (enables testing with mock dates)
/// Provides current time and token expiration calculation
protocol DateProviding: Sendable {
    /// Current date and time
    var now: Date { get }
    /// New expiration date for tokens (14 days from now)
    var newExpirationDate: Date { get }
}

struct CalendarDateProvider: DateProviding {
    var calendar: Calendar

    var now: Date { .now }

    func date(byAdding component: Calendar.Component, value: Int, to date: Date) -> Date? {
        calendar.date(byAdding: component, value: value, to: date)
    }

    var newExpirationDate: Date {
        calendar.date(byAdding: .day, value: 14, to: now)!
    }
}

/// Protocol for secure password hashing operations
/// Uses Scrypt algorithm for resistance against brute-force attacks
protocol PasswordHashing: Sendable {
    /// Compute secure hash of password with salt
    /// - Parameters:
    ///   - password: Plain text password
    ///   - salt: Random salt for this user
    /// - Returns: Hex-encoded hash string
    func computePasswordHash(password: String, salt: String) throws -> String
}

struct ScryptPasswordHasher: PasswordHashing {
    func computePasswordHash(password: String, salt: String) throws -> String {
        let scrypt = try Scrypt(
            password: [UInt8](password.utf8),
            salt: [UInt8](hex: salt),
            dkLen: 64,
            N: 16384,
            r: 8,
            p: 1
        )
        let digest = try scrypt.calculate()
        return digest.toHexString()
    }
}

/// Controller for user management operations
/// Handles authentication, registration, and user lifecycle
final class UserController: Sendable {
    /// Domain-specific errors for user operations
    enum UserError: Error, Equatable {
        /// User not found by username or ID
        case notFound(String)
        /// Password verification failed
        case incorrectPassword(user: String)
        /// Authentication token has expired
        case tokenExpired
        /// Password doesn't meet length requirement (8+ chars)
        case passwordNotLongEnough
        /// Username already taken during registration
        case userAlreadyExists(String)

        var message: String {
            switch self {
            case .incorrectPassword(let user):
                "Incorrect password for user '\(user)'"
            case .tokenExpired:
                "Authentication token has expired"
            case .passwordNotLongEnough:
                "Password must be 8 characters long"
            case .userAlreadyExists(let user):
                "A user with the username '\(user)' already exists"
            case .notFound(let user):
                "User '\(user)' not found"
            }
        }
    }
    let db: Connection
    let dateProvider: DateProviding
    let passwordHasher: PasswordHashing
    let logger = Logger(label: "UserController")

    init(
        db: Connection,
        dateProvider: DateProviding = CalendarDateProvider(calendar: .current),
        passwordHasher: PasswordHashing = ScryptPasswordHasher()
    ) {
        self.db = db
        self.dateProvider = dateProvider
        self.passwordHasher = passwordHasher
    }

    /// Initialize database tables for users and tokens
    /// Creates tables only if they don't already exist
    func createTables() throws {
        let userColumns = try db.schema.columnDefinitions(table: "user")
        if !userColumns.isEmpty {
            return
        }
        logger.info("No users table found in database; creating table...")
        try db.run(User.table.create { t in
            t.column(User.id, primaryKey: true)
            t.column(User.username, unique: true)
            t.column(User.passwordHash)
            t.column(User.salt)
        })

        try db.run(Token.table.create { t in
            t.column(Token.id, primaryKey: true)
            t.column(Token.userID, unique: true)
            t.column(Token.content, unique: true)
            t.column(Token.expires)
        })
    }

    func list() throws -> [User] {
        return try db.find()
    }

    func user(withID id: Int64) throws -> User {
        guard let user = try db.first(User.self, User.id == id) else {
            throw UserError.notFound("\(id)")
        }
        return user
    }

    func refreshExpiration(for token: inout Token) throws {
        let newExpiration = dateProvider.newExpirationDate
        let seconds = Int64(newExpiration.timeIntervalSince1970)
        let refreshToken = Token.table.filter(Token.content == token.content).update(
            Token.expires <- seconds)
        try db.run(refreshToken)
        token.expires = Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    func refreshOrCreateToken(userID: Int64) throws -> Token {
        if var token = try db.first(Token.self, Token.userID == Int64(userID)) {
            try refreshExpiration(for: &token)
            return token
        } else {
            let uuid = withUnsafeBytes(of: UUID().uuid, Array.init)
            var token = Token(
                id: 0,
                userID: userID,
                content: uuid.toHexString(),
                expires: dateProvider.newExpirationDate
            )
            let query = Token.table.insert(
                Token.userID <- userID,
                Token.content <- token.content,
                Token.expires <- Int64(token.expires.timeIntervalSince1970)
            )
            token.id = try db.run(query)
            return token
        }
    }

    /// Delete user and all associated data (cascading delete)
    /// Removes user record, tokens, locations, and push tokens
    /// - Parameter user: User to delete
    /// - Throws: Database errors if deletion fails
    func deleteUser(_ user: User) throws {
        // Delete the user record, all authorization tokens, all locations,
        // and all push tokens for this user.

        let deletions: [(Model.Type, Delete)] = [
            (User.self, User.find(User.id == user.id).delete()),
            (PushToken.self, PushToken.find(PushToken.userID == user.id).delete()),
            (Token.self, Token.find(Token.userID == user.id).delete()),
            (UserLocation.self, UserLocation.find(UserLocation.userID == user.id).delete())
        ]

        do {
            try db.transaction {
                for (type, deletion) in deletions {
                    logger.info("Deleting \(type.tableName) entries for '\(user.username)'")
                    try db.run(deletion)
                }
            }
            logger.info("Successfully deleted user '\(user.username)'")
        } catch {
            logger.info("Failed to delete user '\(user.username)': \(error)")
            throw error
        }
    }

    /// Authenticate user by token and refresh expiration
    /// - Parameter token: Hex-encoded authentication token
    /// - Returns: Valid token with refreshed expiration
    /// - Throws: UserError if token is invalid or expired
    func authenticate(token: String) throws -> Token {
        guard var token = try db.first(Token.self, Token.content == token) else {
            throw UserError.notFound(token)
        }
        if token.expires < dateProvider.now {
            throw UserError.tokenExpired
        }

        do {
            try refreshExpiration(for: &token)
        } catch {
            print("Failed to refresh token for user \(token.userID)")
        }

        return token
    }

    /// Authenticate user by credentials and return/create token
    /// - Parameters:
    ///   - username: User's username (will be normalized)
    ///   - password: Plain text password
    /// - Returns: Authentication token for API access
    /// - Throws: UserError for invalid credentials
    func authenticate(username: String, password: String) throws -> Token {
        let username = cleanUsername(username)
        guard let user = try db.first(User.self, User.username == username) else {
            throw UserError.notFound(username)
        }

        let digest = try passwordHasher.computePasswordHash(password: password, salt: user.salt)
        if digest != user.passwordHash {
            throw UserError.incorrectPassword(user: username)
        }
        return try refreshOrCreateToken(userID: user.id)
    }

    func revokeAuthentication(auth: ServerAuthentication) throws {
        try db.transaction {
            let token = Token.find(Token.content == auth.token.content)
            try db.run(token.delete())
            logger.info("Deleted push token for '\(auth.user.username)'")

            let notification = PushToken.find(
                PushToken.authToken == auth.token.content &&
                PushToken.userID == auth.user.id
            )
            let numberDeleted = try db.run(notification.delete())
            logger.info("Deleted \(numberDeleted) notification tokens for '\(auth.user.username)'")
        }
    }

    func cleanUsername(_ username: String) -> String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Create new user account with secure password storage
    /// - Parameters:
    ///   - username: Desired username (must be unique)
    ///   - password: Plain text password (8+ characters)
    ///   - location: Optional initial location
    /// - Returns: Tuple of created user and authentication token
    /// - Throws: UserError for validation failures or conflicts
    func create(
        username: String,
        password: String,
        location: Location? = nil
    ) throws -> (User, Token) {
        let username = cleanUsername(username)
        guard password.count >= 8 else {
            throw UserError.passwordNotLongEnough
        }
        let saltLength = Int.random(in: 12..<28)
        let salt = (0..<saltLength).map { _ in UInt8.random(in: 0x20...0x7E) }.toHexString()
        let digest = try passwordHasher.computePasswordHash(password: password, salt: salt)

        var id: Int64 = 0

        try db.transaction {
            guard try db.count(User.self, User.username == username) == 0 else {
                throw UserError.userAlreadyExists(username)
            }
            
            // Keep the user creation inside the transaction
            let insertion = User.table.insert(
                User.username <- username,
                User.passwordHash <- digest,
                User.salt <- salt)

            id = try db.run(insertion)

            if let location {
                let insertion = UserLocation.table.insert(
                    UserLocation.userID <- id,
                    UserLocation.latitude <- location.latitude,
                    UserLocation.longitude <- location.longitude
                )
                _ = try db.run(insertion)
            }
        }

        let newUser = User(
            id: id,
            username: username,
            passwordHash: digest,
            salt: salt)
        let newToken = try refreshOrCreateToken(userID: id)
        return (newUser, newToken)
    }
}

// MARK: - Route Registration
extension UserController {
    /// Register public routes that don't require authentication
    /// Routes: POST /auth (login), POST /users (registration)
    func addUnauthenticatedRoutes(to router: some RouterMethods, weather: WeatherController) {
        router
            .post("auth") { request, context in
                let authenticateUser = try await request.decode(
                    as: AuthenticateRequest.self,
                    context: context
                )
                do {
                    let token = try self.authenticate(
                        username: authenticateUser.username,
                        password: authenticateUser.password
                    )
                    let location = weather.location(forUserID: token.userID)?.location
                    return Authentication(
                        user: UserDTO(
                            id: token.userID,
                            username: authenticateUser.username,
                            location: location
                        ),
                        token: TokenDTO(userID: token.userID, token: token.content, expires: token.expires)
                    )
                } catch let error as UserError {
                    switch error {
                    case .incorrectPassword(let name):
                        throw HTTPError(.unauthorized, message: "Incorrect password for user '\(name)'")
                    case .notFound(let user):
                        throw HTTPError(.unauthorized, message: "Unknown user '\(user)'")
                    default:
                        throw error
                    }
                }
            }
            .post("users") { request, context in
                let createUser = try await request.decode(
                    as: CreateUserRequest.self,
                    context: context
                )
                do {
                    let (user, token) = try self.create(
                        username: createUser.username,
                        password: createUser.password,
                        location: createUser.location
                    )
                    return Authentication(user: user, token: token, location: nil)
                } catch let error as UserController.UserError {
                    throw HTTPError(.unauthorized, message: error.message)
                }
            }
    }

    /// Register protected routes requiring authentication
    /// Routes: PUT /auth (refresh), DELETE /auth (logout), DELETE /users (delete account)
    func addRoutes(to router: some RouterMethods<AuthenticatedRequestContext>, weather: WeatherController) {
        router
            .put("auth") { request, context in
                let auth = try context.requireIdentity()
                let location = weather.location(forUserID: auth.user.id)?.location
                return Authentication(user: auth.user, token: auth.token, location: location)
            }
            .delete("auth") { request, context in
                let auth = try context.requireIdentity()
                do {
                    try self.revokeAuthentication(auth: auth)
                    return Response(status: .ok)
                } catch {
                    throw HTTPError(.badRequest)
                }
            }
            .delete("users") { request, context in
                let auth = try context.requireIdentity()
                try self.deleteUser(auth.user)
                return Response(status: .ok)
            }
    }
}
