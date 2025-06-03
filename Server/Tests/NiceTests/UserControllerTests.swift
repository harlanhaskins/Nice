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
    ) throws -> UserController {
        let controller = UserController(
            db: db,
            dateProvider: dateProvider,
            passwordHasher: SHA256PasswordHasher()
        )
        try controller.createTables()
        return controller
    }
    
    @Test
    func testUserCreation() throws {
        let db = try Connection(.inMemory)
        let controller = try makeTestController(db: db)

        let username = "homestar"
        let password = "itsdotcom"

        let (user, _) = try controller.create(username: username, password: password, location: nil)

        #expect(user.username == username)
        #expect(user.passwordHash.isEmpty == false)
        #expect(user.salt.isEmpty == false)
    }
    
    @Test
    func testPasswordTooShort() throws {
        let db = try Connection(.inMemory)
        let controller = try makeTestController(db: db)
        
        let username = "strongbad"
        let shortPassword = "crap"

        #expect(throws: UserController.UserError.passwordNotLongEnough) {
            _ = try controller.create(username: username, password: shortPassword)
        }
    }
    
    @Test
    func testUsernamePasswordAuthentication() throws {
        let db = try Connection(.inMemory)
        let controller = try makeTestController(db: db)
        
        let username = "strongsad"
        let password = "imsadthatimflying123"

        _ = try controller.create(username: username, password: password)
        
        let token = try controller.authenticate(username: username, password: password)
        
        #expect(token.content.isEmpty == false)
        #expect(token.expires > Date.now)
        #expect(token.userID > 0)
    }
    
    @Test
    func testIncorrectPasswordAuthentication() throws {
        let db = try Connection(.inMemory)
        let controller = try makeTestController(db: db)
        
        let username = "theCheat"
        let password = "LightSwitchRave2023"
        let wrongPassword = "MehMehMehMehMehMehMeh"
        
        _ = try controller.create(username: username, password: password)
        
        #expect(throws: UserController.UserError.incorrectPassword(user: username.lowercased())) {
            _ = try controller.authenticate(username: username, password: wrongPassword)
        }
    }
    
    @Test
    func testNonexistentUserAuthentication() throws {
        let db = try Connection(.inMemory)
        let controller = try makeTestController(db: db)
        
        let username = "coachZ"
        let password = "GreatJorb123"
        
        #expect(throws: UserController.UserError.notFound(username.lowercased())) {
            _ = try controller.authenticate(username: username, password: password)
        }
    }
    
    @Test
    func testTokenAuthentication() throws {
        let db = try Connection(.inMemory)
        let controller = try makeTestController(db: db)
        
        let username = "marzipan"
        let password = "CoolTapes4Ever"
        
        _ = try controller.create(username: username, password: password)
        let initialToken = try controller.authenticate(username: username, password: password)
        
        let refreshedToken = try controller.authenticate(token: initialToken.content)
        
        #expect(refreshedToken.content == initialToken.content)
        #expect(refreshedToken.userID == initialToken.userID)
    }
    
    @Test
    func testTokenExpiration() throws {
        let db = try Connection(.inMemory)
        let dateProvider = MockDateProvider()
        let controller = try makeTestController(db: db, dateProvider: dateProvider)
        
        let username = "kingOfTown"
        let password = "ILikeTastyFood999"
        
        // Set initial date
        let baseDate = Date(timeIntervalSince1970: 946684800) // January 1, 2000
        dateProvider.now = baseDate
        
        _ = try controller.create(username: username, password: password)
        let token = try controller.authenticate(username: username, password: password)
        
        // Record original expiration date (should be baseDate + 14 days)
        let originalExpiration = token.expires
        
        // Advance time to after the token expiration
        dateProvider.now = originalExpiration.addingTimeInterval(3600) // 1 hour after expiration
        
        // Now the token should be expired
        #expect(throws: UserController.UserError.tokenExpired) {
            _ = try controller.authenticate(token: token.content)
        }
    }
    
    @Test
    func testNonexistentTokenAuthentication() throws {
        let db = try Connection(.inMemory)
        let controller = try makeTestController(db: db)
        
        let fakeToken = "fakeTokenThatDoesntExist123456"

        #expect(throws: UserController.UserError.notFound(fakeToken)) {
            _ = try controller.authenticate(token: fakeToken)
        }
    }
    
    @Test
    func testTokenRefreshOnUsernamePasswordAuth() throws {
        let db = try Connection(.inMemory)
        let dateProvider = MockDateProvider()
        let controller = try makeTestController(db: db, dateProvider: dateProvider)
        
        let username = "poopsmith"
        let password = "the-poopsmith-has-taken-a-vow-of-silence"

        let baseDate = Date(timeIntervalSince1970: 946684800) // January 1, 2000
        dateProvider.now = baseDate
        
        _ = try controller.create(username: username, password: password)
        let initialToken = try controller.authenticate(username: username, password: password)
        let originalExpiration = initialToken.expires
        
        // Advance time instead of waiting
        dateProvider.now = baseDate.addingTimeInterval(3600) // Advance 1 hour
        
        let refreshedToken = try controller.authenticate(username: username, password: password)
        
        #expect(refreshedToken.content == initialToken.content)
        #expect(refreshedToken.expires > originalExpiration)
    }
    
    @Test
    func testTokenRefreshOnTokenAuth() throws {
        let db = try Connection(.inMemory)
        let dateProvider = MockDateProvider()
        let controller = try makeTestController(db: db, dateProvider: dateProvider)
        
        let username = "bubbs"
        let password = "CheckEmOut123!"

        let baseDate = Date(timeIntervalSince1970: 946684800) // January 1, 2000
        dateProvider.now = baseDate
        
        _ = try controller.create(username: username, password: password)
        let initialToken = try controller.authenticate(username: username, password: password)
        let originalExpiration = initialToken.expires
        
        // Advance time instead of waiting
        dateProvider.now = baseDate.addingTimeInterval(3600) // Advance 1 hour

        let refreshedToken = try controller.authenticate(token: initialToken.content)
        
        #expect(refreshedToken.content == initialToken.content)
        #expect(refreshedToken.expires > originalExpiration)
    }
    
    @Test
    func testDateProviderAffectsTokenExpiration() throws {
        let db = try Connection(.inMemory)
        let dateProvider = MockDateProvider()
        let controller = try makeTestController(db: db, dateProvider: dateProvider)

        let baseDate = Date(timeIntervalSince1970: 946684800) // January 1, 2000
        dateProvider.now = baseDate

        let username = "homsar"
        let password = "IWasRaisedByACupOfCoffee!!"
        
        _ = try controller.create(username: username, password: password)
        let token = try controller.authenticate(username: username, password: password)
        
        // Should be valid at current time
        #expect(token.expires > dateProvider.now)
        
        // Advance time to just before expiration
        dateProvider.advanceTime(by: (14 * 24 * 3600 - 10)) // 10 seconds before expiration

        // Token should still be valid
        let stillValidToken = try controller.authenticate(token: token.content)
        #expect(stillValidToken.content == token.content)
        
        // Advance time past the new expiration
        dateProvider.advanceTime(by: (14 * 24 * 3600 + 10)) // 10 seconds after expiration

        // Should be expired.
        #expect(stillValidToken.expires < dateProvider.now)

        // Expiration should reflect in the database
        #expect(throws: UserController.UserError.tokenExpired) {
            _ = try controller.authenticate(token: token.content)
        }
    }
    
    @Test
    func testTokenRefreshUpdatesDatabaseExpiration() throws {
        let db = try Connection(.inMemory)
        let dateProvider = MockDateProvider()
        let controller = try makeTestController(db: db, dateProvider: dateProvider)
        
        let username = "thepaper"
        let password = "preeeeowwwwwwww"

        // Set initial date
        let baseDate = Date(timeIntervalSince1970: 946684800) // January 1, 2000
        dateProvider.now = baseDate
        
        _ = try controller.create(username: username, password: password)
        let token = try controller.authenticate(username: username, password: password)

        // Advance time so the new expiration is later
        dateProvider.advanceTime(by: 10)

        // Authenticate with token to trigger refresh
        let refreshedToken = try controller.authenticate(token: token.content)
        
        // Now let's verify that the database was actually updated with the new expiration
        // by reading the token record directly from the database
        let query = Token.table.select(Token.expires).filter(Token.content == token.content)
        let row = try db.prepare(query).first(where: { _ in true })!
        let databaseExpiration = Date(timeIntervalSince1970: TimeInterval(row[Token.expires]))
        
        // The database expiration should match the memory token expiration
        #expect(databaseExpiration == refreshedToken.expires)
        
        // And the new expiration should be later than the original token expiration
        #expect(databaseExpiration > token.expires)
    }
    
    @Test
    func testPasswordHasherUsed() throws {
        // Create a predictable hasher for testing
        struct PredictableHasher: PasswordHashing {
            func computePasswordHash(password: String, salt: String) throws -> String {
                return "predictable-hash-\(password)-\(salt)"
            }
        }
        
        let db = try Connection(.inMemory)
        let controller = UserController(
            db: db,
            passwordHasher: PredictableHasher()
        )
        try controller.createTables()
        
        let username = "bubs"
        let password = "concessionStand123"
        
        let (user, token) = try controller.create(username: username, password: password)
        #expect(!token.content.isEmpty)

        // Verify the hasher was used
        #expect(user.passwordHash.starts(with: "predictable-hash-"))
        #expect(user.passwordHash.contains(password))
        #expect(user.passwordHash.contains(user.salt))
        
        // Verify authentication works with our predictable hasher
        let reauthedToken = try controller.authenticate(username: username, password: password)
        #expect(!reauthedToken.content.isEmpty)
    }

    @Test func testUsingScryptHasher() throws {
        let db = try Connection(.inMemory)
        let controller = UserController(db: db)
        try controller.createTables()

        let username = "marshie"
        let password = "stackemtotheheavens"

        let (user, _) = try controller.create(username: username, password: password)

        // Verify the scrypt hasher was used (64 byte password, 128 hex chars, password does not contains the input)
        #expect(!user.passwordHash.contains(password))
        #expect(user.passwordHash.count == 128)
        #expect(user.passwordHash.allSatisfy { $0.isHexDigit })
        #expect(user.salt.allSatisfy { $0.isHexDigit })
    }

    @Test
    func testCannotCreateDuplicateUser() throws {
        let db = try Connection(.inMemory)
        let controller = try makeTestController(db: db)

        // Create first user
        let username = "strongbad"
        let password = "DELETED12345"

        let (user, _) = try controller.create(username: username, password: password)
        #expect(user.username == username)

        // Attempt to create a second user with the same username
        #expect(throws: UserController.UserError.userAlreadyExists(username)) {
            _ = try controller.create(username: username, password: "differentpassword12345")
        }
    }

    @Test
    func testListReturnsAllUsers() throws {
        let db = try Connection(.inMemory)
        let controller = try makeTestController(db: db)

        // Create a few users
        let (user1, _) = try controller.create(username: "senor_cardgage", password: "Excardon me")
        let (user2, _) = try controller.create(username: "coach_z", password: "jorearbs12345")
        let (user3, _) = try controller.create(username: "bubs", password: "itsaconcessionstand")

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
    func testGetUserByID() throws {
        let db = try Connection(.inMemory)
        let controller = UserController(db: db, passwordHasher: SHA256PasswordHasher())
        try controller.createTables()

        // Create a user
        let (createdUser, _) = try controller.create(username: "homestar", password: "RunnerPassword123", location: nil)

        // Test getting user by ID
        let user = try controller.user(withID: createdUser.id)
        #expect(user.id == createdUser.id)
        #expect(user.username == "homestar")
    }

    @Test
    func testGetUserByIDNotFound() throws {
        let db = try Connection(.inMemory)
        let controller = UserController(db: db, passwordHasher: SHA256PasswordHasher())
        try controller.createTables()

        // Test getting non-existent user by ID
        #expect(throws: UserController.UserError.notFound("999")) {
            _ = try controller.user(withID: 999)
        }
    }

    @Test
    func testRefreshExpirationOnlyUpdatesSpecificToken() throws {
        let db = try Connection(.inMemory)
        let dateProvider = MockDateProvider()

        // Create controller with the mock date provider
        let controller = UserController(
            db: db,
            dateProvider: dateProvider,
            passwordHasher: SHA256PasswordHasher()
        )
        try controller.createTables()

        // Set initial date
        let baseDate = Date(timeIntervalSince1970: 946684800) // January 1, 2000
        dateProvider.now = baseDate

        // Create two users with tokens
        let (_, token1) = try controller.create(username: "user1", password: "password12345")
        let (_, token2) = try controller.create(username: "user2", password: "anotherpassword12345")

        // Record initial expiration times
        let initialExp1 = token1.expires
        let initialExp2 = token2.expires

        // Advance time so the next expiration date will be different
        dateProvider.advanceTime(by: 3600) // 1 hour

        // Refresh only token1
        _ = try controller.authenticate(token: token1.content)

        // Get the current expiration values from the database
        let queryToken1 = Token.table.select(Token.expires).filter(Token.content == token1.content)
        let queryToken2 = Token.table.select(Token.expires).filter(Token.content == token2.content)

        let row1 = try db.prepare(queryToken1).first(where: { _ in true })!
        let row2 = try db.prepare(queryToken2).first(where: { _ in true })!

        let currentExp1 = Date(timeIntervalSince1970: TimeInterval(row1[Token.expires]))
        let currentExp2 = Date(timeIntervalSince1970: TimeInterval(row2[Token.expires]))

        // Token 1 should be updated, token 2 should not be
        #expect(currentExp1 > initialExp1)
        #expect(currentExp2 == initialExp2)
    }

    @Test
    func testTokenWithoutIDHandling() throws {
        let db = try Connection(.inMemory)
        let dateProvider = MockDateProvider()
        let controller = UserController(
            db: db,
            dateProvider: dateProvider,
            passwordHasher: SHA256PasswordHasher()
        )
        try controller.createTables()

        // Create a token that's not in the database (id: 0)
        var token = Token(
            id: 0,
            userID: 1,
            content: "not-in-database",
            expires: dateProvider.now
        )

        // This should not throw but might not update anything
        try controller.refreshExpiration(for: &token)

        // Verify token expiration was still updated in memory
        #expect(token.expires > dateProvider.now)
    }
}
