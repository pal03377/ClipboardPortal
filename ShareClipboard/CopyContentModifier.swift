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

struct CopyContentModifier: ViewModifier {
    var isButton: Bool
    var copyContent: String
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
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copyContent, forType: .string)
    }
}

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
    func copyContent(_ copyContent: String) -> some View {
        self.modifier(CopyContentModifier(isButton: false, copyContent: copyContent))
    }
}
extension Button {
    func copyContent(_ copyContent: String) -> some View {
        self.modifier(CopyContentModifier(isButton: true, copyContent: copyContent))
    }
}

#Preview {
    VStack {
        // Text button
        Button {} label: { Text("Copy") }
            .copyContent("Text to copy")
        // Image button
        Button {} label: { Image(systemName: "doc.on.doc") }
            .copyContent("Text to copy")
        // Pure text
        Text("Copyme")
            .copyContent("Text to copy")
    }
    .padding()
}