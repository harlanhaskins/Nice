//
//  HTTPClient.swift
//  Nice
//
//  Created by Harlan Haskins on 5/4/25.
//

import Foundation
import NiceTypes
import os
import Synchronization

struct APIError: nonisolated Codable, LocalizedError {
    var message: String

    var errorDescription: String? {
        message
    }
}

private struct APIErrorResponse: nonisolated Codable {
    var error: APIError
}

actor HTTPClient {
    let logger = Logger(for: HTTPClient.self)

    let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    let urlSession: URLSession
    let baseURL: URL
    let authenticationLock = Mutex<Authentication?>(nil)

    nonisolated var authentication: Authentication? {
        get { authenticationLock.withLock { $0 } }
        set { authenticationLock.withLock { $0 = newValue } }
    }

    init(baseURL: URL, authentication: Authentication?, urlSession: URLSession = .shared) {
        self.baseURL = baseURL
        self.urlSession = urlSession
        self.authenticationLock.withLock { $0 = authentication }
    }

    func updateAuthentication(_ authentication: Authentication?) {
        self.authentication = authentication
    }

    func reset() {
        self.authentication = nil
    }

    enum HTTPMethod: String {
        case get, put, delete, post, head, options

        var name: String {
            rawValue.uppercased()
        }
    }

    func makeRequest(
        _ method: HTTPMethod,
        path: String,
        query: [URLQueryItem],
        headers: [String: String]
    ) -> URLRequest {
        let url = baseURL.appending(path: path)
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.httpMethod = method.name
        if let authentication {
            request.setValue("Bearer \(authentication.token.token)", forHTTPHeaderField: "Authorization")
        }
        for (header, value) in headers {
            request.setValue(value, forHTTPHeaderField: header)
        }
        return request
    }

    func extractError(_ httpResponse: HTTPURLResponse, data: Data) -> Error {
        let errorMessage = String(decoding: data, as: UTF8.self)
        logger.error("Received \(httpResponse.statusCode) error from server at '\(httpResponse.url!.path)': \(errorMessage)")
        do {
            return try decoder.decode(APIErrorResponse.self, from: data).error
        } catch {
            return URLError(.badServerResponse)
        }
    }

    func performRequest<Result: Decodable>(_ request: URLRequest) async throws -> Result {
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw extractError(httpResponse, data: data)
        }
        return try decoder.decode(Result.self, from: data)
    }

    func performRequest(_ request: URLRequest) async throws {
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw extractError(httpResponse, data: data)
        }
    }

    func send<Result: Decodable>(
        _ method: HTTPMethod,
        path: String,
        query: [URLQueryItem],
        headers: [String: String]
    ) async throws -> Result {
        let request = makeRequest(method, path: path, query: query, headers: headers)
        return try await performRequest(request)
    }

    func send<Body: Encodable, Result: Decodable>(
        _ method: HTTPMethod,
        path: String,
        query: [URLQueryItem],
        headers: [String: String],
        body: Body
    ) async throws -> Result {
        var request = makeRequest(method, path: path, query: query, headers: headers)
        request.httpBody = try encoder.encode(body)
        return try await performRequest(request)
    }

    func send<Body: Encodable>(
        _ method: HTTPMethod,
        path: String,
        query: [URLQueryItem],
        headers: [String: String],
        body: Body
    ) async throws {
        var request = makeRequest(method, path: path, query: query, headers: headers)
        request.httpBody = try encoder.encode(body)
        try await performRequest(request)
    }

    func send(
        _ method: HTTPMethod,
        path: String,
        query: [URLQueryItem],
        headers: [String: String]
    ) async throws {
        let request = makeRequest(method, path: path, query: query, headers: headers)
        try await performRequest(request)
    }

    func get<Result: Decodable>(
        _ path: String,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:]
    ) async throws -> Result {
        try await send(.get, path: path, query: query, headers: headers)
    }

    func delete<Result: Decodable>(
        _ path: String,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:]
    ) async throws -> Result {
        try await send(.delete, path: path, query: query, headers: headers)
    }

    func delete(
        _ path: String,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:]
    ) async throws {
        try await send(.delete, path: path, query: query, headers: headers)
    }

    func delete<Body: Encodable>(
        _ path: String,
        body: Body,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:]
    ) async throws {
        try await send(.delete, path: path, query: query, headers: headers, body: body)
    }

    func post<Body: Encodable, Result: Decodable>(
        _ path: String,
        body: Body?,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:]
    ) async throws -> Result {
        try await send(.post, path: path, query: query, headers: headers, body: body)
    }

    func post<Result: Decodable>(
        _ path: String,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:]
    ) async throws -> Result {
        try await send(.post, path: path, query: query, headers: headers)
    }

    func put<Body: Encodable, Result: Decodable>(
        _ path: String,
        body: Body?,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:]
    ) async throws -> Result {
        try await send(.put, path: path, query: query, headers: headers, body: body)
    }

    func put<Result: Decodable>(
        _ path: String,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:]
    ) async throws -> Result {
        try await send(.put, path: path, query: query, headers: headers)
    }

    func put<Body: Encodable>(
        _ path: String,
        body: Body?,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:]
    ) async throws {
        try await send(.put, path: path, query: query, headers: headers, body: body)
    }
}

extension HTTPClient {
    static nonisolated let localURL = URL(string: "https://barnacle-driven-hornet.ngrok-free.app/api")!
    static nonisolated let productionURL = URL(string: "https://nice.harlanhaskins.com/api")!
    static nonisolated let baseURL = productionURL
}

