//
//  LoadingState.swift
//  Nice
//
//  Created by Harlan Haskins on 5/22/25.
//

import Foundation

/// Generic state enum for async operations with loading indicators
/// Provides type-safe state management for UI components
enum LoadingState<T> {
    /// Initial state before any operation
    case idle
    /// Operation in progress
    case loading
    /// Operation completed successfully with result
    case loaded(T)
    /// Operation failed with error
    case failed(Error)

    /// Extract value if in loaded state
    var value: T? {
        guard case .loaded(let t) = self else {
            return nil
        }
        return t
    }

    /// Extract error if in failed state
    var error: Error? {
        guard case .failed(let error) = self else {
            return nil
        }
        return error
    }
}

extension LoadingState: Sendable where T: Sendable {}
