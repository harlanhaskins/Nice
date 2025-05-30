//
//  CustomAppDelegate.swift
//  Nice
//
//  Created by Harlan Haskins on 5/18/25.
//

import UIKit

extension Notification.Name {
    static let didReceiveRemoteNotificationToken = Notification.Name("didReceiveRemoteNotificationToken")
}

enum NotificationConstants {
    static let deviceTokenKey = "deviceToken"
}

class AppDelegate: NSObject, UIApplicationDelegate, ObservableObject {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        UserDefaults.standard.pushToken = tokenString
        NotificationCenter.default.post(
            name: .didReceiveRemoteNotificationToken,
            object: nil,
            userInfo: [
                NotificationConstants.deviceTokenKey: tokenString
            ]
        )
    }
}
