import Foundation
import Hummingbird
import HummingbirdAuth
import NiceTypes
import SQLite
import Logging

struct Secrets: Codable {
    struct Weather: Codable {
        var apiKey: String
    }
    struct APNS: Codable {
        var keyID: String
        var teamID: String
        var privateKey: String
    }
    struct VAPID: Codable {
        var publicKey: String
        var privateKey: String
        var contact: String
    }
    var weather: Weather
    var apns: APNS
    var vapid: VAPID
}

@main
struct Nice {
    static func main() async throws {
        let secretsFile = Bundle.module.url(forResource: "secrets", withExtension: "json")!
        let secrets = try JSONDecoder().decode(Secrets.self, from: Data(contentsOf: secretsFile))

        let connection = try Connection("nice.db")
        let users = UserController(db: connection)
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

        let router = Router(context: AuthenticatedRequestContext.self)
            .addMiddleware {
                RequestLoggerMiddleware()

                CORSMiddleware(
                    allowOrigin: .originBased,
                    allowHeaders: [.accept, .authorization, .contentType, .origin],
                    allowMethods: [.get, .options]
                )
            }

        users.addUnauthenticatedRoutes(to: router, weather: weather)
        notifications.addPublicRoutes(to: router)

        let authGroup = router.group().add(middleware: Authenticator(userController: users))
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

