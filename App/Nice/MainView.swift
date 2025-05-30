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
    @State var isSettingsOpen: Bool = false
    @Environment(\.presentToast) var presentToast

    init(auth: Authentication, authenticator: Authenticator) {
        self.auth = auth
        self._controller = State(
            initialValue: NiceController(
                authentication: auth,
                authenticator: authenticator
            )
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if let forecast {
                    WeatherPreview(forecast: forecast)
                } else {
                    ProgressView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gear") {
                        isSettingsOpen = true
                    }
                    .labelStyle(.iconOnly)
                }
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
                presentToast(.warning("Could not load weather: \(error)"))
            }
        }
        .sheet(isPresented: $isSettingsOpen) {
            SettingsView(controller: controller)
                .padding()
                .presentationDetents([.height(160)])
        }
        .frame(maxWidth: 320)
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    var controller: NiceController
    @State var isShowingDeleteConfirmation = false
    @Environment(\.presentToast) var presentToast

    var body: some View {
        VStack {
            Button("Sign out") {
                Task {
                    do {
                        try await controller.signOut()
                        dismiss()
                    } catch {
                        presentToast(.error("Failed to sign out: \(error)"))
                    }
                }
            }
            Button("Delete account", role: .destructive) {
                isShowingDeleteConfirmation = true
            }
            .tint(.red)
        }
        .confirmationDialog("Delete account", isPresented: $isShowingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                Task {
                    do {
                        try await controller.signOut()
                        dismiss()
                    } catch {
                        presentToast(.error("Could not delete account: \(error)"))
                    }
                }
            }
        }
        .buttonStyle(ActionButtonStyle())
        .tint(.blue)
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
        ),
        authenticator: Authenticator()
    )
}
