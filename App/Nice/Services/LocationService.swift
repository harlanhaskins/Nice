//
//  LocationService.swift
//  Nice
//
//  Created by Harlan Haskins on 5/18/25.
//

import CoreLocation
import Foundation
import NiceTypes
import os.log

@MainActor
@Observable
final class LocationService: NSObject {
    let client: HTTPClient
    let locationManager = CLLocationManager()
    let logger = Logger(for: LocationService.self)
    var state: AuthorizationState = .indeterminate

    init(client: HTTPClient) {
        self.client = client
        super.init()
        checkForLocationState()
    }

    func requestLocationUpdates() {
        checkForLocationState()
        if state == .allowed { return }
        locationManager.requestWhenInUseAuthorization()
    }

    func checkForLocationState() {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            logger.log("Location updates authorized; not re-requesting")
            state = .allowed
        case .notDetermined:
            state = .indeterminate
        case .denied, .restricted:
            state = .denied
        @unknown default:
            state = .denied
        }
    }

    func updateLocation(_ location: CLLocation) async {
        let loc = Location(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        do {
            try await client.put("location", body: loc)
        } catch {
            logger.error("Failed to update location: \(error)")
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let loc = locations.max(by: { $0.timestamp < $1.timestamp }) else {
            return
        }
        Task { @MainActor in
            await self.updateLocation(loc)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            checkForLocationState()
        }
    }
}

extension Logger {
    init(_ category: String) {
        self.init(subsystem: "com.harlanhaskins.Nice", category: category)
    }
    init(for type: Any.Type) {
        self.init(subsystem: "com.harlanhaskins.Nice", category: _typeName(type, qualified: false))
    }
}
