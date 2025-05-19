//
//  Location.swift
//  Nice
//
//  Created by Harlan Haskins on 5/3/25.
//
import Foundation
import NiceTypes

#if os(Linux)
import FoundationNetworking
#endif

struct WeatherAPI: Sendable {
    enum WeatherError: Error {
        case apiFailure(String)
    }
    static let baseURL = URL(string: "https://api.openweathermap.org/data/3.0/onecall")!
    var key: String

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    func forecast(for location: Location) async throws -> Forecast {
        var components = URLComponents(url: Self.baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "lat", value: "\(location.latitude)"),
            URLQueryItem(name: "lon", value: "\(location.longitude)"),
            URLQueryItem(name: "units", value: "imperial"),
            URLQueryItem(name: "appid", value: key),
            URLQueryItem(name: "exclude", value: "minutely,hourly,daily,alerts")
        ]
        struct Response: Codable {
            var current: Forecast
            var timezone: String
        }
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw WeatherError.apiFailure(String(decoding: data, as: UTF8.self))
        }
        return try Self.decoder.decode(Response.self, from: data).current
    }
}
