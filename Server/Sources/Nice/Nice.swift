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

        let router = Router(context: BasicAuthRequestContext<User>.self)
        router.addMiddleware {
            LogRequestsMiddleware(.debug)

            CORSMiddleware(
                allowOrigin: .originBased,
                allowHeaders: [.accept, .authorization, .contentType, .origin],
                allowMethods: [.get, .options]
            )
        }

        router.put("auth") { request, context in
            let authenticateUser = try await request.decode(
                as: AuthenticateRequest.self,
                context: context
            )
            do {
                let token = try users.authenticate(
                    username: authenticateUser.username,
                    password: authenticateUser.password
                )
                return Authentication(
                    user: UserDTO(id: token.userID, username: authenticateUser.username),
                    token: TokenDTO(userID: token.userID, token: token.content, expires: token.expires)
                )
            }
        }

        router.put("users") { request, context in
            let createUser = try await request.decode(
                as: CreateUserRequest.self,
                context: context
            )
            do {
                let (user, token) = try users.create(
                    username: createUser.username,
                    password: createUser.password,
                    location: createUser.location
                )
                return Authentication(user: user, token: token)
            } catch let error as UserController.UserError {
                throw HTTPError(.unauthorized, message: error.message)
            }
        }

        router.group()
            .add(middleware: Authenticator(userController: users))
            .get("nice") { request, context in
                let user = try context.requireIdentity()
                guard let location = user.location else {
                    throw HTTPError(.badRequest, message: "User '\(user.username)' does not have a location set")
                }
                do {
                    let forecast = try await weather.forecast(
                        for: location
                    )
                    return Int(forecast.temperature) == 69 ? "nice" : "not nice"
                } catch {
                    throw HTTPError(.badRequest)
                }
            }
            .post("location") { request, context in
                let user = try context.requireIdentity()
                let location = try await request.decode(
                    as: Location.self,
                    context: context
                )
                try users.updateLocation(location, forUserID: user.id)
                return Response(status: .ok)
            }
            .put("refresh") { request, context in
                let user = try context.requireIdentity()
                let token = try users.refreshOrCreateToken(userID: user.id)
                return Authentication(user: user, token: token)
            }

        let app = Application(
            router: router,
            configuration: .init(address: .hostname("127.0.0.1", port: 8080))
        )
        try await app.runService()
    }
}

