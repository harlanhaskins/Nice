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
            .background(background, in: .capsule)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}
