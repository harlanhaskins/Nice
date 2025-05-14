//
//  MainView.swift
//  Nice
//
//  Created by Harlan Haskins on 5/12/25.
//

import NiceTypes
import SwiftUI

struct MainView: View {
    @State var controller: NiceController
    @State var niceness: String?
    var auth: Authentication

    init(auth: Authentication) {
        self.auth = auth
        self._controller = State(initialValue: NiceController(authentication: auth))
    }

    var body: some View {
        NavigationStack {
            if let niceness {
                Text(niceness)
            }
            Text("Welcome, \(auth.user.username)")
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
