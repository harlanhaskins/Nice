//
//  WeatherPreview.swift
//  Nice
//
//  Created by Harlan Haskins on 5/21/25.
//

import NiceTypes
import SwiftUI

struct WeatherPreview: View {
    var forecast: Forecast

    var body: some View {
        GroupBox {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                        Text("\(forecast.isNice ? "😎" : "\(Int(forecast.temperature))º")")
                            .font(.system(size: 60))
                            .fontWeight(.thin)
                    Gauge(value: Double(forecast.clouds), in: 0...100) {
                        Text("\(forecast.clouds)%")
                    } currentValueLabel: {
                        Image(systemName: "cloud.fill")
                            .foregroundStyle(.tertiary)
                            .offset(y: -3)
                            .scaleEffect(0.9)
                    }
                    .gaugeStyle(.accessoryCircular)
                    .offset(y: 10)
                }
                VStack(spacing: 10) {
                    Text("\(Text("feels like").foregroundStyle(.secondary)) \(Int(forecast.feelsLike))º")
                        .font(.caption)
                    Grid {
                        GridRow {
                            Image(systemName: "sunrise.fill")
                            Text("\(forecast.sunrise, format: .dateTime.hour().minute())")
                                .gridColumnAlignment(.leading)
                        }
                        GridRow {
                            Image(systemName: "sunset.fill")
                            Text("\(forecast.sunset, format: .dateTime.hour().minute())")
                                .gridColumnAlignment(.leading)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview {
    WeatherPreview(
        forecast: Forecast(
            temperature: 69,
            feelsLike: 67,
            currentTime: .now,
            sunset: .now - 8 * 60 * 60,
            sunrise: .now + 8 * 60 * 60,
            clouds: 79
        )
    )
}
