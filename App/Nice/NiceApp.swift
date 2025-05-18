//
//  NiceApp.swift
//  Nice
//
//  Created by Harlan Haskins on 5/4/25.
//

import SwiftUI

@main
struct NiceApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
