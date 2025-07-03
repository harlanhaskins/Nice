//
//  NiceController.swift
//  Nice
//
//  Created by Harlan Haskins on 5/12/25.
//


import CoreLocation
import NiceTypes
import Observation
import os.log
import UserNotifications
import UIKit

@Observable
final class NiceController {
    let logger = Logger(for: NiceController.self)
    
    let client: HTTPClient
    let authenticator: Authenticator
    let locationService: LocationService
    let notificationService: NotificationService

    init() {
        client = HTTPClient(baseURL: HTTPClient.baseURL, authentication: nil, urlSession: .shared)
        authenticator = Authenticator(client: client)
        locationService = LocationService(client: client)
        notificationService = NotificationService(client: client)
    }

    func onAuthenticate(_ auth: Authentication) async {
        if let location = auth.user.location {
            locationService.setInitialLocation(location)
        } else if locationService.location != nil {
            await locationService.updateLocation()
        }
    }

    var isAuthenticated: Bool {
        client.authentication != nil
    }

    func signIn(username: String, password: String) async throws -> Authentication {
        let auth = try await authenticator.signIn(username: username, password: password)
        await onAuthenticate(auth)
        return auth
    }

    func signUp(username: String, password: String) async throws -> Authentication {
        let auth = try await authenticator.signUp(
            username: username,
            password: password,
            location: (locationService.location?.coordinate).map { Location($0) }
        )
        await onAuthenticate(auth)
        return auth
    }

    func signOut() async throws {
        try await authenticator.signOut()
        await client.reset()
    }

    func loadForecast() async throws -> Forecast {
        try await client.get("forecast")
    }
}
