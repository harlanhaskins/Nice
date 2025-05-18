//
//  NiceController.swift
//  Nice
//
//  Created by Harlan Haskins on 5/12/25.
//


import CoreLocation
import NiceTypes
import Observation

@MainActor
@Observable
final class NiceController {
    let client: HTTPClient
    let locationManager = CLLocationManager()
    init(authentication: Authentication) {
        client = HTTPClient(baseURL: HTTPClient.baseURL, authentication: authentication)
    }

    func loadNiceness() async throws -> Niceness {
        try await client.get("nice")
    }

    func fetchWeather() throws {
        guard let location = locationManager.location else {
            return
        }
        let loc = Location(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)

        Task {
            try await client.put("location", body: loc)
        }
    }

    func requestLocationUpdates() async throws {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            print("Authorized")
        case .notDetermined:
            print("Not determined")
        case .denied, .restricted:
            print("Denied")
        @unknown default:
            print("Nope")
        }
    }
}
