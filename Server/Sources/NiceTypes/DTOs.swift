//
//  UserDTOs.swift
//  Nice
//
//  Created by Harlan Haskins on 5/4/25.
//

import Foundation

/// Base protocol for all data transfer objects used in API communication
/// Ensures type safety, thread safety, and JSON serialization capability
public protocol DTO: Codable, Sendable, Equatable {}

/// Weather forecast data containing temperature, timing, and atmospheric conditions
/// Used for displaying current weather and determining if conditions are "nice"
public struct Forecast: DTO {
    /// Current temperature in Fahrenheit
    public var temperature: Double
    /// Perceived temperature accounting for humidity and wind
    public var feelsLike: Double
    /// Timestamp when forecast was generated
    public var currentTime: Date
    /// Time of sunset for the day
    public var sunset: Date
    /// Time of sunrise for the day
    public var sunrise: Date
    /// Cloud coverage percentage (0-100)
    public var clouds: Int

    /// Returns true when temperature is exactly 69°F (the "nice" condition)
    /// This is the core business logic that triggers notifications
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

/// Request payload for user registration
/// Contains credentials and optional initial location
public struct CreateUserRequest: DTO {
    /// Username (will be trimmed and lowercased)
    public var username: String
    /// Plain text password (must be ≥8 characters)
    public var password: String
    /// Optional initial location for weather forecasts
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

/// Request payload for user authentication
/// Contains login credentials for existing users
public struct AuthenticateRequest: DTO {
    /// Username (will be trimmed and lowercased)
    public var username: String
    /// Plain text password for verification
    public var password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

/// User representation for API responses
/// Contains public user information without sensitive data
public struct UserDTO: DTO {
    /// Unique user identifier
    public var id: Int64
    /// Display username (normalized)
    public var username: String
    /// User's current location for weather forecasts
    public var location: Location?

    public init(id: Int64, username: String, location: Location?) {
        self.id = id
        self.username = username
        self.location = location
    }
}

/// Authentication token data for API access
/// Used for Bearer token authentication on protected endpoints
public struct TokenDTO: DTO {
    /// ID of the user this token belongs to
    public var userID: Int64
    /// JWT token string for Authorization header
    public var token: String

    /// Provided for backwards compatibility with clients
    public var expires: Date = .now

    public init(userID: Int64, token: String) {
        self.userID = userID
        self.token = token
    }
}

/// Complete authentication response containing user data and access token
/// Returned on successful login/registration and token refresh
public struct Authentication: DTO {
    /// User information for the authenticated user
    public var user: UserDTO
    /// Access token for making authenticated API calls
    public var token: TokenDTO

    public init(user: UserDTO, token: TokenDTO) {
        self.user = user
        self.token = token
    }
}

/// Supported device types for push notifications
/// Determines which notification service to use (APNS vs VAPID)
public enum DeviceType: String, DTO {
    /// iOS devices using Apple Push Notification Service
    case iOS
    /// Web browsers using VAPID push notifications
    case web
}

/// Push notification token registration data
/// Associates a device token with a user for sending notifications
public struct PushTokenDTO: DTO {
    /// Device-specific push token (APNS token or VAPID subscription)
    public var token: String
    /// Type of device to determine notification service
    public var deviceType: DeviceType

    public init(token: String, deviceType: DeviceType) {
        self.token = token
        self.deviceType = deviceType
    }
}

/// Request payload for logout
/// Contains notification token to revoke on logout
public struct LogoutRequest: DTO {
    /// Notification token to delete
    public var notificationToken: String

    public init(notificationToken: String) {
        self.notificationToken = notificationToken
    }
}
