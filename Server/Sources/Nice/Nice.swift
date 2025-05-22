import Foundation
import Hummingbird
import HummingbirdAuth
import NiceTypes
import SQLite

struct Secrets: Codable {
    struct Weather: Codable {
        var apiKey: String
    }
    struct APNS: Codable {
        var keyID: String
        var teamID: String
        var privateKey: String
    }
    var weather: Weather
    var apns: APNS
}

@main
struct Nice {
    static func main() async throws {
        let secretsFile = Bundle.module.url(forResource: "secrets", withExtension: "json")!
        let secrets = try JSONDecoder().decode(Secrets.self, from: Data(contentsOf: secretsFile))

        let connection = try Connection("nice.db")
        let users = UserController(db: connection)
        try users.createTables()

        let notifications = try NotificationController(db: connection, users: users, notifier: APNSNotifier(secrets: secrets.apns))
        try notifications.createTables()

        let weather = WeatherController(
            db: connection,
            users: users,
            notifications: notifications,
            weatherProvider: WeatherAPI(key: secrets.weather.apiKey)
        )
        try weather.createTables()

        let router = Router(context: AuthenticatedRequestContext.self)
        router.addMiddleware {
            LogRequestsMiddleware(.trace)

            CORSMiddleware(
                allowOrigin: .originBased,
                allowHeaders: [.accept, .authorization, .contentType, .origin],
                allowMethods: [.get, .options]
            )

            FileMiddleware(urlBasePath: ".well-known")
        }

        users.addUnauthenticatedRoutes(to: router, weather: weather)

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

