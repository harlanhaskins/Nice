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

    let client = HTTPClient(baseURL: HTTPClient.baseURL, authentication: nil, urlSession: .shared)
    let logger = Logger(for: Authenticator.self)
    var authState: AuthenticationState = .unauthenticated

    init() {
        if let token = UserDefaults.standard.apiToken {
            authState = .pendingRefresh(token)
            Task {
                try await refreshAuth(token)
            }
        }
    }

    func setAuthentication(_ auth: Authentication?) async {
        UserDefaults.standard.apiToken = auth?.token.token
        await client.updateAuthentication(auth)
    }

    func refreshAuth(_ token: String) async throws {
        do {
            let auth: Authentication = try await client.put("auth", headers: [
                "Authorization": "Bearer \(token)"
            ])
            self.authState = .authenticated(auth)
            await setAuthentication(auth)
            logger.log("Token refresh successful; token: \(auth.token.token)")
        } catch {
            authState = .unauthenticated
            await setAuthentication(nil)
        }
    }

    func signIn(username: String, password: String) async throws {
        self.authState = .signingIn
        let request = AuthenticateRequest(username: username, password: password)
        do {
            let auth: Authentication = try await client.post("auth", body: request)
            logger.log("Authentication successful; token: \(auth.token.token)")
            self.authState = .authenticated(auth)
            await setAuthentication(auth)
        } catch {
            self.authState = .unauthenticated
            await setAuthentication(nil)
            throw error
        }
    }

    func signUp(username: String, password: String) async throws {
        self.authState = .signingIn
        do {
            let request = CreateUserRequest(username: username, password: password, location: nil)
            let auth: Authentication = try await client.post("users", body: request)
            logger.log("Authentication successful; token: \(auth.token.token)")
            self.authState = .authenticated(auth)
            await setAuthentication(auth)
        } catch {
            self.authState = .unauthenticated
            await setAuthentication(nil)
            throw error
        }
    }

    func signOut(pushToken: String?) async throws {
        var query = [URLQueryItem]()
        if let pushToken {
            query.append(URLQueryItem(name: "pushToken", value: pushToken))
        }
        try await client.delete("auth", query: query)
        self.authState = .unauthenticated
        await setAuthentication(nil)
    }
}
