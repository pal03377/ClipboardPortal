import SwiftUI

struct CommandV: View {
    var onPress: () -> Void
    @State var isFlat = false

    var body: some View {
        Button { onPress() } label: {
            HStack(spacing: 10) {
                KeyView(symbol: "command", isFlat: isFlat)
                KeyView(text: "V", isFlat: isFlat)
            }
            .scaleEffect(isFlat ? CGSize(width: 0.98, height: 0.98) : CGSize(width: 1, height: 1))
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in isFlat = true } // Flat while pressed
            .onEnded { _ in
                isFlat = false // Lift when released
            }
        )
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
    CommandV() {}
        .padding()
}
