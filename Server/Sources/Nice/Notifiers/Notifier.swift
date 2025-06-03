//
//  Notifier.swift
//  Nice
//
//  Created by Harlan Haskins on 6/1/25.
//

import Foundation

protocol Notifier: Sendable {
    func sendNotification(deviceToken: String) async throws
    func shutdown() async throws
}

protocol WebPushNotifierProtocol: Notifier {
    var applicationServerKey: Data { get throws }
}

extension Notifier {
    func shutdown() {
    }
}
