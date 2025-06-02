//
//  Authenticator.swift
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
final class Authenticator {
    enum AuthenticationState: Equatable {
        case unauthenticated
        case pendingRefresh(String)
        case signingIn
        case authenticated(Authentication)
    }

    let client: HTTPClient
    let logger = Logger(for: Authenticator.self)
    var authState: AuthenticationState = .unauthenticated

    init(client: HTTPClient) {
        self.client = client
        if let token = UserDefaults.standard.apiToken {
            authState = .pendingRefresh(token)
            Task {
                try await refreshAuth(token)
            }
        }
    }

    func reset() {
        Task {
            await setAuthentication(nil)
        }
    }

    func setAuthentication(_ auth: Authentication?) async {
        UserDefaults.standard.apiToken = auth?.token.token
        await client.updateAuthentication(auth)
        if let auth {
            authState = .authenticated(auth)
        } else {
            authState = .unauthenticated
        }
    }

    func refreshAuth(_ token: String) async throws {
        do {
            let auth: Authentication = try await client.put("auth", headers: [
                "Authorization": "Bearer \(token)"
            ])
            await setAuthentication(auth)
            logger.log("Token refresh successful; token: \(auth.token.token)")
        } catch {
            await setAuthentication(nil)
        }
    }

    func signIn(username: String, password: String) async throws -> Authentication {
        self.authState = .signingIn
        let request = AuthenticateRequest(username: username, password: password)
        do {
            let auth: Authentication = try await client.post("auth", body: request)
            logger.log("Authentication successful; token: \(auth.token.token)")
            await setAuthentication(auth)
            return auth
        } catch {
            await setAuthentication(nil)
            throw error
        }
    }

    func signUp(username: String, password: String, location: Location?) async throws -> Authentication {
        self.authState = .signingIn
        do {
            let request = CreateUserRequest(username: username, password: password, location: location)
            let auth: Authentication = try await client.post("users", body: request)
            logger.log("Authentication successful; token: \(auth.token.token)")
            await setAuthentication(auth)
            return auth
        } catch {
            await setAuthentication(nil)
            throw error
        }
    }

    func signOut() async throws {
        var query = [URLQueryItem]()
        if let pushToken = UserDefaults.standard.pushToken {
            query.append(URLQueryItem(name: "pushToken", value: pushToken))
        }
        try await client.delete("auth", query: query)
        await setAuthentication(nil)
    }

    func deleteAccount() async throws {
        try await client.delete("users")
        await setAuthentication(nil)
    }
}
