import SwiftUI

struct CommandVView: View {
    var onPress: () -> Void
    var minHeight: CGFloat = 120
    @State var isFlat = false

    var body: some View {
        ZStack {
            Button { onPress() } label: {
                HStack(spacing: 10) {
                    KeyView(symbol: "command", isFlat: isFlat)
                    KeyView(text: "V", isFlat: isFlat)
                }
                .scaleEffect(isFlat ? CGSize(width: 0.98, height: 0.98) : CGSize(width: 1, height: 1))
            }
            .focusable(false) // Hide ugly focus border that is not needed because keyboard users can press Cmd+V directly
            .buttonStyle(PlainButtonStyle())
            .simultaneousGesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in isFlat = true } // Flat while pressed
                .onEnded { _ in
                    isFlat = false // Lift when released
                }
            )
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: minHeight) // Prevent squeezing the button too much
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
