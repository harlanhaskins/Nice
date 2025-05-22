//
//  MainView.swift
//  Nice
//
//  Created by Harlan Haskins on 5/12/25.
//

import CoreLocationUI
import NiceTypes
import SwiftUI

struct MainView: View {
    @State var controller: NiceController
    @State var forecast: Forecast?
    var auth: Authentication

    init(auth: Authentication) {
        self.auth = auth
        self._controller = State(initialValue: NiceController(authentication: auth))
    }

    var body: some View {
        VStack {
            if let forecast {
                WeatherPreview(forecast: forecast)
            }

            if controller.notificationService.state == .indeterminate {
                Button {
                    controller.notificationService.registerForNotifications()
                } label: {
                    Text("Allow notifications")
                }
            }

            if controller.locationService.state == .indeterminate {
                Button {
                    controller.locationService.requestLocationUpdates()
                } label: {
                    Text("Allow location updates")
                }
            }
        }
        .buttonStyle(ActionButtonStyle())
        .task {
            do {
                forecast = try await controller.loadForecast()
            } catch {
                print("\(error)")
            }
        }
        .frame(maxWidth: 320)
    }
}

struct ActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled

    var background: AnyShapeStyle {
        if isEnabled {
            AnyShapeStyle(.tint)
        } else {
            AnyShapeStyle(.secondary)
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .foregroundStyle(.white)
            .font(.subheadline.bold())
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .opacity(isEnabled ? 1 : 0.75)
            .background(background, in: .capsule)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

#Preview {
    MainView(
        auth: Authentication(
            user: UserDTO(
                id: 1,
                username: "harlan",
                location: Location(latitude: 40, longitude: -73)
            ),
            token: TokenDTO(userID: 1, token: "", expires: .now)
        )
    )
}
