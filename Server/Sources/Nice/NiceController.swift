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

final class NiceController: Sendable {
    let users: UserController
    let notifications: NotificationController
    let weather: WeatherAPI
    let logger = Logger(label: "NiceController")

    init(
        users: UserController,
        notifications: NotificationController,
        secrets: Secrets
    ) {
        self.users = users
        self.notifications = notifications
        self.weather = WeatherAPI(key: secrets.weather.apiKey)
    }

    func runWeatherJob(for user: User) async {
        guard let location = user.location else {
            return
        }

        let forecast: Forecast
        do {
            forecast = try await weather.forecast(for: location)
        } catch {
            logger.error("Failed to get weather for user \(user.id): \(error)")
            return
        }

        guard forecast.isNice else {
            logger.info("Temperature for user \(user.id) is \(forecast.temperature); not sending notification")
            return
        }

        do {
            try await notifications.sendNiceNotification(to: user.id)
        } catch {
            logger.error("Failed to send nice notification for \(user.id): \(error)")
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

        for user in users {
            await runWeatherJob(for: user)
        }
    }

    func addRoutes(to router: some RouterMethods<AuthenticatedRequestContext>) {
        router
            .get("nice") { req, context in
                let auth = try context.requireIdentity()
                guard let location = auth.user.location else {
                    throw HTTPError(.badRequest, message: "Location must be set")
                }
                let forecast = try await self.weather.forecast(for: location)
                return Niceness(isNice: forecast.isNice)
            }
            .post("run") { req, context in
                await self.runWeatherJob()
                return Response(status: .ok)
            }
    }
}
