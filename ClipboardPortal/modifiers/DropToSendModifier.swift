import SwiftUI

struct DropToSendModifier: ViewModifier {
    @State var targeted: Bool = false
    
    func body(content: Content) -> some View {
        Group {
            if targeted {
                content
                    .overlay {
                        ZStack {
                            Color.blue.opacity(0.4)
                            VStack {
                                Image(systemName: "arrow.up.circle")
                                Text("Drop to send")
                            }
                        }
                    }
            } else {
                content
            }
        }
        // Drop files
        .dropDestination(for: URL.self) { items, location in
            guard !items.isEmpty else { return false }
            Task {
                await ClipboardManager.shared.sendFileSystemItems(items)
            }
            return true
        } isTargeted: { targeted = $0 }
    }
}
