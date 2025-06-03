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

struct MockWebPushNotifier: WebPushNotifierProtocol {
    func shutdown() async throws {
    }

    func sendNotification(deviceToken: String) async throws {
    }
    
    var applicationServerKey: Data {
        get throws { Data() }
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

        let notificationController = NotificationController(db: db, users: users, apnsNotifier: MockNotifier(), webPushNotifier: MockWebPushNotifier())

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

    @Test
    func testWeatherJobOnlyUpdatesCorrectUser() async throws {
        let db = try Connection(.inMemory)

        let users = UserController(
            db: db,
            dateProvider: CalendarDateProvider(calendar: .autoupdatingCurrent),
            passwordHasher: SHA256PasswordHasher()
        )
        try users.createTables()

        let notificationController = NotificationController(db: db, users: users, apnsNotifier: MockNotifier(), webPushNotifier: MockWebPushNotifier())

        let weather = WeatherController(
            db: db,
            users: users,
            notifications: notificationController,
            weatherProvider: MockWeatherProvider()
        )
        try weather.createTables()

        // Create two users with locations
        let (user1, _) = try users.create(username: "user1", password: "password1")
        let (user2, _) = try users.create(username: "user2", password: "password2")

        let location1 = Location(latitude: 34.5, longitude: -82.3)
        let location2 = Location(latitude: 40.7, longitude: -74.0)

        try weather.updateLocation(location1, forUserID: user1.id)
        try weather.updateLocation(location2, forUserID: user2.id)

        // Get initial locations
        let initialLoc1 = try #require(try db.first(UserLocation.self, UserLocation.userID == user1.id))
        let initialLoc2 = try #require(try db.first(UserLocation.self, UserLocation.userID == user2.id))

        // Verify both users have no initial temperature or notification date
        #expect(initialLoc1.lastTemperature == nil)
        #expect(initialLoc1.lastNotificationDate == nil)
        #expect(initialLoc2.lastTemperature == nil)
        #expect(initialLoc2.lastNotificationDate == nil)

        // Run weather job for user1 - this should only update user1's record
        await weather.runWeatherJob(for: user1, entry: initialLoc1)

        // Verify that only user1's record was updated, not user2's
        let updatedLoc1 = try #require(try db.first(UserLocation.self, UserLocation.userID == user1.id))
        let updatedLoc2 = try #require(try db.first(UserLocation.self, UserLocation.userID == user2.id))

        // User1 should have updated temperature (MockWeatherProvider returns 69)
        #expect(updatedLoc1.lastTemperature == 69)

        // User2 should still have nil values - this was the bug!
        // If the bug existed, user2 would also have lastTemperature = 69
        #expect(updatedLoc2.lastTemperature == nil)
        #expect(updatedLoc2.lastNotificationDate == nil)
    }

}
