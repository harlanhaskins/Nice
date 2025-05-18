//
//  File.swift
//  Nice
//
//  Created by Harlan Haskins on 5/18/25.
//

import Foundation

actor JobRunner {
    let nice: NiceController
    var task: Task<Void, Error>?

    init(nice: NiceController) {
        self.nice = nice
    }

    func start() {
        task = Task { [weak self] in
            while true {
                guard let self else { return }
                await self.nice.runWeatherJob()
                try await Task.sleep(for: .seconds(15 * 60))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
