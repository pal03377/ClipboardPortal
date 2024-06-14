import SwiftUI
import KeyboardShortcuts

struct GlobalShortcutView: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Shortcut", name: .sendToFriend)
            Text("Paste from any app")
                .font(.footnote)
        }
    }
}

#Preview {
    GlobalShortcutView()
}
