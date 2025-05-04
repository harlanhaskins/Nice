//
//  UserDTOs.swift
//  Nice
//
//  Created by Harlan Haskins on 5/4/25.
//

import Foundation

public protocol DTO: Codable, Sendable, Equatable {}

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
    public var id: Int
    public var username: String

    public init(id: Int, username: String) {
        self.id = id
        self.username = username
    }
}

public struct TokenDTO: DTO {
    public var userID: Int
    public var token: String
    public var expires: Date

    public init(userID: Int, token: String, expires: Date) {
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
