//
//  NotificationControllerTests.swift
//  Nice
//
//  Created by Harlan Haskins on 5/18/25.
//

import NiceTypes
@testable import Nice
import Testing
import SQLite
import Foundation

@Suite
struct NotificationControllerTests {
    struct TestContext {
        let db: Connection
        let users: UserController
        let notifications: NotificationController
        let dateProvider: MockDateProvider

        static func create() async throws -> TestContext {
            let db = try Connection(.inMemory)
            let dateProvider = MockDateProvider()
            let users = await UserController(
                db: db,
                dateProvider: dateProvider,
                passwordHasher: SHA256PasswordHasher(),
                jwtSecretKey: "test-key"
            )
            try users.createTables()

            let notifications = NotificationController(
                db: db,
                users: users,
                apnsNotifier: MockNotifier(),
                webPushNotifier: MockWebPushNotifier(),
                dateProvider: dateProvider
            )
            try notifications.createTables()

            return TestContext(
                db: db,
                users: users,
                notifications: notifications,
                dateProvider: dateProvider
            )
        }
    }

    @Test
    func registerPushTokenCreatesNewToken() async throws {
        let ctx = try await TestContext.create()

        let (user, token) = try await ctx.users.create(username: "testuser", password: "password123")
        let auth = ServerAuthentication(user: user, tokenString: token)

        let pushTokenDTO = PushTokenDTO(token: "device-token-123", deviceType: .iOS)
        try ctx.notifications.registerPushToken(pushTokenDTO, for: auth)

        // Verify token was created
        let tokens = try ctx.db.find(PushToken.self, PushToken.userID == user.id)
        #expect(tokens.count == 1)

        let storedToken = try #require(tokens.first)
        #expect(storedToken.token == "device-token-123")
        #expect(storedToken.type == "iOS")
        #expect(storedToken.authToken == token)
        #expect(storedToken.createdAt == Int64(ctx.dateProvider.now.timeIntervalSince1970))
    }

    @Test
    func registerPushTokenUpdatesExistingToken() async throws {
        let ctx = try await TestContext.create()

        let (user, token1) = try await ctx.users.create(username: "testuser", password: "password123")
        let auth1 = ServerAuthentication(user: user, tokenString: token1)

        let pushTokenDTO = PushTokenDTO(token: "device-token-123", deviceType: .iOS)

        // Register token with first auth token
        try ctx.notifications.registerPushToken(pushTokenDTO, for: auth1)

        // Get the initial token
        let initialTokens = try ctx.db.find(PushToken.self, PushToken.userID == user.id)
        #expect(initialTokens.count == 1)
        let initialToken = try #require(initialTokens.first)
        let initialCreatedAt = initialToken.createdAt

        // Advance time
        ctx.dateProvider.advanceTime(by: 3600)

        // Create a new auth token (simulating user getting a new JWT)
        let token2 = try await ctx.users.createToken(userID: user.id)
        let auth2 = ServerAuthentication(user: user, tokenString: token2)

        // Register same device token with new auth token
        try ctx.notifications.registerPushToken(pushTokenDTO, for: auth2)

        // Verify still only one token, but updated
        let updatedTokens = try ctx.db.find(PushToken.self, PushToken.userID == user.id)
        #expect(updatedTokens.count == 1)

        let updatedToken = try #require(updatedTokens.first)
        #expect(updatedToken.id == initialToken.id) // Same record
        #expect(updatedToken.token == "device-token-123")
        #expect(updatedToken.authToken == token2) // Updated auth token
        #expect(updatedToken.createdAt > initialCreatedAt) // Updated timestamp
        #expect(updatedToken.createdAt == Int64(ctx.dateProvider.now.timeIntervalSince1970))
    }

    @Test
    func registerPushTokenSkipsUpdateIfAuthTokenMatches() async throws {
        let ctx = try await TestContext.create()

        let (user, token) = try await ctx.users.create(username: "testuser", password: "password123")
        let auth = ServerAuthentication(user: user, tokenString: token)

        let pushTokenDTO = PushTokenDTO(token: "device-token-123", deviceType: .iOS)

        // Register token
        try ctx.notifications.registerPushToken(pushTokenDTO, for: auth)

        let initialTokens = try ctx.db.find(PushToken.self, PushToken.userID == user.id)
        let initialToken = try #require(initialTokens.first)
        let initialCreatedAt = initialToken.createdAt

        // Advance time
        ctx.dateProvider.advanceTime(by: 3600)

        // Register same token again with same auth token
        try ctx.notifications.registerPushToken(pushTokenDTO, for: auth)

        // Verify token was not updated (createdAt should be the same)
        let updatedTokens = try ctx.db.find(PushToken.self, PushToken.userID == user.id)
        #expect(updatedTokens.count == 1)

        let updatedToken = try #require(updatedTokens.first)
        #expect(updatedToken.createdAt == initialCreatedAt) // Should not have changed
    }

    @Test
    func deletePushTokensByAuthToken() async throws {
        let ctx = try await TestContext.create()

        let (user, token1) = try await ctx.users.create(username: "testuser", password: "password123")
        let token2 = try await ctx.users.createToken(userID: user.id)

        let auth1 = ServerAuthentication(user: user, tokenString: token1)
        let auth2 = ServerAuthentication(user: user, tokenString: token2)

        // Register two tokens with different auth tokens
        try ctx.notifications.registerPushToken(
            PushTokenDTO(token: "device-token-1", deviceType: .iOS),
            for: auth1
        )
        try ctx.notifications.registerPushToken(
            PushTokenDTO(token: "device-token-2", deviceType: .web),
            for: auth2
        )

        // Verify both tokens exist
        let allTokens = try ctx.db.find(PushToken.self, PushToken.userID == user.id)
        #expect(allTokens.count == 2)

        // Delete tokens with first auth token
        try ctx.notifications.deletePushTokens(withAuthToken: token1)

        // Verify only one token remains (the one with token2)
        let remainingTokens = try ctx.db.find(PushToken.self, PushToken.userID == user.id)
        #expect(remainingTokens.count == 1)
        #expect(remainingTokens.first?.authToken == token2)
        #expect(remainingTokens.first?.token == "device-token-2")
    }
}
