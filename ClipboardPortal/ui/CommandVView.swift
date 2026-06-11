import SwiftUI

struct CommandVView: View {
    var onPress: () -> Void
    var minHeight: CGFloat = 120
    @State var isFlat = false

    var body: some View {
        ZStack {
            HStack(spacing: 10) {
                KeyView(symbol: "command", isFlat: isFlat)
                KeyView(text: "V", isFlat: isFlat)
            }
            .scaleEffect(isFlat ? CGSize(width: 0.98, height: 0.98) : CGSize(width: 1, height: 1))
            .overlay {
                WindowDraggableClickView(
                    onClick: onPress,
                    onPressChanged: { isFlat = $0 }
                )
                .accessibilityLabel("Send clipboard")
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: minHeight) // Prevent squeezing the button too much
    }
}

private struct WindowDraggableClickView: NSViewRepresentable {
    var onClick: () -> Void
    var onPressChanged: (Bool) -> Void

    func makeNSView(context: Context) -> DraggableClickNSView {
        DraggableClickNSView(onClick: onClick, onPressChanged: onPressChanged)
    }

    func updateNSView(_ nsView: DraggableClickNSView, context: Context) {
        nsView.onClick = onClick
        nsView.onPressChanged = onPressChanged
    }

    final class DraggableClickNSView: NSView {
        var onClick: () -> Void
        var onPressChanged: (Bool) -> Void
        private var mouseDownLocation: NSPoint?
        private var didDrag = false

        init(onClick: @escaping () -> Void, onPressChanged: @escaping (Bool) -> Void) {
            self.onClick = onClick
            self.onPressChanged = onPressChanged
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var acceptsFirstResponder: Bool { true }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func mouseDown(with event: NSEvent) {
            didDrag = false
            mouseDownLocation = event.locationInWindow
            onPressChanged(true)
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window else { return }
            if !didDrag, let mouseDownLocation {
                let distance = hypot(event.locationInWindow.x - mouseDownLocation.x, event.locationInWindow.y - mouseDownLocation.y)
                guard distance >= 3 else { return }
            }

            didDrag = true
            onPressChanged(false)
            window.performDrag(with: event)
        }

        override func mouseUp(with event: NSEvent) {
            onPressChanged(false)
            mouseDownLocation = nil

            guard !didDrag else { return }
            onClick()
        }
    }
}

struct MediaControlsView: View {
    var width: CGFloat = 400
    var onPress: (MediaCommand) -> Void

    private var visibleCommands: [MediaCommand] {
        MediaCommand.allCases.filter { command in
            switch command {
            case .volumeDown, .volumeUp:
                return width >= 400
            case .previousTrack:
                return width >= 300
            case .playPause, .nextTrack:
                return true
            }
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(visibleCommands, id: \.self) { command in
                Button {
                    onPress(command)
                } label: {
                    Image(systemName: command.systemImageName)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 22)
                }
                .help(command.description)
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .focusable(false)
            }
        }
        .frame(maxWidth: .infinity, alignment: width < 300 ? .leading : .center)
        .padding(.leading, width < 300 ? 8 : 0)
    }
}

struct KeyView: View {
    var symbol: String?
    var text: String?
    var isFlat: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(gradient: Gradient(colors: [Color(hue: 0, saturation: 0, brightness: isFlat ? 0.12 : 0.2), Color(hue: 0, saturation: 0, brightness: isFlat ? 0.12 : 0.04)]),
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing)
                )
                .frame(width: 60, height: 60)
                .shadow(color: isFlat ? Color.clear : Color.black.opacity(0.4), radius: 10, x: 5, y: 5)

            if let symbol = symbol {
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
            }
            
            if let text = text {
                Text(text)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white) // Text needs to be slightly larger to appear the same size
            }
        }
    }
}

#Preview {
    CommandVView() {}
        .frame(width: 400, height: 300)
        .padding()
}
