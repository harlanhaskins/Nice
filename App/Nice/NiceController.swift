//
//  NiceController.swift
//  Nice
//
//  Created by Harlan Haskins on 5/12/25.
//


import CoreLocation
import NiceTypes
import Observation
import UserNotifications
import UIKit

@MainActor
@Observable
final class NiceController: NSObject, UNUserNotificationCenterDelegate {
    let client: HTTPClient
    let locationManager = CLLocationManager()
    let notificationCenter = UNUserNotificationCenter.current()

    init(authentication: Authentication) {
        client = HTTPClient(baseURL: HTTPClient.baseURL, authentication: authentication)
        super.init()
        notificationCenter.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(didReceiveNotificationUpdate), name: .didReceiveRemoteNotificationToken, object: nil)
        didReceiveNotificationUpdate()
    }

    func loadNiceness() async throws -> Niceness {
        try await client.get("nice")
    }

    @objc func didReceiveNotificationUpdate() {
        Task {
            try await performNotificationRegistration()
        }
    }

    func performNotificationRegistration() async throws {
        guard let deviceToken = UserDefaults.standard.string(forKey: UserDefaultsKey.deviceToken.rawValue) else {
            return
        }
        try await client.put(
            "notifications",
            body: PushTokenDTO(token: deviceToken, deviceType: .iOS)
        )
    }

    func registerForNotifications() {
        Task {
            do {
                if try await notificationCenter.requestAuthorization(options: [.alert]) {
                    UIApplication.shared.registerForRemoteNotifications()
                    try await performNotificationRegistration()
                }
            } catch {
                print("Failed to register: \(error)")
            }
        }
    }

    func fetchWeather() throws {
        guard let location = locationManager.location else {
            return
        }
        let loc = Location(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)

        Task {
            try await client.put("location", body: loc)
        }
    }

    func requestLocationUpdates() async throws {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            print("Authorized")
        case .notDetermined:
            print("Not determined")
        case .denied, .restricted:
            print("Denied")
        @unknown default:
            print("Nope")
        }
    }
}
