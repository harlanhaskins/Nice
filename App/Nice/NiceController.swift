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
    var notificationState = AuthorizationState.indeterminate

    init(authentication: Authentication) {
        client = HTTPClient(baseURL: HTTPClient.baseURL, authentication: authentication)
        locationService = LocationService(client: client)
        notificationService = NotificationService(client: client)
        super.init()
    }

    func loadForecast() async throws -> Forecast {
        try await client.get("forecast")
    }
}
