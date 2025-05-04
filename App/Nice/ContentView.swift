//
//  ContentView.swift
//  Nice
//
//  Created by Harlan Haskins on 5/4/25.
//

import NiceTypes
import SwiftUI

struct ContentView: View {
    @State var controller = NiceController()
    var body: some View {
        ZStack {
            switch controller.authState {
            case .unauthenticated:
                SignInView(controller: controller)
            case .pendingRefresh:
                ProgressView()
            case .authenticated(let auth):
                MainView(user: auth.user)
            }
        }
    }
}

struct MainView: View {
    var user: UserDTO
    var body: some View {
        NavigationStack {
            Text("Welcome, \(user.username)")
        }
    }
}

#Preview {
    ContentView()
}
