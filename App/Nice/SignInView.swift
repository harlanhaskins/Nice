//
//  SignInView.swift
//  Nice
//
//  Created by Harlan Haskins on 5/4/25.
//

import SwiftUI

struct SignInView: View {
    var controller: NiceController
    @State private var username: String = "harlan"
    @State private var password: String = "helloworld"

    var body: some View {
        VStack {
            TextField("Username", text: $username)
                .autocorrectionDisabled()
            SecureField("Password", text: $password)
            Button("Sign in", action: signIn)
            .buttonStyle(.borderedProminent)
            .disabled(username.isEmpty || password.count < 8)
        }
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: 320)
        .padding()
    }

    func signIn() {
        Task {
            do {
                try await controller.signIn(
                    username: username.lowercased(),
                    password: password
                )
            } catch {
                print(error)
            }
        }
    }
}

#Preview {
    @Previewable @State var controller = NiceController()
    SignInView(controller: controller)
}
