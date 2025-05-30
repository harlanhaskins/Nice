//
//  SignInView.swift
//  Nice
//
//  Created by Harlan Haskins on 5/4/25.
//

import SwiftUI

struct SignInView: View {
    enum AuthenticationType {
        case signIn
        case signUp
    }
    var authenticator: Authenticator

    @State private var username: String = ""
    @State private var password: String = ""
    @State private var passwordConfirmation: String = ""
    @State private var authType: AuthenticationType = .signIn

    var body: some View {
        VStack {
            TextField("Username", text: $username)
                .autocorrectionDisabled()
            SecureField("Password", text: $password)
            if authType == .signUp {
                SecureField("Confirm password", text: $passwordConfirmation)
                    .transition(.blurReplace.animation(.snappy))
            }
            Button(authType == .signIn ? "Sign in" : "Sign up", action: authType == .signIn ? signIn : signUp)
                .buttonStyle(ActionButtonStyle())
                .tint(.blue)
        }
        .disabled(authenticator.authState == .signingIn)
        .textFieldStyle(.roundedBorder)
        .frame(maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) {
            ZStack {
                if authType == .signIn {
                    Button("Create account") {
                        authType = .signUp
                    }
                    .transition(.blurReplace.animation(.snappy))
                } else {
                    Button("Sign in instead") {
                        authType = .signIn
                        passwordConfirmation = ""
                    }
                    .transition(.blurReplace.animation(.snappy))
                }
            }
            .buttonStyle(ActionButtonStyle())
            .tint(.blue)
        }
        .animation(.snappy, value: authType)
        .frame(maxWidth: 320)
        .padding()
    }

    func signUp() {
        guard password == passwordConfirmation else {
            print("Passwords do not match")
            return
        }

        Task {
            do {
                try await authenticator.signUp(
                    username: username.lowercased(),
                    password: password
                )
            } catch {
                print(error)
            }
        }
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
