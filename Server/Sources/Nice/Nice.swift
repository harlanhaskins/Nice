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

        let notifications = try NotificationController(db: connection, users: users, secrets: secrets)
        try notifications.createTables()

        let nice = NiceController(users: users, notifications: notifications, secrets: secrets)

        let router = Router(context: AuthenticatedRequestContext.self)
        router.addMiddleware {
            LogRequestsMiddleware(.trace)

            CORSMiddleware(
                allowOrigin: .originBased,
                allowHeaders: [.accept, .authorization, .contentType, .origin],
                allowMethods: [.get, .options]
            )
        }

        users.addUnauthenticatedRoutes(to: router)

        let authGroup = router.group().add(middleware: Authenticator(userController: users))
        users.addRoutes(to: authGroup)
        notifications.addRoutes(to: authGroup)
        nice.addRoutes(to: authGroup)

        let runner = JobRunner(nice: nice)
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

