//
//  File.swift
//  Nice
//
//  Created by Harlan Haskins on 5/18/25.
//

import Foundation

actor JobRunner {
    let weather: WeatherController
    var task: Task<Void, Error>?

    init(weather: WeatherController) {
        self.weather = weather
    }

    func start() {
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.weather.runWeatherJob()
                do {
                    try await Task.sleep(for: .seconds(15 * 60))
                } catch is CancellationError {
                    break
                } catch {
                    continue
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
