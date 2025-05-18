//
//  File.swift
//  Nice
//
//  Created by Harlan Haskins on 5/18/25.
//

import APNSCore
import APNS
import NIOPosix
import Foundation
import Logging
@preconcurrency import SQLite
import Hummingbird
import NiceTypes

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

struct PushToken: Model {
    static let id = Expression<Int64>("id")
    static let userID = Expression<Int64>("userID")
    static let token = Expression<String>("token")
    static let type = Expression<String>("type")

    var id: Int64
    var userID: Int64
    var token: String
    var type: String

    init(_ row: Row) {
        id = row[Self.id]
        userID = row[Self.userID]
        token = row[Self.token]
        type = row[Self.type]
    }
}

final class NotificationController: Sendable {
    enum NotificationError: Error {
        case couldNotFindPrivateKey
    }
    let db: Connection
    let users: UserController
    let client: APNSClient<JSONDecoder, JSONEncoder>
    let logger = Logger(label: "NotificationController")

    init(db: Connection, users: UserController, secrets: Secrets) throws {
        self.db = db
        self.users = users

        let privateKey = try P256.Signing.PrivateKey(pemRepresentation: secrets.apns.privateKey)

        self.client = APNSClient(
            configuration: .init(
                authenticationMethod: .jwt(
                    privateKey: privateKey,
                    keyIdentifier: secrets.apns.keyID,
                    teamIdentifier: secrets.apns.teamID
                ),
                environment: .development
            ),
            eventLoopGroupProvider: .shared(MultiThreadedEventLoopGroup.singleton),
            responseDecoder: JSONDecoder(),
            requestEncoder: JSONEncoder()
        )
    }

    deinit {
        Task { [client] in
            try await client.shutdown()
        }
    }

    func createTables() throws {
        if try db.tableExists(PushToken.self) {
            return
        }
        logger.info("No push token table found in database; creating table...")
        try db.run(PushToken.table.create { t in
            t.column(PushToken.id, primaryKey: true)
            t.column(PushToken.userID)
            t.column(PushToken.token)
            t.column(PushToken.type)
        })
    }

    func registerPushToken(_ dto: PushTokenDTO, for user: User) throws {
        let matchingTokens = try db.count(
            PushToken.self,
            PushToken.token == dto.token &&
            PushToken.type == dto.deviceType.rawValue &&
            PushToken.userID == Int64(user.id)
        )
        if matchingTokens > 0 {
            return
        }
        let newToken = PushToken.table.insert(
            PushToken.token <- dto.token,
            PushToken.type <- dto.deviceType.rawValue,
            PushToken.userID <- Int64(user.id)
        )
        try db.run(newToken)
    }

    func sendNiceNotification(to userID: Int64) async throws {
        var badTokenIDs = [Int64]()

        let tokens = try db.find(PushToken.self, PushToken.userID == userID)
        for token in tokens {
            do {
                try await client.sendAlertNotification(
                    .init(
                        alert: .init(title: .raw("Nice")),
                        expiration: .none,
                        priority: .immediately,
                        topic: "com.harlanhaskins.Nice",
                        payload: [String: String]()
                    ),
                    deviceToken: token.token
                )
            } catch let error as APNSError {
                logger.error("\(error)")
                if error.reason == .badDeviceToken {
                    badTokenIDs.append(token.id)
                }
            } catch {
                logger.error("\(error)")
            }
        }

        if !badTokenIDs.isEmpty {
            try db.run(PushToken.find(badTokenIDs.contains(PushToken.id)).delete())
        }
    }

    func addRoutes(to router: some RouterMethods<AuthenticatedRequestContext>) {
        router
            .put("notifications") { request, context in
                let auth = try context.requireIdentity()
                let location = try await request.decode(
                    as: PushTokenDTO.self,
                    context: context
                )
                try self.registerPushToken(location, for: auth.user)
                return Response(status: .ok)
            }
            .post("notifications/test") { request, context in
                let auth = try context.requireIdentity()
                try await self.sendNiceNotification(to: Int64(auth.user.id))
                return Response(status: .ok)
            }
    }
}

extension Model {
    static func find(_ predicate: SQLite.Expression<Bool>? = nil) -> Table {
        var query = table.select(*)
        if let predicate {
            query = query.filter(predicate)
        }
        return query
    }
}

extension Connection {
    func tableExists<M: Model>(_ type: M.Type) throws -> Bool {
        try !schema.columnDefinitions(table: type.tableName).isEmpty
    }

    func find<M: Model>(
        _ type: M.Type = M.self,
        _ predicate: SQLite.Expression<Bool>? = nil
    ) throws -> [M] {
        try prepare(M.find(predicate)).map(M.init)
    }

    func first<M: Model>(
        _ type: M.Type = M.self,
        _ predicate: SQLite.Expression<Bool>? = nil
    ) throws -> M? {
        try prepare(M.find(predicate)).firstNonNil(M.init)
    }

    func count<M: Model>(
        _ type: M.Type = M.self,
        _ predicate: SQLite.Expression<Bool>
    ) throws -> Int {
        try scalar(M.find(predicate).count)
    }
}
