//
//  SignUpView.swift
//  Nice
//
//  Created by Harlan Haskins on 5/21/25.
//

import SwiftUI

struct SignUpView: View {
    var authenticator: Authenticator

    @State private var username: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""

    var body: some View {
        VStack {
            TextField("Username", text: $username)
                .autocorrectionDisabled()
            SecureField("Password", text: $password)
            SecureField("Confirm password", text: $confirmPassword)

            Button("Create account", action: signUp)
                .buttonStyle(ActionButtonStyle())
                .tint(.blue)
        }
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: 320)
        .padding()
    }

    func signUp() {
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
