//
//  LoadingState.swift
//  Nice
//
//  Created by Harlan Haskins on 5/22/25.
//

import Foundation

enum LoadingState<T> {
    case idle
    case loading
    case loaded(T)
    case failed(Error)

    var value: T? {
        guard case .loaded(let t) = self else {
            return nil
        }
        return t
    }

    var error: Error? {
        guard case .failed(let error) = self else {
            return nil
        }
        return error
    }
}

extension LoadingState: Sendable where T: Sendable {}
