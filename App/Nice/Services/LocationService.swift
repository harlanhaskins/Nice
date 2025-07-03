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
import Contacts

@Observable
final class LocationService: NSObject {
    let client: HTTPClient
    let locationManager = CLLocationManager()
    let logger = Logger(for: LocationService.self)
    var state: AuthorizationState = .indeterminate
    var preciseLocation: CLLocation?
    var location: CLLocation?

    init(client: HTTPClient) {
        self.client = client
        super.init()
        locationManager.delegate = self
        checkForAuthorization()
    }

    func setInitialLocation(_ location: Location?) {
        if self.location == nil, let location {
            self.location = CLLocation(
                latitude: location.latitude,
                longitude: location.longitude
            )
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
        guard let location, client.authentication != nil else { return }
        do {
            let loc = Location(location.coordinate)
            try await client.put("location", body: loc)
        } catch {
            logger.error("Failed to update location: \(error)")
        }
    }
    
    /// Converts a precise CLLocation to a coarse location based on ZIP code
    /// Returns the geographic center of the ZIP code area for privacy protection
    /// Falls back to exact coordinates if coarsening fails
    func coarseLocation(from location: CLLocation) async -> CLLocation {
        let geocoder = CLGeocoder()
        
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            
            guard let placemark = placemarks.first,
                  let postalCode = placemark.postalCode else {
                logger.warning("No postal code found for location, using exact coordinates")
                return location
            }
            
            // Forward geocode the postal code to get its center point
            let forwardPlacemarks = try await geocoder.geocodeAddressString(postalCode)
            
            guard let centerPlacemark = forwardPlacemarks.first,
                  let centerLocation = centerPlacemark.location else {
                logger.warning("Could not geocode postal code: \(postalCode), using exact coordinates")
                return location
            }
            
            logger.info("Coarsened location from precise coordinates to ZIP code \(postalCode) center")
            return centerLocation
            
        } catch {
            logger.error("Failed to coarsen location: \(error), using exact coordinates")
            return location
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let loc = locations.max(by: { $0.timestamp < $1.timestamp }) else {
            return
        }
        Task {
            if let preciseLocation, loc.distance(from: preciseLocation) < 500 {
                return
            }
            self.preciseLocation = loc
            let coarsenedLocation = await coarseLocation(from: loc)
            self.location = coarsenedLocation

            await self.updateLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task {
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
    nonisolated init(_ category: String) {
        self.init(subsystem: "com.harlanhaskins.Nice", category: category)
    }
    nonisolated init(for type: Any.Type) {
        self.init(subsystem: "com.harlanhaskins.Nice", category: _typeName(type, qualified: false))
    }
}
