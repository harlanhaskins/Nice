//
//  ActionButtonStyle.swift
//  Nice
//
//  Created by Harlan Haskins on 5/30/25.
//

import SwiftUI

struct ActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled

    var background: AnyShapeStyle {
        if isEnabled {
            AnyShapeStyle(.tint)
        } else {
            AnyShapeStyle(.secondary)
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .foregroundStyle(.white)
            .font(.subheadline.bold())
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .opacity(isEnabled ? 1 : 0.75)
            .frame(minHeight: 44)
            .background(background, in: .capsule)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

struct AsyncButton<Content: View>: View {
    var action: @MainActor () async -> Void
    var label: Content

    @State private var isExecuting: Bool = false

    init(
        _ title: LocalizedStringKey,
        action: @escaping @MainActor () async -> Void
    ) where Content == Text {
        self.init(action: action) {
            Text(title)
        }
    }

    init(
        _ title: some StringProtocol,
        action: @escaping @MainActor () async -> Void
    ) where Content == Text {
        self.init(action: action) {
            Text(title)
        }
    }

    init(
        _ title: LocalizedStringKey,
        systemImage: String,
        action: @escaping @MainActor () async -> Void
    ) where Content == Label<Text, Image> {
        self.init(action: action) {
            Label(title, systemImage: systemImage)
        }
    }

    init(
        action: @escaping @MainActor () async -> Void,
        @ViewBuilder label: () -> Content
    ) {
        self.label = label()
        self.action = action
    }

    var body: some View {
        Button {
            guard !isExecuting else { return }
            isExecuting = true
            Task {
                await action()
                isExecuting = false
            }
        } label: {
            HStack {
                if isExecuting {
                    ProgressView()
                        .transition(.blurReplace)
                        .tint(nil)
                }
                label
            }
        }
        .disabled(isExecuting)
        .animation(.snappy, value: isExecuting)
    }
}
