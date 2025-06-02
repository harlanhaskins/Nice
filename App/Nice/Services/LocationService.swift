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
    var location: CLLocation?

    init(client: HTTPClient) {
        self.client = client
        super.init()
        locationManager.delegate = self
        checkForAuthorization()
    }

    func setInitialLocation(_ location: Location?) {
        if self.location == nil, let location {
            self.location = CLLocation(latitude: location.latitude, longitude: location.longitude)
        }
    }

    func requestLocationUpdates() {
        checkForAuthorization()
        if state == .allowed { return }
        locationManager.requestWhenInUseAuthorization()
    }

    func didBecomeActive() {
        guard state == .allowed else { return }
        locationManager.startUpdatingLocation()
    }

    func didBecomeInactive() {
        locationManager.stopUpdatingLocation()
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
            let loc = Location(location.coordinate)
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
            let prev = self.location
            self.location = loc

            if prev == nil || prev!.distance(from: loc) > 100 {
                await self.updateLocation()
            } else {
                logger.info("Not updating location; within 100 meters")
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            checkForAuthorization()
            didBecomeActive()
        }
    }
}

extension CLLocationCoordinate2D {
    init(_ location: Location) {
        self.init(latitude: location.latitude, longitude: location.longitude)
    }
}

extension Location {
    init(_ location: CLLocationCoordinate2D) {
        self.init(latitude: location.latitude, longitude: location.longitude)
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
