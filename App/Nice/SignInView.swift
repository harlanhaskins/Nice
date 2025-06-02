//
//  SignInView.swift
//  Nice
//
//  Created by Harlan Haskins on 5/4/25.
//

import SwiftUI

struct SignInView: View {
    enum FocusedField {
        case username
        case password
        case passwordConfirmation
    }
    enum AuthenticationType {
        case signIn
        case signUp
    }
    var controller: NiceController

    @State private var username: String = ""
    @State private var password: String = ""
    @State private var passwordConfirmation: String = ""
    @State private var authType: AuthenticationType = .signIn
    @Environment(\.presentToast) var presentToast
    @FocusState var field: FocusedField?

    var body: some View {
        VStack {
            TextField("Username", text: $username)
                .focused($field, equals: FocusedField.username)
                .autocorrectionDisabled()
            SecureField("Password", text: $password)
                .focused($field, equals: FocusedField.password)
            if authType == .signUp {
                SecureField("Confirm password", text: $passwordConfirmation)
                    .transition(.blurReplace.animation(.snappy))
                    .focused($field, equals: FocusedField.passwordConfirmation)
            }
            AsyncButton(authType == .signIn ? "Sign in" : "Sign up", action: authType == .signIn ? signIn : signUp)
                .buttonStyle(ActionButtonStyle())
                .tint(.blue)
        }
        .autocapitalization(.none)
        .onAppear {
            field = .username
        }
        .disabled(controller.authenticator.authState == .signingIn)
        .textFieldStyle(.roundedBorder)
        .frame(maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) {
            ZStack {
                if authType == .signIn {
                    Button("Create account", systemImage: "person.fill.badge.plus") {
                        authType = .signUp
                    }
                    .transition(.blurReplace.animation(.snappy))
                } else {
                    Button("Sign in instead", systemImage: "arrow.backward") {
                        authType = .signIn
                        passwordConfirmation = ""
                        field = .username
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

    func signUp() async {
        guard password == passwordConfirmation else {
            presentToast(.error("Passwords do not match"))
            return
        }

        do {
            _ = try await controller.signUp(
                username: username.lowercased(),
                password: password
            )
        } catch {
            presentToast(.error("Could not sign up: \(error.localizedDescription)"))
        }
    }

    func signIn() async {
        do {
            _ = try await controller.signIn(
                username: username.lowercased(),
                password: password
            )
        } catch {
            presentToast(.error("Could not sign in: \(error.localizedDescription)"))
        }
    }
}
