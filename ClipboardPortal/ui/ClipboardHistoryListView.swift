import SwiftUI

struct ClipboardHistoryListView: View {
    var history: [ClipboardHistoryEntry]
    var onSend: (ClipboardContent) -> Void

    var body: some View {
        LazyVStack {
            ForEach(history.reversed(), id: \.self) { entry in
                ClipboardHistoryListEntryView(entry: entry) {
                    onSend(entry.clipboardContent)
                }.padding(.vertical, 4)
            }
        }
    }
}

struct ClipboardHistoryListEntryView: View {
    var entry: ClipboardHistoryEntry
    var onSend: () -> Void
    @EnvironmentObject var settingsStore: SettingsStore // Store for quickly setting the friend ID when receiving it
    @State var showingActions = false
    @State var isSetFriendCodePopupOpen = false

    var body: some View {
        HStack {
            Image(systemName: entry.received ? "arrow.down" : "arrow.up")
            Text(entry.clipboardContent.content)
                .lineLimit(4)
                .truncationMode(.tail)
            if entry.received && settingsStore.settingsData.receiverId == entry.clipboardContent.content {
                Image(systemName: "person.fill.checkmark")
                    .help("This is your friend's ID.")
            }
            else if entry.received &&  looksLikeUserId(entry.clipboardContent.content) {
                Button("Set friend ID") {
                    settingsStore.settingsData.receiverId = entry.clipboardContent.content
                }
                Button { isSetFriendCodePopupOpen = true } label: {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(PlainButtonStyle())
                .popover(isPresented: $isSetFriendCodePopupOpen) {
                    Text("Change the friend ID setting to this ID")
                        .padding()
                }
            }
            HStack {
                Spacer()
                Button {} label: { Image(systemName: "doc.on.doc") }
                    .copyContent(entry.clipboardContent)
                    .buttonStyle(PlainButtonStyle())
                Button { // Resend button
                    onSend()
                } label: { Image(systemName: "arrow.up.circle") }
                    .buttonStyle(PlainButtonStyle())
            }
            .isHidden(!showingActions)
        }
        .onHover { hovering in
            showingActions = hovering
        }
    }
    
    func looksLikeUserId(_ contentString: String) -> Bool {
        return contentString.count == 8 && contentString.allSatisfy({ $0.isNumber }) // 8-digit number?
    }
}


#Preview {
    @State var history = [
        ClipboardHistoryEntry(clipboardContent: ClipboardContent(id: UUID(), type: .text, content: "Some copied text 1"), received: false),
        ClipboardHistoryEntry(clipboardContent: ClipboardContent(id: UUID(), type: .text, content: "Some copied text 2"), received: false),
        ClipboardHistoryEntry(clipboardContent: ClipboardContent(id: UUID(), type: .text, content: "The next one looks like a user ID"), received: true),
        ClipboardHistoryEntry(clipboardContent: ClipboardContent(id: UUID(), type: .text, content: "12345678"), received: true),
        ClipboardHistoryEntry(clipboardContent: ClipboardContent(id: UUID(), type: .text, content: "87654321"), received: true),
    ]
    @State var settingsStore = SettingsStore()
    return VStack {
        Button("Add") {
            history.append(ClipboardHistoryEntry(clipboardContent: ClipboardContent(id: UUID(), type: .text, content: "Some copied text \(history.count + 1)"), received: Bool.random()))
        }.padding()
        ClipboardHistoryListView(history: history) { _ in }
            .padding()
            .environmentObject(settingsStore)
            .onAppear {
                settingsStore.settingsData.receiverId = "87654321"
            }
    }
}
