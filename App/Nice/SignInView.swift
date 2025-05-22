//
//  SignInView.swift
//  Nice
//
//  Created by Harlan Haskins on 5/4/25.
//

import SwiftUI

struct SignInView: View {
    var authenticator: Authenticator

    @State private var username: String = ""
    @State private var password: String = ""

    var body: some View {
        VStack {
            TextField("Username", text: $username)
                .autocorrectionDisabled()
            SecureField("Password", text: $password)
            Button("Sign in", action: signIn)
                .buttonStyle(ActionButtonStyle())
                .tint(.blue)
        }
        .disabled(authenticator.authState == .signingIn)
        .textFieldStyle(.roundedBorder)
        .frame(maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) {
            Button("Create account", action: signIn)
                .buttonStyle(ActionButtonStyle())
                .tint(.blue)
        }
        .frame(maxWidth: 320)
        .padding()
    }

    func signIn() {
        Task {
            do {
                try await authenticator.signIn(
                    username: username.lowercased(),
                    password: password
                )
            } catch {
                print(error)
            }
        }
    }
}
