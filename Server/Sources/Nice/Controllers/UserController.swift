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
import JWTKit
import Logging

/// JWT payload for authentication tokens
/// Contains user ID and expiration claims
struct AuthPayload: JWTPayload {
    var sub: SubjectClaim  // userID as string
    var exp: ExpirationClaim  // 14 days from issuance
    var iat: IssuedAtClaim  // issued at timestamp

    func verify(using algorithm: some JWTAlgorithm) async throws {
        try exp.verifyNotExpired()
    }
}

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

extension Authentication {
    init(auth: ServerAuthentication, location: Location?) {
        self.init(
            user: UserDTO(id: auth.user.id, username: auth.user.username, location: location),
            token: TokenDTO(userID: auth.user.id, token: auth.tokenString)
        )
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
    let jwtKeys: JWTKeyCollection
    let logger = Logger(label: "UserController")

    init(
        db: Connection,
        dateProvider: DateProviding = CalendarDateProvider(calendar: .current),
        passwordHasher: PasswordHashing = ScryptPasswordHasher(),
        jwtSecretKey: String
    ) async {
        self.db = db
        self.dateProvider = dateProvider
        self.passwordHasher = passwordHasher
        self.jwtKeys = await JWTKeyCollection()
            .add(hmac: HMACKey(from: jwtSecretKey), digestAlgorithm: .sha256)
    }

    /// Initialize database tables for users
    /// Creates table only if it doesn't already exist
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

    /// Generate a new JWT token for the given user
    /// - Parameter userID: ID of the user to create token for
    /// - Returns: JWT string
    func createToken(userID: Int64) async throws -> String {
        let payload = AuthPayload(
            sub: SubjectClaim(value: "\(userID)"),
            exp: ExpirationClaim(value: dateProvider.newExpirationDate),
            iat: IssuedAtClaim(value: dateProvider.now)
        )
        return try await jwtKeys.sign(payload)
    }

    /// Delete user and all associated data (cascading delete)
    /// Removes user record, locations, and push tokens
    /// - Parameter user: User to delete
    /// - Throws: Database errors if deletion fails
    func deleteUser(_ user: User) throws {
        // Delete the user record, all locations, and all push tokens for this user.

        let deletions: [(Model.Type, Delete)] = [
            (User.self, User.find(User.id == user.id).delete()),
            (PushToken.self, PushToken.find(PushToken.userID == user.id).delete()),
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

    /// Authenticate user by verifying JWT token
    /// - Parameter token: JWT authentication token
    /// - Returns: User ID extracted from JWT
    /// - Throws: JWTError if token is invalid or expired
    func authenticate(token: String) async throws -> Int64 {
        let payload = try await jwtKeys.verify(token, as: AuthPayload.self)
        guard let userID = Int64(payload.sub.value) else {
            throw UserError.notFound(token)
        }
        return userID
    }

    /// Authenticate user by credentials and generate JWT token
    /// - Parameters:
    ///   - username: User's username (will be normalized)
    ///   - password: Plain text password
    /// - Returns: Tuple of (user, JWT string)
    /// - Throws: UserError for invalid credentials
    func authenticate(username: String, password: String) async throws -> (User, String) {
        let username = cleanUsername(username)
        guard let user = try db.first(User.self, User.username == username) else {
            throw UserError.notFound(username)
        }

        let digest = try passwordHasher.computePasswordHash(password: password, salt: user.salt)
        if digest != user.passwordHash {
            throw UserError.incorrectPassword(user: username)
        }
        let jwt = try await createToken(userID: user.id)
        return (user, jwt)
    }

    /// Revoke notification token for user (JWT tokens cannot be revoked)
    /// - Parameters:
    ///   - auth: Authenticated user context
    ///   - notificationToken: Specific notification token to delete
    func revokeNotificationToken(auth: ServerAuthentication, notificationToken: String) throws {
        let query = PushToken.find(
            PushToken.token == notificationToken &&
            PushToken.userID == auth.user.id
        )
        let numberDeleted = try db.run(query.delete())
        logger.info("Deleted \(numberDeleted) notification token(s) for '\(auth.user.username)'")
    }

    func cleanUsername(_ username: String) -> String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Create new user account with secure password storage
    /// - Parameters:
    ///   - username: Desired username (must be unique)
    ///   - password: Plain text password (8+ characters)
    ///   - location: Optional initial location
    /// - Returns: Tuple of (user, JWT string)
    /// - Throws: UserError for validation failures or conflicts
    func create(
        username: String,
        password: String,
        location: Location? = nil
    ) async throws -> (User, String) {
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
        let jwt = try await createToken(userID: id)
        return (newUser, jwt)
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
                    let (user, jwt) = try await self.authenticate(
                        username: authenticateUser.username,
                        password: authenticateUser.password
                    )
                    let location = weather.location(forUserID: user.id)?.location
                    return Authentication(
                        user: UserDTO(
                            id: user.id,
                            username: user.username,
                            location: location
                        ),
                        token: TokenDTO(userID: user.id, token: jwt)
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
                    let (user, jwt) = try await self.create(
                        username: createUser.username,
                        password: createUser.password,
                        location: createUser.location
                    )
                    return Authentication(
                        user: UserDTO(id: user.id, username: user.username, location: nil),
                        token: TokenDTO(userID: user.id, token: jwt)
                    )
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
                return Authentication(auth: auth, location: location)
            }
            .delete("auth") { request, context in
                let auth = try context.requireIdentity()
                let logoutRequest = try await request.decode(as: LogoutRequest.self, context: context)
                do {
                    try self.revokeNotificationToken(auth: auth, notificationToken: logoutRequest.notificationToken)
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
