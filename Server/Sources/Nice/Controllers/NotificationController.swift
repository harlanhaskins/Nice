//
//  NotificationController.swift
//  Nice
//
//  Created by Harlan Haskins on 5/18/25.
//

import APNSCore
import APNS
import Foundation
import Logging
@preconcurrency import SQLite
import Hummingbird
import NiceTypes

/// Database model for push notification tokens
/// Associates device tokens with users and auth tokens for security
struct PushToken: Model {
    /// Database column expressions for type-safe queries
    static let id = Expression<Int64>("id")
    static let userID = Expression<Int64>("userID")
    static let token = Expression<String>("token")
    static let authToken = Expression<String>("authToken")
    static let type = Expression<String>("type")
    static let createdAt = Expression<Int64>("createdAt")

    /// Unique push token record identifier
    var id: Int64
    /// Foreign key to user table
    var userID: Int64
    /// Authentication token this push token is bound to
    var authToken: String
    /// Device-specific push token (APNS or VAPID)
    var token: String
    /// Device type string (iOS or web)
    var type: String
    /// Timestamp when token was created
    var createdAt: Int64

    init(_ row: Row) {
        id = row[Self.id]
        userID = row[Self.userID]
        token = row[Self.token]
        type = row[Self.type]
        authToken = row[Self.authToken]
        createdAt = row[Self.createdAt]
    }
}


/// Controller for push notification management
/// Handles registration and delivery across iOS and web platforms
final class NotificationController: Sendable {
    /// Errors specific to notification operations
    enum NotificationError: Error {
        /// APNS private key not found or invalid
        case couldNotFindPrivateKey
        /// Unknown device type for notification
        case unsupportedDeviceType
    }
    let db: Connection
    let users: UserController
    let apnsNotifier: any Notifier
    let webPushNotifier: any WebPushNotifierProtocol
    let dateProvider: DateProviding
    let logger = Logger(label: "NotificationController")

    init(db: Connection, users: UserController, apnsNotifier: any Notifier, webPushNotifier: any WebPushNotifierProtocol, dateProvider: DateProviding = CalendarDateProvider(calendar: .current)) {
        self.db = db
        self.users = users
        self.apnsNotifier = apnsNotifier
        self.webPushNotifier = webPushNotifier
        self.dateProvider = dateProvider
    }

    deinit {
        Task { [apnsNotifier, webPushNotifier] in
            try await apnsNotifier.shutdown()
            try await webPushNotifier.shutdown()
        }
    }
    
    private func notifier(for deviceType: DeviceType) -> Notifier {
        switch deviceType {
        case .iOS:
            return apnsNotifier
        case .web:
            return webPushNotifier
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
            t.column(PushToken.authToken)
            t.column(PushToken.type)
            t.column(PushToken.createdAt)
        })
    }

    /// Delete all push tokens associated with a specific auth token
    /// Used to clean up tokens when an auth token expires or is invalidated
    /// - Parameter authToken: The auth token string to match
    func deletePushTokens(withAuthToken authToken: String) throws {
        let deletedCount = try db.run(PushToken.find(PushToken.authToken == authToken).delete())
        if deletedCount > 0 {
            logger.info("Deleted \(deletedCount) push token(s) with invalid auth token")
        }
    }

    /// Register a push notification token for a user
    /// Overwrites existing token for same device/user combo to prevent duplicates
    /// - Parameters:
    ///   - dto: Push token registration data
    ///   - auth: Current user authentication
    func registerPushToken(_ dto: PushTokenDTO, for auth: ServerAuthentication) throws {
        // Check if token already exists for this user/device combination
        let existing = try db.first(
            PushToken.self,
            PushToken.token == dto.token &&
            PushToken.type == dto.deviceType.rawValue &&
            PushToken.userID == auth.user.id
        )

        let now = Int64(dateProvider.now.timeIntervalSince1970)

        if let existing {
            // If the database is up to date, no need to do anything.
            if existing.authToken == auth.tokenString {
                return
            }

            // Update existing token with new authToken and createdAt
            try db.run(PushToken.find(PushToken.id == existing.id).update(
                PushToken.authToken <- auth.tokenString,
                PushToken.createdAt <- now
            ))
        } else {
            // Insert new token
            let newToken = PushToken.table.insert(
                PushToken.token <- dto.token,
                PushToken.type <- dto.deviceType.rawValue,
                PushToken.userID <- auth.user.id,
                PushToken.authToken <- auth.tokenString,
                PushToken.createdAt <- now
            )
            try db.run(newToken)
        }
    }

    /// Send "nice weather" notification to all user's devices
    /// Handles both iOS (APNS) and web (VAPID) push notifications
    /// Automatically cleans up invalid tokens
    /// - Parameter userID: User to send notification to
    func sendNiceNotification(to userID: Int64) async throws {
        var badTokenIDs = [Int64]()

        let tokens = try db.find(PushToken.self, PushToken.userID == userID)
        for token in tokens {
            guard let deviceType = DeviceType(rawValue: token.type) else {
                logger.error("Unknown device type: \(token.type)")
                continue
            }
            
            let selectedNotifier = notifier(for: deviceType)
            
            do {
                try await selectedNotifier.sendNotification(deviceToken: token.token)
            } catch let error as APNSError {
                logger.error("\(error)")
                if error.reason == .badDeviceToken {
                    badTokenIDs.append(token.id)
                }
            } catch let error as WebPushError {
                logger.error("\(error)")
                switch error {
                case .httpError(410), .httpError(404):
                    badTokenIDs.append(token.id)
                default:
                    break
                }
            } catch {
                logger.error("\(error)")
            }
        }

        if !badTokenIDs.isEmpty {
            try db.run(PushToken.find(badTokenIDs.contains(PushToken.id)).delete())
        }
    }

    /// Register public notification routes
    /// Routes: GET /notifications/vapid-public-key (for web push setup)
    func addPublicRoutes(to router: some RouterMethods<AuthenticatedRequestContext>) {
        router
            .get("notifications/vapid-public-key") { request, context in
                let publicKeyData = try self.webPushNotifier.applicationServerKey
                let base64Key = publicKeyData.base64EncodedString()
                return ["publicKey": base64Key]
            }
    }
    
    /// Register protected notification routes
    /// Routes: PUT /notifications (register token), POST /notifications/test
    func addRoutes(to router: some RouterMethods<AuthenticatedRequestContext>) {
        router
            .put("notifications") { request, context in
                let auth = try context.requireIdentity()
                let location = try await request.decode(
                    as: PushTokenDTO.self,
                    context: context
                )
                try self.registerPushToken(location, for: auth)
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
