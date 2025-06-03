//
//  File.swift
//  Nice
//
//  Created by Harlan Haskins on 5/18/25.
//

import Foundation
import Hummingbird
import Logging
import NiceTypes
@preconcurrency import SQLite

struct UserLocation: Model {
    static let id = Expression<Int64>("id")
    static let userID = Expression<Int64>("userID")
    static let latitude = Expression<Double>("latitude")
    static let longitude = Expression<Double>("longitude")
    static let lastTemperature = Expression<Int?>("lastTemperature")
    static let lastNotificationDate = Expression<Int64?>("lastNotificationDate")

    var id: Int64
    var userID: Int64
    var location: Location
    var lastTemperature: Int?
    var lastNotificationDate: Date?

    init(_ row: Row) {
        id = row[UserLocation.id]
        userID = row[UserLocation.userID]
        location = Location(
            latitude: row[UserLocation.latitude],
            longitude: row[UserLocation.longitude]
        )
        lastTemperature = row[UserLocation.lastTemperature]
        if let lastNotificationTimestamp = row[UserLocation.lastNotificationDate] {
            lastNotificationDate = Date(timeIntervalSince1970: TimeInterval(lastNotificationTimestamp))
        }
    }
}

protocol WeatherProvider: Sendable {
    func forecast(for location: Location) async throws -> Forecast
}

extension WeatherAPI: WeatherProvider {}

final class WeatherController: Sendable {
    let db: Connection
    let users: UserController
    let notifications: NotificationController
    let weather: WeatherProvider
    let logger = Logger(label: "NiceController")

    init(
        db: Connection,
        users: UserController,
        notifications: NotificationController,
        weatherProvider: some WeatherProvider
    ) {
        self.db = db
        self.users = users
        self.notifications = notifications
        self.weather = weatherProvider
    }

    func createTables() throws {
        let columns = try db.schema.columnDefinitions(table: UserLocation.tableName)
        if !columns.isEmpty {
            return
        }
        logger.info("No \(UserLocation.tableName) table found in database; creating table...")
        try db.run(UserLocation.table.create { t in
            t.column(UserLocation.id, primaryKey: true)
            t.column(UserLocation.userID, unique: true)
            t.column(UserLocation.latitude)
            t.column(UserLocation.longitude)
            t.column(UserLocation.lastTemperature)
            t.column(UserLocation.lastNotificationDate)
        })
    }

    func runWeatherJob(for user: User, entry: UserLocation) async {
        let forecast: Forecast
        do {
            forecast = try await weather.forecast(for: entry.location)
        } catch {
            logger.error("Failed to get weather for user '\(user.username)': \(error)")
            return
        }

        var suppressNotification = false

        if let lastTemperature = entry.lastTemperature, let lastNotificationDate = entry.lastNotificationDate {
            let timeSinceLastNotification = Date.now.timeIntervalSince(lastNotificationDate)
            let hasSentWithinLastHour = timeSinceLastNotification < (60 * 60)
            if lastTemperature == 69 && hasSentWithinLastHour {
                suppressNotification = true
            }
        }

        var entry = entry
        entry.lastTemperature = Int(forecast.temperature)

        if forecast.isNice {
            if suppressNotification {
                logger.error("Not sending notification for '\(user.username)'; it has been continually nice out")
            } else {
                do {
                    try await notifications.sendNiceNotification(to: user.id)
                    entry.lastNotificationDate = Date()
                } catch {
                    logger.error("Failed to send notification for '\(user.username)': \(error)")
                }
            }
        } else {
            logger.info("Temperature for user '\(user.username)' is \(forecast.temperature); not sending notification")
        }


        // Update the entry in the database to mark that we looked it up
        do {
            let lastTimestamp = (entry.lastNotificationDate?.timeIntervalSince1970).map { Int64($0) }

            let update = UserLocation.table
                .filter(UserLocation.userID == user.id)
                .update(
                    UserLocation.lastTemperature <- entry.lastTemperature,
                    UserLocation.lastNotificationDate <- lastTimestamp
                )
            try db.run(update)
        } catch {
            logger.error("Failed to update user entry for notification: \(error)")
        }
    }

    func runWeatherJob() async {
        let users: [User]
        do {
            users = try self.users.list()
        } catch {
            logger.error("Could not query list of users: \(error)")
            return
        }

        let start = Date.now.timeIntervalSince1970
        logger.info("Beginning weather job for \(users.count) users...")

        for user in users {
            if Task.isCancelled { return }
            guard let location = location(forUserID: user.id) else {
                continue
            }
            await runWeatherJob(for: user, entry: location)
        }

        let end = Date.now.timeIntervalSince1970
        logger.info("Ending weather job for \(users.count) users. Elapsed time: \(Int(end - start)) seconds")
    }

    func location(forUserID userID: Int64) -> UserLocation? {
        try? db.first(UserLocation.self, UserLocation.userID == userID)
    }

    func updateLocation(_ location: Location, forUserID userID: Int64) throws {
        if var entry = self.location(forUserID: userID) {
            entry.location = location
            try db.run(UserLocation.table.update(
                UserLocation.latitude <- location.latitude,
                UserLocation.longitude <- location.longitude
            ))
        } else {
            let create = UserLocation.table.insert(
                UserLocation.userID <- userID,
                UserLocation.latitude <- location.latitude,
                UserLocation.longitude <- location.longitude
            )
            try db.run(create)
        }
    }

    func addRoutes(to router: some RouterMethods<AuthenticatedRequestContext>) {
        router
            .get("forecast") { req, context in
                let auth = try context.requireIdentity()
                guard let entry = self.location(forUserID: auth.user.id) else {
                    throw HTTPError(.badRequest, message: "Location must be set")
                }
                return try await self.weather.forecast(for: entry.location)
            }
            .post("run") { req, context in
                await self.runWeatherJob()
                return Response(status: .ok)
            }
            .put("location") { request, context in
                let auth = try context.requireIdentity()
                let location = try await request.decode(
                    as: Location.self,
                    context: context
                )
                do {
                    try self.updateLocation(location, forUserID: auth.user.id)
                } catch {
                    self.logger.error("\(error)")
                    return Response(status: .badRequest)
                }
                return Response(status: .ok)
            }
    }
}
