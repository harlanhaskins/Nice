//
//  WeatherControllerTests.swift
//  Nice
//
//  Created by Harlan Haskins on 5/18/25.
//

import NiceTypes
@testable import Nice
import Testing
import SQLite
import Foundation

struct MockNotifier: Notifier {
    func shutdown() async throws {
    }

    func sendNotification(deviceToken: String) async throws {
    }
}

struct MockWeatherProvider: WeatherProvider {
    func forecast(for location: Location) async throws -> Forecast {
        Forecast(temperature: 69, feelsLike: 69, currentTime: .now, sunset: .now, sunrise: .now, clouds: 69)
    }
}

@Suite
struct WeatherControllerTests {
    @Test
    func testLocationUpdate() throws {
        let db = try Connection(.inMemory)

        let users = UserController(
            db: db,
            dateProvider: CalendarDateProvider(calendar: .autoupdatingCurrent),
            passwordHasher: SHA256PasswordHasher()
        )
        try users.createTables()

        let notificationController = NotificationController(db: db, users: users, notifier: MockNotifier())

        let weather = WeatherController(
            db: db,
            users: users,
            notifications: notificationController,
            weatherProvider: MockWeatherProvider()
        )
        try weather.createTables()

        let username = "trogdor"
        let password = "BurnInatingTh3Countryside!"

        let (user, _) = try users.create(username: username, password: password)

        let location = Location(latitude: 34.5, longitude: -82.3)
        try weather.updateLocation(location, forUserID: user.id)

        // Verify the location update by directly querying the database
        let loc = try #require(try db.first(UserLocation.self, UserLocation.userID == user.id))

        #expect(loc.location == location)
    }

}
