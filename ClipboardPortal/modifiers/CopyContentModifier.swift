import SwiftUI
import AppKit

extension AnyTransition {
    static var fadeOutScaleUpOnRemove: AnyTransition {
        .asymmetric(
            insertion: .identity,
            removal: .scale(scale: 1.5).combined(with: .opacity)
        )
    }
}

@available(macOS 14.0, *)
struct CopyContentModifier: ViewModifier {
    var isButton: Bool
    var copyContent: ClipboardContent
    @State var copyAnimationPlaying: Bool = false
    
    func body(content: Content) -> some View {
        if isButton {
            content
                .buttonStyle(AdditionalActionButtonStyle(additionalAction: {
                    copyClick()
                }))
                .overlay(
                    Group {
                        if copyAnimationPlaying {
                            content
                                .buttonStyle(AdditionalActionButtonStyle(additionalAction: {}))
                                .transition(.fadeOutScaleUpOnRemove)
                        }
                    }
                )
        } else {
            content
                .simultaneousGesture(
                    TapGesture().onEnded {
                        copyClick()
                    }
                )
                .overlay(
                    Group {
                        if copyAnimationPlaying {
                            content
                                .transition(.fadeOutScaleUpOnRemove)
                        }
                    }
                )
        }
        /*
        .task { // For debugging the animation
            while true {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                DispatchQueue.main.async { self.copyClick()  }
            }
        }
         */
    }
    
    private func copyClick() {
        self.copyAnimationPlaying = true
        withAnimation {
            self.copyAnimationPlaying = false
        }
        copyContent.copyToClipboard()
    }
}

@available(macOS 14.0, *)
struct AdditionalActionButtonStyle: ButtonStyle {
    var additionalAction: () -> ()
    public static func applyStyles(_ label: ButtonStyleConfiguration.Label) -> some View {
        label
    }
    public func makeBody(configuration: Configuration) -> some View {
        Self.applyStyles(configuration.label)
            .onChange(of: configuration.isPressed) { _, newValue in
                if newValue {
                    additionalAction()
                }
            }
    }
}

// Completely hide opacity: 0 View overlay for Accessibility and keyboard focus
extension View {
    @ViewBuilder func isHidden(_ hidden: Bool) -> some View {
        if hidden {
            self.hidden()
        } else {
            self
        }
    }
}

extension View {
    func copyContent(_ copyContent: ClipboardContent) -> some View {
        if #available(macOS 14, *) {
            return self.modifier(CopyContentModifier(isButton: false, copyContent: copyContent))
        } else {
            return self
        }
    }
}
extension Button {
    func copyContent(_ copyContent: ClipboardContent) -> some View {
        if #available(macOS 14, *) {
            return self.modifier(CopyContentModifier(isButton: true, copyContent: copyContent))
        } else {
            return self
        }
    }
}

#Preview {
    VStack {
        // Text button
        Button {} label: { Text("Copy") }
            .copyContent(.text("Text to copy"))
        // Image button
        Button {} label: { Image(systemName: "doc.on.doc") }
            .copyContent(.text("Text to copy"))
        // Pure text
        Text("Copyme")
            .copyContent(.text("Text to copy"))
    }
    .padding()
}
