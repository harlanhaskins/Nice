//
//  NotificationService.swift
//  Nice
//
//  Created by Harlan Haskins on 5/18/25.
//

import Foundation
import NiceTypes
import UserNotifications
import UIKit

@MainActor
@Observable
final class NotificationService: NSObject {
    let client: HTTPClient
    let notificationCenter = UNUserNotificationCenter.current()
    var state: AuthorizationState = .indeterminate

    init(client: HTTPClient) {
        self.client = client
        super.init()
        notificationCenter.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(didReceiveNotificationUpdate), name: .didReceiveRemoteNotificationToken, object: nil)
        didReceiveNotificationUpdate()

        Task {
            await checkForNotificationState()
        }
    }

    func checkForNotificationState() async {
        let settings = await notificationCenter.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .ephemeral:
            state = .allowed
        case .denied, .provisional:
            state = .denied
        case .notDetermined:
            state = .indeterminate
        @unknown default:
            state = .denied
        }
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
        if state == .allowed {
            UIApplication.shared.registerForRemoteNotifications()
            return
        }
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
}

extension NotificationService: UNUserNotificationCenterDelegate {
}
