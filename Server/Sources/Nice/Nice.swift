import Foundation
import Hummingbird
import HummingbirdAuth
import NiceTypes
import SQLite

struct Secrets: Codable {
    struct Weather: Codable {
        var apiKey: String
    }
    var weather: Weather
}

@main
struct Nice {
    static func main() async throws {
        let secretsFile = Bundle.module.url(forResource: "secrets", withExtension: "json")!
        let secrets = try JSONDecoder().decode(Secrets.self, from: Data(contentsOf: secretsFile))
        let weather = WeatherAPI(key: secrets.weather.apiKey)

        let connection = try Connection(.inMemory)
        let users = UserController(db: connection)
        try users.createTables()

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

        authGroup.get("nice") { req, context in
            let auth = try context.requireIdentity()
            guard let location = auth.user.location else {
                throw HTTPError(.badRequest, message: "Location must be set")
            }
            let forecast = try await weather.forecast(for: location)
            return Niceness(isNice: Int(forecast.temperature) == 69)
        }

        let app = Application(
            router: router,
            configuration: .init(address: .hostname("127.0.0.1", port: 8080))
        )
        try await app.runService()
    }
}

