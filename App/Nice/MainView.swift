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
    enum WeatherUpdateState: Equatable {
        case noLocation
        case loading
        case forecast(Forecast, Location)
    }
    var controller: NiceController
    @State var weatherState: WeatherUpdateState = .noLocation
    @Binding var isSettingsOpen: Bool
    @Environment(\.presentToast) var presentToast
    @Environment(\.scenePhase) var scenePhase

    init(
        controller: NiceController,
        isSettingsOpen: Binding<Bool>
    ) {
        self.controller = controller
        self._isSettingsOpen = isSettingsOpen
        if controller.locationService.location != nil {
            weatherState = .loading
        }
    }

    var body: some View {
        VStack {
            ZStack {
                switch weatherState {
                case .noLocation:
                    Text("No location set. Nice needs location services to fetch your weather.")
                case .loading:
                    ProgressView()
                case .forecast(let forecast, let location):
                    WeatherPreview(location: location, forecast: forecast)
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
        .task(id: scenePhase) {
            await fetchWeather()

            switch scenePhase {
            case .active:
                controller.locationService.didBecomeActive()
            case .background, .inactive:
                controller.locationService.didBecomeInactive()
            @unknown default:
                break
            }
        }
        .task(id: controller.locationService.location) {
            await fetchWeather()
        }
        .task {
            do {
                try await controller.notificationService.performNotificationRegistration()
                controller.locationService.didBecomeActive()
            } catch {

            }

            await controller.locationService.updateLocation()
            await fetchWeather()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Settings", systemImage: "gear") {
                    isSettingsOpen = true
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 320)
    }

    func fetchWeather() async {
        do {
            guard let location = controller.locationService.location else { return }
            await controller.locationService.updateLocation()
            let forecast = try await controller.loadForecast()
            weatherState = .forecast(forecast, Location(location.coordinate))
        } catch {
            presentToast(.warning("Could not load weather: \(error)"))
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    var authenticator: Authenticator
    @State var isShowingDeleteConfirmation = false
    @State var isDeletingAccount: Bool = false
    @Environment(\.presentToast) var presentToast

    var body: some View {
        VStack {
            AsyncButton("Sign out") {
                do {
                    try await authenticator.signOut()
                    dismiss()
                } catch {
                    presentToast(.error("Failed to sign out: \(error)"))
                }
            }

            Button {
                isShowingDeleteConfirmation = true
            } label: {
                HStack {
                    if isDeletingAccount {
                        ProgressView()
                            .tint(nil)
                            .transition(.blurReplace)
                    }
                    Text("Delete account")
                }
            }
            .disabled(isDeletingAccount)
            .animation(.snappy, value: isDeletingAccount)
            .tint(.red)
        }
        .confirmationDialog(
            "Delete account?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    isDeletingAccount = true
                    defer { isDeletingAccount = false }
                    do {
                        try await authenticator.deleteAccount()
                        dismiss()
                    } catch {
                        presentToast(.error("Could not delete account: \(error)"))
                    }
                }
            }
        } message: {
            Text("This will permanently delete all information associated with your account and sign you out. This cannot be undone, but you may create a new account.")
        }
        .buttonStyle(ActionButtonStyle())
        .tint(.blue)
    }
}
