//
//  WebPushNotifier.swift
//  Nice
//
//  Created by Harlan Haskins on 5/18/25.
//

import Foundation
import Logging
import NiceTypes

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

struct WebPushNotifier: Notifier {
    let logger = Logger(label: "WebPushNotifier")
    let vapidKeys: Secrets.VAPID
    
    init(secrets: Secrets.VAPID) throws {
        self.vapidKeys = secrets
    }
    
    func sendNotification(deviceToken: String) async throws {
        logger.info("Sending web push notification to subscription")
        
        // Parse the subscription JSON from deviceToken
        guard let subscriptionData = deviceToken.data(using: .utf8),
              let subscription = try? JSONSerialization.jsonObject(with: subscriptionData) as? [String: Any],
              let endpoint = subscription["endpoint"] as? String,
              let keys = subscription["keys"] as? [String: String],
              let p256dh = keys["p256dh"],
              let auth = keys["auth"] else {
            throw WebPushError.invalidSubscription
        }
        
        // Create the notification payload
        let payload = WebPushPayload(
            title: "Nice",
            body: "",
            icon: nil,
            badge: nil,
            tag: "nice-notification"
        )
        
        let payloadData = try JSONEncoder().encode(payload)
        
        // Create VAPID headers
        let vapidHeaders = try createVapidHeaders(for: endpoint)
        
        // Send the notification
        try await sendWebPushNotification(
            to: endpoint,
            payload: payloadData,
            vapidHeaders: vapidHeaders,
            userPublicKey: p256dh,
            userAuth: auth
        )
    }
    
    func shutdown() async throws {
        // No cleanup needed for manual implementation
    }
    
    var applicationServerKey: Data {
        get throws {
            // Extract the public key from the private key for browser compatibility
            let privateKey = try P256.Signing.PrivateKey(pemRepresentation: vapidKeys.privateKey)
            let publicKey = privateKey.publicKey

            // Create uncompressed public key format (65 bytes: 0x04 + 64 bytes of raw data)
            var uncompressedKey = Data([0x04])
            uncompressedKey.append(publicKey.rawRepresentation)

            return uncompressedKey
        }
    }
    
    private func createVapidHeaders(for endpoint: String) throws -> [String: String] {
        guard let endpointURL = URL(string: endpoint),
              let host = endpointURL.host else {
            throw WebPushError.invalidEndpoint
        }
        
        let audience = "\(endpointURL.scheme!)://\(host)"
        let exp = Int(Date().addingTimeInterval(12 * 3600).timeIntervalSince1970) // 12 hours
        
        let claims: [String: Any] = [
            "aud": audience,
            "exp": exp,
            "sub": "mailto:\(vapidKeys.contact)"
        ]
        
        logger.info("VAPID claims - audience: \(audience), exp: \(exp), sub: mailto:\(vapidKeys.contact)")
        
        let jwt = try createJWT(claims: claims)
        
        // Get the public key in base64url format for the header
        let publicKeyB64 = try applicationServerKey.base64URLEncodedString()

        return [
            "Authorization": "vapid t=\(jwt), k=\(publicKeyB64)"
        ]
    }
    
    private func createJWT(claims: [String: Any]) throws -> String {
        let header = ["typ": "JWT", "alg": "ES256"]
        
        let headerData = try JSONSerialization.data(withJSONObject: header)
        let claimsData = try JSONSerialization.data(withJSONObject: claims)
        
        let headerB64 = headerData.base64URLEncodedString()
        let claimsB64 = claimsData.base64URLEncodedString()
        
        let message = "\(headerB64).\(claimsB64)"
        let messageData = message.data(using: .utf8)!
        
        // Create signature using VAPID private key
        let privateKey = try P256.Signing.PrivateKey(pemRepresentation: vapidKeys.privateKey)
        let signature = try privateKey.signature(for: messageData)
        let signatureB64 = signature.rawRepresentation.base64URLEncodedString()
        
        return "\(message).\(signatureB64)"
    }
    
    private func sendWebPushNotification(
        to endpoint: String,
        payload: Data,
        vapidHeaders: [String: String],
        userPublicKey: String,
        userAuth: String
    ) async throws {
        guard let url = URL(string: endpoint) else {
            throw WebPushError.invalidEndpoint
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("86400", forHTTPHeaderField: "TTL") // 24 hours
        
        // Add VAPID headers
        for (key, value) in vapidHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        logger.info("Sending Web Push request to: \(endpoint)")
        logger.info("VAPID Authorization header: \(vapidHeaders["Authorization"] ?? "missing")")
        
        // For now, send an empty payload since we're not implementing encryption yet
        // The service worker can show a default notification
        // In production, you should encrypt the payload using the user's public key and auth secret
        request.httpBody = Data() // Empty payload
        
        // Remove Content-Type for empty payload
        request.setValue(nil, forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebPushError.invalidResponse
        }
        
        logger.info("Web Push response status: \(httpResponse.statusCode)")
        
        if httpResponse.statusCode >= 400 {
            let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
            logger.error("Web Push error response: \(responseBody)")
            logger.error("Response headers: \(httpResponse.allHeaderFields)")
            throw WebPushError.httpError(httpResponse.statusCode)
        }
        
        logger.info("Web push notification sent successfully")
    }
}

struct WebPushPayload: Codable {
    let title: String
    let body: String
    let icon: String?
    let badge: String?
    let tag: String
    
    enum CodingKeys: String, CodingKey {
        case title, body, icon, badge, tag
    }
}

enum WebPushError: Error {
    case invalidSubscription
    case invalidEndpoint
    case invalidResponse
    case httpError(Int)
}

extension Data {
    func base64URLEncodedString() -> String {
        return base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
