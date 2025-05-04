//
//  MockDateProvider.swift
//  Nice
//
//  Created by Harlan Haskins on 5/4/25.
//

import Foundation
@testable import Nice
import Synchronization

final class MockDateProvider: DateProviding {
    let currentDate = Mutex<Date>(.now)

    var now: Date {
        get {
            currentDate.withLock { $0 }
        }
        set {
            currentDate.withLock { $0 = newValue }
        }
    }

    init(now: Date = .now) {
        self.currentDate.withLock { $0 = now }
    }

    func advanceTime(by seconds: TimeInterval) {
        self.currentDate.withLock {
            $0 = Calendar.current.date(byAdding: .second, value: Int(seconds), to: $0)!
        }
    }

    var newExpirationDate: Date {
        Calendar.current.date(byAdding: .day, value: 14, to: now)!
    }
}
