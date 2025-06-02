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
    var location: Location?

    init(client: HTTPClient) {
        self.client = client
        super.init()
        checkForAuthorization()
    }

    func setInitialLocation(_ location: Location?) {
        if self.location == nil {
            self.location = location
        }
    }

    func requestLocationUpdates() {
        checkForAuthorization()
        if state == .allowed { return }
        locationManager.requestWhenInUseAuthorization()
    }

    func checkForAuthorization() {
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

    func updateLocation() async {
        guard let location else { return }
        do {
            try await client.put("location", body: location)
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
            self.location = Location(
                latitude: loc.coordinate.latitude,
                longitude: loc.coordinate.longitude
            )
            await self.updateLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            checkForAuthorization()
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
