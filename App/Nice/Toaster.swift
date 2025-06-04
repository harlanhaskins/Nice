//
//  Toaster.swift
//  studio
//
//  Created by Harlan Haskins on 2/14/23.
//

import Foundation
import SwiftUI

struct Toast: Identifiable {
    var id: UUID = UUID()
    var message: String
    var subtitle: String? = nil
    var image: Image? = nil
    var color: Color
    var textColor: Color

    static func error(
        _ error: String,
        subtitle: String? = nil,
        image: Image = Image(systemName: "multiply.circle.fill")
    ) -> Toast {
        Toast(message: error, subtitle: subtitle, image: image, color: .red, textColor: .white)
    }

    static func warning(
        _ warning: String,
        subtitle: String? = nil,
        image: Image = Image(systemName: "exclamationmark.triangle.fill")
    ) -> Toast {
        Toast(message: warning, subtitle: subtitle, image: image, color: .yellow, textColor: .white)
    }
}

@Observable
@MainActor
private final class Breadbox {
    var toasts = [Toast]()

    func addToast(_ toast: Toast) {
        toasts.append(toast)
    }

    func dismissToast(_ id: UUID) {
        toasts.removeAll { $0.id == id }
    }
}

@MainActor
public struct PresentToastAction {
    private var breadbox: Breadbox?

    fileprivate nonisolated init(breadbox: Breadbox?) {
        self.breadbox = breadbox
    }

    func callAsFunction(_ toast: Toast) {
        breadbox?.addToast(toast)
    }
}

private enum PresentToastKey: EnvironmentKey {
    static var defaultValue: PresentToastAction {
        PresentToastAction(breadbox: nil)
    }
}

extension EnvironmentValues {
    var presentToast: PresentToastAction {
        get { self[PresentToastKey.self] }
        set { self[PresentToastKey.self] = newValue }
    }
}

struct ToasterModifier: ViewModifier {
    @State private var breadbox = Breadbox()

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                VStack {
                    ForEach(breadbox.toasts.suffix(8)) { toast in
                        HStack {
                            toast.image?.font(.title2)
                            VStack {
                                Text(toast.message)
                                    .font(.subheadline)
                                if let subtitle = toast.subtitle {
                                    Text(subtitle)
                                }
                            }
                            .lineLimit(3)
                            .padding(.trailing, 12)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .background {
                            RoundedRectangle(cornerRadius: 9)
                                .fill(.thinMaterial)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 9)
                                        .fill(toast.color.gradient)
                                        .blendMode(.lighten)
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: 9)
                                        .stroke(Color.white.opacity(0.2))
                                }
                        }
                        .onTapGesture {
                            breadbox.dismissToast(toast.id)
                        }
                        .task {
                            try? await Task.sleep(for: .seconds(3))
                            breadbox.dismissToast(toast.id)
                        }
                        .transition(
                            .asymmetric(
                                insertion: .opacity.animation(.spring().delay(0.25)),
                                removal: .opacity.animation(.spring())))
                    }
                    .animation(.spring(), value: breadbox.toasts.count)
                }
            }
            .environment(\.presentToast, PresentToastAction(breadbox: breadbox))
    }
}
