//
//  ContentView.swift
//  Nice
//
//  Created by Harlan Haskins on 5/4/25.
//

import NiceTypes
import SwiftUI

struct ContentView: View {
    @State var authenticator = Authenticator()
    var body: some View {
        ZStack {
            switch authenticator.authState {
            case .unauthenticated, .signingIn:
                SignInView(authenticator: authenticator)
            case .pendingRefresh:
                ProgressView()
            case .authenticated(let auth):
                MainView(auth: auth)
            }
        }
    }
}

#Preview {
    ContentView()
}
