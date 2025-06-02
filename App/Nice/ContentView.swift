//
//  ContentView.swift
//  Nice
//
//  Created by Harlan Haskins on 5/4/25.
//

import NiceTypes
import SwiftUI

struct ContentView: View {
    @State var controller: NiceController
    @State var isSettingsOpen: Bool = false

    init() {
        self._controller = State(initialValue: NiceController())
    }

    var body: some View {
        NavigationStack {
            switch controller.authenticator.authState {
            case .unauthenticated, .signingIn:
                SignInView(controller: controller)
                    .transition(.scale(scale: 0.95).combined(with: .opacity).animation(.snappy))
            case .pendingRefresh:
                ProgressView()
            case .authenticated:
                MainView(controller: controller, isSettingsOpen: $isSettingsOpen)
                    .transition(.scale(scale: 0.95).combined(with: .opacity).animation(.snappy))
            }
        }
        .sheet(isPresented: $isSettingsOpen) {
            SettingsView(authenticator: controller.authenticator)
                .padding()
                .presentationDetents([.height(160)])
        }
        .modifier(ToasterModifier())
    }
}

#Preview {
    ContentView()
}
