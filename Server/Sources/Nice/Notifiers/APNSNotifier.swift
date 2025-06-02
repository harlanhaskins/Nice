//
//  APNSNotifier.swift
//  Nice
//
//  Created by Harlan Haskins on 5/18/25.
//

import APNSCore
import APNS
import NIOPosix
import Foundation
import Logging
import NiceTypes

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

struct APNSNotifier: Notifier {
    let logger = Logger(label: "APNSNotifier")
    let client: APNSClient<JSONDecoder, JSONEncoder>
    
    init(secrets: Secrets.APNS) throws {
        let privateKey = try P256.Signing.PrivateKey(pemRepresentation: secrets.privateKey)

        self.client = APNSClient(
            configuration: .init(
                authenticationMethod: .jwt(
                    privateKey: privateKey,
                    keyIdentifier: secrets.keyID,
                    teamIdentifier: secrets.teamID
                ),
                environment: .development
            ),
            eventLoopGroupProvider: .shared(MultiThreadedEventLoopGroup.singleton),
            responseDecoder: JSONDecoder(),
            requestEncoder: JSONEncoder()
        )
    }

    func sendNotification(deviceToken: String) async throws {
        logger.info("Sending notification to device token '\(deviceToken)'")
        try await client.sendAlertNotification(
            .init(
                alert: .init(title: .raw("Nice")),
                expiration: .none,
                priority: .immediately,
                topic: "com.harlanhaskins.Nice",
                payload: [String: String]()
            ),
            deviceToken: deviceToken
        )
    }

    func shutdown() async throws {
        try await client.shutdown()
    }
}
