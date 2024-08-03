import SwiftUI

struct StatusView: View {
    var connecting: Bool = false
    var errorMessage: String?
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "circlebadge.fill")
            Text(errorMessage ?? (connecting ? "Connecting..." : "Connected"))
        }
        .foregroundColor(errorMessage == nil ? (connecting ? .blue : .green) : .red)
        .padding(8)
    }
}

#Preview("Connected") {
    VStack {
        ZStack {
            Text("Some content")
        }
        .padding(64)
        .overlay(alignment: .bottomTrailing) {
            StatusView()
        }
    }
}
#Preview("Error") {
    @State var errorMessage = "There was some very bad error!"
    return VStack {
        ZStack {
            Text("Some content")
        }
        .padding(64)
        .overlay(alignment: .bottomTrailing) {
            StatusView(errorMessage: errorMessage)
        }
    }
}
#Preview("Connecting") {
    @State var connecting = true
    return VStack {
        ZStack {
            Text("Some content")
        }
        .padding(64)
        .overlay(alignment: .bottomTrailing) {
            StatusView(connecting: connecting)
        }
    }
}
