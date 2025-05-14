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

    func loadNiceness() async throws -> String {
        try await client.get("nice")
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
