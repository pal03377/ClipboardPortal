import SwiftUI
import KeyboardShortcuts

struct GlobalKeyboardShortcutView: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Shortcut", name: .sendToFriend)
            Text("Paste from any app")
                .font(.footnote)
        }
    }
}

#Preview {
    GlobalKeyboardShortcutView()
}
