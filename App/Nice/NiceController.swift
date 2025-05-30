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


@MainActor
@Observable
final class NiceController: NSObject, UNUserNotificationCenterDelegate {
    let client: HTTPClient
    let locationManager = CLLocationManager()
    let notificationCenter = UNUserNotificationCenter.current()
    let locationService: LocationService
    let notificationService: NotificationService
    let logger = Logger(for: NiceController.self)
    let authenticator: Authenticator
    var notificationState = AuthorizationState.indeterminate

    init(authentication: Authentication, authenticator: Authenticator) {
        client = HTTPClient(baseURL: HTTPClient.baseURL, authentication: authentication)
        locationService = LocationService(client: client)
        notificationService = NotificationService(client: client)
        self.authenticator = authenticator
        super.init()
    }

    func loadForecast() async throws -> Forecast {
        try await client.get("forecast")
    }

    func signOut() async throws {
        try await authenticator.signOut(pushToken: UserDefaults.standard.pushToken)
    }

    func deleteAccount() async throws {
        try await authenticator.deleteAccount()
    }
}
