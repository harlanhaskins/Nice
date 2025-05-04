//
//  Location.swift
//  Nice
//
//  Created by Harlan Haskins on 5/4/25.
//

public struct Location: DTO {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}
