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
    @State var niceness: Niceness?
    var auth: Authentication

    init(auth: Authentication) {
        self.auth = auth
        self._controller = State(initialValue: NiceController(authentication: auth))
    }

    var body: some View {
        NavigationStack {
            if let niceness {
                Text(niceness.isNice ? "😎" : "😐")
                    .font(.largeTitle)
            }
            Text("Welcome, \(auth.user.username)")

            Button("Register for notifications") {
                do {
                    try controller.registerForNotifications()
                } catch {
                    print("Failed")
                }
            }

            LocationButton {
                do {
                    try controller.fetchWeather()
                } catch {
                    print("Failed")
                }

                Task {
                    do {
                        niceness = try await controller.loadNiceness()
                    } catch {
                        print("\(error)")
                    }
                }
            }
            .clipShape(.capsule)
        }
        .task {
            do {
                niceness = try await controller.loadNiceness()
            } catch {
                print("\(error)")
            }
        }
    }
}
