//
//  UserControllerTests.swift
//  Nice
//
//  Created by Harlan Haskins on 5/4/25.
//

import NiceTypes
@testable import Nice
import Testing
import SQLite
import Foundation

@Suite
struct UserControllerTests {
    // Helper function to create a test controller with SHA256 password hasher
    func makeTestController(
        db: Connection = try! Connection(.inMemory),
        dateProvider: DateProviding = MockDateProvider(),
        useScrypt: Bool = false
    ) async throws -> UserController {
        let controller = await UserController(
            db: db,
            dateProvider: dateProvider,
            passwordHasher: SHA256PasswordHasher(),
            jwtSecretKey: "test-secret-key-for-jwt-signing"
        )
        try controller.createTables()
        return controller
    }
    
    @Test
    func testUserCreation() async throws {
        let db = try Connection(.inMemory)
        let controller = try await makeTestController(db: db)

        let username = "homestar"
        let password = "itsdotcom"

        let (user, _) = try await controller.create(username: username, password: password, location: nil)

        #expect(user.username == username)
        #expect(user.passwordHash.isEmpty == false)
        #expect(user.salt.isEmpty == false)
    }
    
    @Test
    func testPasswordTooShort() async throws {
        let db = try Connection(.inMemory)
        let controller = try await makeTestController(db: db)

        let username = "strongbad"
        let shortPassword = "crap"

        await #expect(throws: UserController.UserError.passwordNotLongEnough) {
            _ = try await controller.create(username: username, password: shortPassword)
        }
    }

    @Test
    func testUsernamePasswordAuthentication() async throws {
        let db = try Connection(.inMemory)
        let controller = try await makeTestController(db: db)

        let username = "strongsad"
        let password = "imsadthatimflying123"

        _ = try await controller.create(username: username, password: password)

        let (user, jwt) = try await controller.authenticate(username: username, password: password)

        #expect(jwt.isEmpty == false)
        #expect(user.id > 0)
    }

    @Test
    func testIncorrectPasswordAuthentication() async throws {
        let db = try Connection(.inMemory)
        let controller = try await makeTestController(db: db)

        let username = "theCheat"
        let password = "LightSwitchRave2023"
        let wrongPassword = "MehMehMehMehMehMehMeh"

        _ = try await controller.create(username: username, password: password)

        await #expect(throws: UserController.UserError.incorrectPassword(user: username.lowercased())) {
            _ = try await controller.authenticate(username: username, password: wrongPassword)
        }
    }

    @Test
    func testNonexistentUserAuthentication() async throws {
        let db = try Connection(.inMemory)
        let controller = try await makeTestController(db: db)

        let username = "coachZ"
        let password = "GreatJorb123"

        await #expect(throws: UserController.UserError.notFound(username.lowercased())) {
            _ = try await controller.authenticate(username: username, password: password)
        }
    }

    @Test
    func testTokenAuthentication() async throws {
        let db = try Connection(.inMemory)
        let controller = try await makeTestController(db: db)

        let username = "marzipan"
        let password = "CoolTapes4Ever"

        let (_, _) = try await controller.create(username: username, password: password)
        let (initialUser, initialJwt) = try await controller.authenticate(username: username, password: password)

        // Verify the token by extracting the payload (JWT is stateless)
        let verifiedUserID = try await controller.authenticate(token: initialJwt)

        // JWT verification returns the same token data
        #expect(verifiedUserID == initialUser.id)
    }
    
    @Test
    func testTokenExpiration() async throws {
        let db = try Connection(.inMemory)
        let dateProvider = MockDateProvider()
        let controller = try await makeTestController(db: db, dateProvider: dateProvider)

        let username = "kingOfTown"
        let password = "ILikeTastyFood999"

        // Set initial date
        let baseDate = Date(timeIntervalSince1970: 946684800) // January 1, 2000
        dateProvider.now = baseDate

        _ = try await controller.create(username: username, password: password)
        let (_, jwt) = try await controller.authenticate(username: username, password: password)

        // Advance time to after the token expiration (14 days + 1 hour)
        dateProvider.now = dateProvider.now.addingTimeInterval(14 * 24 * 3600 + 3600)

        // Now the token should be expired (JWT verification will fail)
        await #expect(throws: (any Error).self) {
            _ = try await controller.authenticate(token: jwt)
        }
    }

    @Test
    func testNonexistentTokenAuthentication() async throws {
        let db = try Connection(.inMemory)
        let controller = try await makeTestController(db: db)

        let fakeToken = "fakeTokenThatDoesntExist123456"

        // Invalid JWT will throw during verification
        await #expect(throws: (any Error).self) {
            _ = try await controller.authenticate(token: fakeToken)
        }
    }
    
    @Test
    func testNewTokenOnPasswordAuth() async throws {
        let db = try Connection(.inMemory)
        let dateProvider = MockDateProvider()
        let controller = try await makeTestController(db: db, dateProvider: dateProvider)

        let username = "poopsmith"
        let password = "the-poopsmith-has-taken-a-vow-of-silence"

        let baseDate = Date(timeIntervalSince1970: 946684800) // January 1, 2000
        dateProvider.now = baseDate

        _ = try await controller.create(username: username, password: password)
        let (_, initialJwt) = try await controller.authenticate(username: username, password: password)

        // Advance time
        dateProvider.now = baseDate.addingTimeInterval(3600) // Advance 1 hour

        // Re-authenticating creates a NEW JWT (stateless, not refreshed)
        let (_, newJwt) = try await controller.authenticate(username: username, password: password)

        #expect(newJwt != initialJwt) // Different JWT (new signature with new iat claim)
    }
    
    @Test
    func testTokenCreation() async throws {
        let db = try Connection(.inMemory)
        let dateProvider = MockDateProvider()
        let controller = try await makeTestController(db: db, dateProvider: dateProvider)

        let baseDate = Date(timeIntervalSince1970: 946684800) // January 1, 2000
        dateProvider.now = baseDate

        let username = "homsar"
        let password = "IWasRaisedByACupOfCoffee!!"

        _ = try await controller.create(username: username, password: password)
        let (_, jwt) = try await controller.authenticate(username: username, password: password)

        // JWT token should be a non-empty string
        #expect(!jwt.isEmpty)
    }
    
    @Test
    func testPasswordHasherUsed() async throws {
        // Create a predictable hasher for testing
        struct PredictableHasher: PasswordHashing {
            func computePasswordHash(password: String, salt: String) throws -> String {
                return "predictable-hash-\(password)-\(salt)"
            }
        }

        let db = try Connection(.inMemory)
        let controller = await UserController(
            db: db,
            passwordHasher: PredictableHasher(),
            jwtSecretKey: "test-secret-key"
        )
        try controller.createTables()

        let username = "bubs"
        let password = "concessionStand123"

        let (user, jwt) = try await controller.create(username: username, password: password)
        #expect(!jwt.isEmpty)

        // Verify the hasher was used
        #expect(user.passwordHash.starts(with: "predictable-hash-"))
        #expect(user.passwordHash.contains(password))
        #expect(user.passwordHash.contains(user.salt))

        // Verify authentication works with our predictable hasher
        let (_, reauthedJwt) = try await controller.authenticate(username: username, password: password)
        #expect(!reauthedJwt.isEmpty)
    }

    @Test func testUsingScryptHasher() async throws {
        let db = try Connection(.inMemory)
        let controller = await UserController(db: db, jwtSecretKey: "test-secret-key")
        try controller.createTables()

        let username = "marshie"
        let password = "stackemtotheheavens"

        let (user, _) = try await controller.create(username: username, password: password)

        // Verify the scrypt hasher was used (64 byte password, 128 hex chars, password does not contains the input)
        #expect(!user.passwordHash.contains(password))
        #expect(user.passwordHash.count == 128)
        #expect(user.passwordHash.allSatisfy { $0.isHexDigit })
        #expect(user.salt.allSatisfy { $0.isHexDigit })
    }

    @Test
    func testCannotCreateDuplicateUser() async throws {
        let db = try Connection(.inMemory)
        let controller = try await makeTestController(db: db)

        // Create first user
        let username = "strongbad"
        let password = "DELETED12345"

        let (user, _) = try await controller.create(username: username, password: password)
        #expect(user.username == username)

        // Attempt to create a second user with the same username
        await #expect(throws: UserController.UserError.userAlreadyExists(username)) {
            _ = try await controller.create(username: username, password: "differentpassword12345")
        }
    }

    @Test
    func testListReturnsAllUsers() async throws {
        let db = try Connection(.inMemory)
        let controller = try await makeTestController(db: db)

        // Create a few users
        let (user1, _) = try await controller.create(username: "senor_cardgage", password: "Excardon me")
        let (user2, _) = try await controller.create(username: "coach_z", password: "jorearbs12345")
        let (user3, _) = try await controller.create(username: "bubs", password: "itsaconcessionstand")

        // List all users
        let users = try controller.list()

        // Verify the correct number of users
        #expect(users.count == 3)

        // Verify the users are present in the list
        #expect(users.contains { $0.id == user1.id && $0.username == "senor_cardgage" })
        #expect(users.contains { $0.id == user2.id && $0.username == "coach_z" })
        #expect(users.contains { $0.id == user3.id && $0.username == "bubs" })
    }

    @Test
    func testGetUserByID() async throws {
        let db = try Connection(.inMemory)
        let controller = await UserController(db: db, passwordHasher: SHA256PasswordHasher(), jwtSecretKey: "test-secret-key")
        try controller.createTables()

        // Create a user
        let (createdUser, _) = try await controller.create(username: "homestar", password: "RunnerPassword123", location: nil)

        // Test getting user by ID
        let user = try controller.user(withID: createdUser.id)
        #expect(user.id == createdUser.id)
        #expect(user.username == "homestar")
    }

    @Test
    func testGetUserByIDNotFound() async throws {
        let db = try Connection(.inMemory)
        let controller = await UserController(db: db, passwordHasher: SHA256PasswordHasher(), jwtSecretKey: "test-secret-key")
        try controller.createTables()

        // Test getting non-existent user by ID
        #expect(throws: UserController.UserError.notFound("999")) {
            _ = try controller.user(withID: 999)
        }
    }
}
