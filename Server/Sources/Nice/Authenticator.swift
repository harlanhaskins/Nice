//
//  Authenticator.swift
//  Nice
//
//  Created by Harlan Haskins on 5/4/25.
//

import Foundation
import Hummingbird
import HummingbirdAuth

/// Authentication errors
enum AuthenticatorError: Error, CustomStringConvertible {
    /// Missing Authorization header
    case missingAuthorizationHeader
    
    /// Invalid Authorization header format
    case invalidAuthorizationHeader
    
    var description: String {
        switch self {
        case .missingAuthorizationHeader:
            return "Missing Authorization header"
        case .invalidAuthorizationHeader:
            return "Invalid Authorization header format"
        }
    }
}

typealias AuthenticatedRequestContext = BasicAuthRequestContext<ServerAuthentication>

final class Authenticator: MiddlewareProtocol {
    /// The UserController instance to use for authentication
    private let userController: UserController
    
    /// Creates a new authenticator
    /// - Parameter userController: The UserController instance to use
    init(userController: UserController) {
        self.userController = userController
    }

    /// Extracts token from HTTP headers
    /// - Parameter headers: The HTTP headers to extract the token from
    /// - Returns: The bearer token
    /// - Throws: AuthenticatorError if headers are invalid or missing
    func extractToken(from headers: HTTPFields) throws -> String {
        guard let authHeader = headers[.authorization] else {
            throw AuthenticatorError.missingAuthorizationHeader
        }
        
        let components = authHeader.split(separator: " ", maxSplits: 1)
        guard components.count == 2, components[0].lowercased() == "bearer" else {
            throw AuthenticatorError.invalidAuthorizationHeader
        }
        
        return String(components[1])
    }
    
    /// Get authenticated user from headers
    /// - Parameter headers: HTTP headers containing authorization information
    /// - Returns: The authenticated user
    /// - Throws: Error if authentication fails or user not found
    func authentication(headers: HTTPFields) async throws -> ServerAuthentication {
        let tokenContent = try extractToken(from: headers)
        let userID = try await userController.authenticate(token: tokenContent)
        let user = try userController.user(withID: userID)
        return ServerAuthentication(user: user, tokenString: tokenContent)
    }

    func handle(
        _ request: Request,
        context: BasicAuthRequestContext<ServerAuthentication>,
        next: (Request, BasicAuthRequestContext<ServerAuthentication>) async throws -> Response
    ) async throws -> Response {
        var context = context
        do {
            context.identity = try await authentication(headers: request.headers)
        } catch {
            throw HTTPError(.unauthorized)
        }
        return try await next(request, context)
    }
}
