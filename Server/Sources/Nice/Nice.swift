import Foundation
import Hummingbird
import HummingbirdAuth
import NiceTypes
import SQLite
import Logging

/// Configuration secrets loaded from JSON file
/// Contains API keys and certificates for external services
struct Secrets: Codable {
    /// Weather API configuration
    struct Weather: Codable {
        /// API key for weather service provider
        var apiKey: String
    }
    /// Apple Push Notification Service configuration
    struct APNS: Codable {
        /// APNS key identifier
        var keyID: String
        /// Apple Developer Team ID
        var teamID: String
        /// Private key for APNS authentication
        var privateKey: String
    }
    /// VAPID configuration for web push notifications
    struct VAPID: Codable {
        /// Public key for client subscription
        var publicKey: String
        /// Private key for server signing
        var privateKey: String
        /// Contact email for push service
        var contact: String
    }
    struct JWT: Codable {
        var secret: String
    }
    /// Weather API secrets
    var weather: Weather
    /// APNS configuration
    var apns: APNS
    /// Web push configuration
    var vapid: VAPID
    /// JWT secret key for token signing
    var jwt: JWT
}

/// Main application entry point
/// Sets up database, controllers, middleware, and starts the server
@main
struct Nice {
    static func main() async throws {
        let secretsFile = Bundle.module.url(forResource: "secrets", withExtension: "json")!
        let secrets = try JSONDecoder().decode(Secrets.self, from: Data(contentsOf: secretsFile))

        let connection = try Connection("nice.db")
        let users = await UserController(db: connection, jwtSecretKey: secrets.jwt.secret)
        try users.createTables()

        let apnsNotifier = try APNSNotifier(secrets: secrets.apns)
        let webPushNotifier = try WebPushNotifier(secrets: secrets.vapid)
        let notifications = NotificationController(db: connection, users: users, apnsNotifier: apnsNotifier, webPushNotifier: webPushNotifier)
        try notifications.createTables()

        let weather = WeatherController(
            db: connection,
            users: users,
            notifications: notifications,
            weatherProvider: WeatherAPI(key: secrets.weather.apiKey)
        )
        try weather.createTables()

        let filePath = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Web")

        let router = Router(context: AuthenticatedRequestContext.self)
            .addMiddleware {
                RequestLoggerMiddleware()

                FileMiddleware(filePath.path, searchForIndexHtml: true)

                CORSMiddleware(
                    allowOrigin: .originBased,
                    allowHeaders: [.accept, .authorization, .contentType, .origin],
                    allowMethods: [.get, .options]
                )
            }

        let apiGroup = router.group("api")

        users.addUnauthenticatedRoutes(to: apiGroup, weather: weather)
        notifications.addPublicRoutes(to: apiGroup)

        let authGroup = apiGroup.add(middleware: Authenticator(userController: users))
        users.addRoutes(to: authGroup, weather: weather)
        notifications.addRoutes(to: authGroup)
        weather.addRoutes(to: authGroup)

        let runner = JobRunner(weather: weather)
        await runner.start()
        defer {
            Task {
                await runner.stop()
            }
        }

        let app = Application(
            router: router,
            configuration: .init(address: .hostname("127.0.0.1", port: 8080))
        )
        try await app.runService()
    }
}

