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

struct User: Sendable, Codable {
    static let table = Table("user")
    static let id = Expression<Int64>("id")
    static let username = Expression<String>("username")
    static let passwordHash = Expression<String>("passwordHash")
    static let salt = Expression<String>("salt")
    static let latitude = Expression<Double?>("latitude")
    static let longitude = Expression<Double?>("longitude")

    let id: Int
    var username: String
    var passwordHash: String
    var salt: String
    var latitude: Double?
    var longitude: Double?

    var location: Location? {
        guard let latitude, let longitude else {
            return nil
        }
        return Location(latitude: latitude, longitude: longitude)
    }

    var dto: UserDTO {
        UserDTO(id: id, username: username)
    }
}

extension User {
    init(row: Row) {
        id = Int(row[User.id])
        username = row[User.username]
        passwordHash = row[User.passwordHash]
        salt = row[User.salt]
        latitude = row[User.latitude]
        longitude = row[User.longitude]
    }
}

struct Token: Sendable, Codable {
    static let table = Table("token")
    static let id = Expression<Int64>("id")
    static let userID = Expression<Int64>("userID")
    static let content = Expression<String>("content")
    static let expires = Expression<Int64>("expires")

    var id: Int
    var userID: Int
    var content: String
    var expires: Date

    var dto: TokenDTO {
        TokenDTO(userID: userID, token: content, expires: expires)
    }
}

extension Authentication {
    init(user: User, token: Token) {
        self.init(user: user.dto, token: token.dto)
    }
}

extension Token {
    init(row: Row) {
        id = Int(row[Token.id])
        userID = Int(row[Token.userID])
        content = row[Token.content]
        expires = Date(timeIntervalSince1970: TimeInterval(row[Token.expires]))
    }
}

protocol DateProviding: Sendable {
    var now: Date { get }
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

protocol PasswordHashing: Sendable {
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

final class UserController: Sendable {
    enum UserError: Error, Equatable {
        case notFound(String)
        case incorrectPassword(user: String)
        case tokenExpired
        case passwordNotLongEnough
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

    init(
        db: Connection,
        dateProvider: DateProviding = CalendarDateProvider(calendar: .current),
        passwordHasher: PasswordHashing = ScryptPasswordHasher()
    ) {
        self.db = db
        self.dateProvider = dateProvider
        self.passwordHasher = passwordHasher
    }

    func createTables() throws {
        let userColumns = try db.schema.columnDefinitions(table: "user")
        if !userColumns.isEmpty {
            return
        }
        print("No users table found in database; creating table...")
        try db.run(User.table.create { t in
            t.column(User.id, primaryKey: true)
            t.column(User.username, unique: true)
            t.column(User.passwordHash)
            t.column(User.salt)
            t.column(User.latitude)
            t.column(User.longitude)
        })

        try db.run(Token.table.create { t in
            t.column(Token.id, primaryKey: true)
            t.column(Token.userID, unique: true)
            t.column(Token.content, unique: true)
            t.column(Token.expires)
        })
    }

    func list() throws -> [User] {
        let results = User.table.select(*)
        var users: [User] = []
        for row in try db.prepare(results) {
            users.append(User(row: row))
        }
        return users
    }

    func user(withID id: Int) throws -> User {
        let query = User.table.select(*).filter(User.id == Int64(id))
        guard let row = try db.prepare(query).first(where: { _ in true }) else {
            throw UserError.notFound("\(id)")
        }
        return User(row: row)
    }

    func refreshExpiration(for token: inout Token) throws {
        let newExpiration = dateProvider.newExpirationDate
        let seconds = Int64(newExpiration.timeIntervalSince1970)
        let refreshToken = Token.table.filter(Token.content == token.content).update(
            Token.expires <- seconds)
        try db.run(refreshToken)
        token.expires = Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    func refreshOrCreateToken(userID: Int) throws -> Token {
        let query = Token.table.select(*).filter(Token.userID == Int64(userID))

        if let row = try db.prepare(query).first(where: { _ in true }) {
            var token = Token(row: row)
            try refreshExpiration(for: &token)
            return token
        } else {
            let uuid = withUnsafeBytes(of: UUID().uuid, Array.init)
            var token = Token(
                id: 0,
                userID: Int(userID),
                content: uuid.toHexString(),
                expires: dateProvider.newExpirationDate
            )
            let query = Token.table.insert(
                Token.userID <- Int64(userID),
                Token.content <- token.content,
                Token.expires <- Int64(token.expires.timeIntervalSince1970)
            )
            token.id = Int(try db.run(query))
            return token
        }
    }

    func authenticate(token: String) throws -> Token {
        let query = Token.table.select(*).filter(Token.content == token)
        guard let row = try db.prepare(query).first(where: { _ in true }) else {
            throw UserError.notFound(token)
        }
        var token = Token(row: row)
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

    func authenticate(username: String, password: String) throws -> Token {
        let findUsers = User.table.select(*).filter(User.username == username)
        guard let user = try db.prepare(findUsers).first(where: { _ in true }) else {
            throw UserError.notFound(username)
        }

        let id = user[User.id]
        let hash = user[User.passwordHash]
        let salt = user[User.salt]

        let digest = try passwordHasher.computePasswordHash(password: password, salt: salt)
        if digest != hash {
            throw UserError.incorrectPassword(user: username)
        }
        return try refreshOrCreateToken(userID: Int(id))
    }

    func updateLocation(_ location: Location, forUserID userID: Int) throws {
        let query = User.table
            .filter(User.id == Int64(userID))
            .update(
                User.latitude <- location.latitude,
                User.longitude <- location.longitude
            )
        try db.run(query)
    }

    func create(
        username: String,
        password: String,
        location: Location? = nil
    ) throws -> (User, Token) {
        guard password.count >= 8 else {
            throw UserError.passwordNotLongEnough
        }
        let saltLength = Int.random(in: 12..<28)
        let salt = (0..<saltLength).map { _ in UInt8.random(in: 0x20...0x7E) }.toHexString()
        let digest = try passwordHasher.computePasswordHash(password: password, salt: salt)

        var id: Int64 = 0

        try db.transaction {
            let numberOfUsers = User.table.select(*).filter(User.username == username).count
            guard try db.scalar(numberOfUsers) == 0 else {
                throw UserError.userAlreadyExists(username)
            }
            
            // Keep the user creation inside the transaction
            let insertion = User.table.insert(
                User.username <- username,
                User.passwordHash <- digest,
                User.salt <- salt,
                User.latitude <- location?.latitude,
                User.longitude <- location?.longitude)

            id = try db.run(insertion)
        }

        let newUser = User(
            id: Int(id),
            username: username,
            passwordHash: digest,
            salt: salt,
            latitude: location?.latitude,
            longitude: location?.longitude)
        let newToken = try refreshOrCreateToken(userID: Int(id))
        return (newUser, newToken)
    }
}

extension UserController {
    func addUnauthenticatedRoutes(to router: some RouterMethods) {
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
                    return Authentication(
                        user: UserDTO(id: token.userID, username: authenticateUser.username),
                        token: TokenDTO(userID: token.userID, token: token.content, expires: token.expires)
                    )
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
                    return Authentication(user: user, token: token)
                } catch let error as UserController.UserError {
                    throw HTTPError(.unauthorized, message: error.message)
                }
            }
    }

    func addRoutes(to router: some RouterMethods<AuthenticatedRequestContext>) {
        router
            .put("auth") { request, context in
                let auth = try context.requireIdentity()
                return Authentication(user: auth.user, token: auth.token)
            }
            .put("location") { request, context in
                let auth = try context.requireIdentity()
                let location = try await request.decode(
                    as: Location.self,
                    context: context
                )
                try self.updateLocation(location, forUserID: auth.user.id)
                return Response(status: .ok)
            }
    }
}
