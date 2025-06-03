//
//  AuthorizationState.swift
//  Nice
//
//  Created by Harlan Haskins on 5/18/25.
//

/// Permission state for system authorizations (location, notifications)
/// Tracks the current status of user permissions
enum AuthorizationState {
    /// Permission status not yet determined
    case indeterminate
    /// User explicitly denied permission
    case denied
    /// User granted permission
    case allowed
}
