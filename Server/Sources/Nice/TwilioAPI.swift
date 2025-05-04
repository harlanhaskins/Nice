//
//  TwilioAPI.swift
//  Nice
//
//  Created by Harlan Haskins on 5/3/25.
//
import Foundation

struct TwilioAPI {
    enum TwilioError: Error {
        case apiFailure(Int, String)
    }
    
    static let baseURL = URL(string: "https://api.twilio.com/2010-04-01")!
    var sid: String
    var secret: String

    func sendMessage(_ message: String, to phoneNumber: String) async throws {
        let auth = Data("\(sid):\(secret)".utf8).base64EncodedString()

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "MessagingServiceSid", value: sid),
            URLQueryItem(name: "To", value: phoneNumber),
            URLQueryItem(name: "Body", value: message)
        ]

        var request = URLRequest(url: Self.baseURL.appendingPathComponent("Accounts/\(sid)/Messages.json"))
        request.httpMethod = "POST"
        request.addValue("Basic \(auth)", forHTTPHeaderField: "Authorization")
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data((components.query ?? "").utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Validate the HTTP response status code
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TwilioError.apiFailure(0, "Response is not HTTP")
        }
        
        // Check if the status code indicates success (2xx)
        guard (200..<300).contains(httpResponse.statusCode) else {
            let responseBody = String(decoding: data, as: UTF8.self)
            throw TwilioError.apiFailure(httpResponse.statusCode, responseBody)
        }
        
        // Only log response on success
        print(String(decoding: data, as: UTF8.self))
    }
}
