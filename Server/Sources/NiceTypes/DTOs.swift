//
//  UserDTOs.swift
//  Nice
//
//  Created by Harlan Haskins on 5/4/25.
//

import Foundation

public protocol DTO: Codable, Sendable, Equatable {}

public struct Forecast: DTO {
    public var temperature: Double
    public var feelsLike: Double
    public var currentTime: Date
    public var sunset: Date
    public var sunrise: Date
    public var clouds: Int

    public var isNice: Bool {
        Int(temperature) == 69
    }

    public init(
        temperature: Double,
        feelsLike: Double,
        currentTime: Date,
        sunset: Date,
        sunrise: Date,
        clouds: Int
    ) {
        self.temperature = temperature
        self.feelsLike = feelsLike
        self.currentTime = currentTime
        self.sunset = sunset
        self.sunrise = sunrise
        self.clouds = clouds
    }
}

public struct CreateUserRequest: DTO {
    public var username: String
    public var password: String
    public var location: Location?

    public init(
        username: String,
        password: String,
        location: Location?
    ) {
        self.username = username
        self.password = password
        self.location = location
    }
}

public struct AuthenticateRequest: DTO {
    public var username: String
    public var password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

public struct UserDTO: DTO {
    public var id: Int64
    public var username: String
    public var location: Location?

    public init(id: Int64, username: String, location: Location?) {
        self.id = id
        self.username = username
        self.location = location
    }
}

public struct TokenDTO: DTO {
    public var userID: Int64
    public var token: String
    public var expires: Date

    public init(userID: Int64, token: String, expires: Date) {
        self.userID = userID
        self.token = token
        self.expires = expires
    }
}

public struct Authentication: DTO {
    public var user: UserDTO
    public var token: TokenDTO

    public init(user: UserDTO, token: TokenDTO) {
        self.user = user
        self.token = token
    }
}

public enum DeviceType: String, DTO {
    case iOS
    case web
}

public struct PushTokenDTO: DTO {
    public var token: String
    public var deviceType: DeviceType

    public init(token: String, deviceType: DeviceType) {
        self.token = token
        self.deviceType = deviceType
    }
}
