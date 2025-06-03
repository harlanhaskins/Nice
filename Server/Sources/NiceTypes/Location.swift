//
//  Location.swift
//  Nice
//
//  Created by Harlan Haskins on 5/4/25.
//

/// Geographic coordinates for weather forecast location
/// Uses standard GPS coordinate system (WGS84)
public struct Location: DTO {
    /// Latitude in decimal degrees (-90 to 90)
    public var latitude: Double
    /// Longitude in decimal degrees (-180 to 180)
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}
