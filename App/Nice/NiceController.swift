//
//  NiceController.swift
//  Nice
//
//  Created by Harlan Haskins on 5/4/25.
//

import Foundation
import NiceTypes
import Observation
import os

@MainActor
@Observable
final class NiceController {
    enum AuthenticationState {
        case unauthenticated
        case pendingRefresh(String)
        case authenticated(Authentication)
    }

    let logger = Logger(subsystem: "com.harlanhaskins.Nice", category: "NiceController")
    static let baseURL = URL(string: "http://127.0.0.1:8080")!
    let client = HTTPClient(baseURL: NiceController.baseURL)
    var authState: AuthenticationState = .unauthenticated

    init() {
        if let token = UserDefaults.standard.string(forKey: "APIToken") {
            authState = .pendingRefresh(token)
            Task {
                try await refreshAuth(token)
            }
        }
    }

    func refreshAuth(_ token: String) async throws {
        do {
            let auth: Authentication = try await client.put("refresh", headers: [
                "Authorization": "Bearer \(token)"
            ])
            self.authState = .authenticated(auth)
            logger.log("Token refresh successful; token: \(auth.token.token)")
            await client.updateAuthentication(auth)
        } catch {
            authState = .unauthenticated
        }
    }

    func signIn(username: String, password: String) async throws {
        let request = AuthenticateRequest(username: username, password: password)
        let auth: Authentication = try await client.put("auth", body: request)
        logger.log("Authentication successful; token: \(auth.token.token)")
        self.authState = .authenticated(auth)
        await client.updateAuthentication(auth)
    }
}
