//
//  WeatherPreview.swift
//  Nice
//
//  Created by Harlan Haskins on 5/21/25.
//

import MapKit
import NiceTypes
import SwiftUI

struct WeatherPreview: View {
    var location: Location
    var forecast: Forecast

    var region: MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
            latitudinalMeters: 200,
            longitudinalMeters: 100
        )
    }

    var temperature: some View {
        VStack(spacing: 0) {
            Text("\(forecast.isNice ? "😎" : "\(Int(forecast.temperature))º")")
                .font(.system(size: 80))
            Text("\(Text("feels like").foregroundStyle(.secondary)) \(Int(forecast.feelsLike))º")
                .font(.caption)
                .offset(y: -20)
        }
    }

    var sunIndicators: some View {
        VStack {
            Text("\(Image(systemName: "sunrise.fill"))\(forecast.sunrise, format: .dateTime.hour().minute())")
            Text("\(Image(systemName: "sunset.fill"))\(forecast.sunset, format: .dateTime.hour().minute())")
        }
        .foregroundStyle(.secondary)
    }

    var clouds: some View {
        Gauge(value: Double(forecast.clouds), in: 0...100) {
            Text("\(forecast.clouds)%")
        } currentValueLabel: {
            Image(systemName: "cloud.fill")
                .foregroundStyle(.tertiary)
                .offset(y: -3)
                .scaleEffect(0.9)
        }
        .gaugeStyle(.accessoryCircular)
    }

    var map: some View {
        Map(position: .constant(.region(region)))
            .aspectRatio(5/2, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 13))
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .fill(.clear)
            }
    }

    var body: some View {
        GroupBox {
            HStack {
                temperature
                HStack(spacing: 10) {
                    clouds
                    sunIndicators
                }
            }
            map
        }
        .fontDesign(.rounded)
    }
}

#Preview {
    WeatherPreview(
        location: Location(latitude: 40.74367, longitude: -73.99519),
        forecast: Forecast(
            temperature: 64,
            feelsLike: 67,
            currentTime: .now,
            sunset: .now - 8 * 60 * 60,
            sunrise: .now + 8 * 60 * 60,
            clouds: 79
        )
    )
}
