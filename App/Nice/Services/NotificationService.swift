//
//  NotificationService.swift
//  Nice
//
//  Created by Harlan Haskins on 5/18/25.
//

import Foundation
import NiceTypes
import os.log
import UserNotifications
import UIKit

@MainActor
@Observable
final class NotificationService: NSObject {
    let client: HTTPClient
    let notificationCenter = UNUserNotificationCenter.current()
    let logger = Logger(for: NotificationService.self)
    var state: AuthorizationState = .indeterminate
    var hasPushedToken = false

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
        registerIfAllowed()
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
        guard !hasPushedToken else {
            return
        }
        hasPushedToken = true

        try await client.put(
            "notifications",
            body: PushTokenDTO(token: deviceToken, deviceType: .iOS)
        )
        logger.log("Updated push notification token: \(deviceToken)")
    }

    func registerIfAllowed() {
        guard state == .allowed else {
            return
        }
        UIApplication.shared.registerForRemoteNotifications()
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
}

extension NotificationService: UNUserNotificationCenterDelegate {
}
