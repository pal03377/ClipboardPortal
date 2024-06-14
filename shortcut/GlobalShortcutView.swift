import SwiftUI
import KeyboardShortcuts

struct GlobalShortcutView: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Global paste shortcut", name: .sendToFriend)
        }
    }
}

#Preview {
    GlobalShortcutView()
}
