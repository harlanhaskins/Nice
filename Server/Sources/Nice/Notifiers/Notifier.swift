//
//  Notifier.swift
//  Nice
//
//  Created by Harlan Haskins on 6/1/25.
//

protocol Notifier: Sendable {
    func sendNotification(deviceToken: String) async throws
    func shutdown() async throws
}

extension Notifier {
    func shutdown() {
    }
}
