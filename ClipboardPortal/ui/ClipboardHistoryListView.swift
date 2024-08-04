import SwiftUI

struct ClipboardHistoryListView: View {
    var history: [ClipboardHistoryEntry]
    var onSend: (ClipboardContent) -> Void

    var body: some View {
        LazyVStack {
            ForEach(history.reversed(), id: \.receiveDate) { entry in
                ClipboardHistoryListEntryView(entry: entry) {
                    onSend(entry.content)
                }.padding(.vertical, 4)
            }
        }
    }
}

struct ClipboardHistoryListEntryView: View {
    var entry: ClipboardHistoryEntry
    var onSend: () -> Void
    @State var showingActions = false
    @State var isSetFriendCodePopupOpen = false

    var body: some View {
        HStack {
            Image(systemName: entry.received ? "arrow.down" : "arrow.up")
            Text("\(entry.content)")
                .lineLimit(4)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading) // Move action buttons to the right while not wrapping the text too early
            if case let ClipboardContent.text(textContent) = entry.content, SettingsStore.shared.settingsData.receiverId == textContent, entry.received {
                Image(systemName: "person.fill.checkmark")
                    .help("This is your friend's ID.")
            }
            else if case let ClipboardContent.text(textContent) = entry.content, looksLikeUserId(textContent), entry.received {
                Button("Set friend ID") {
                    SettingsStore.shared.settingsData.receiverId = textContent
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
            // Actions on hover
            HStack {
                Button {} label: { Image(systemName: "doc.on.doc") }
                    .copyContent(entry.content)
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
        ClipboardHistoryEntry(content: .text("Some copied text 1"), received: false),
        ClipboardHistoryEntry(content: .text("Some copied text 2"), received: false),
        ClipboardHistoryEntry(content: .text("This is a pretty long text that will break Lorem ipsum dolor sit amet"), received: false),
        ClipboardHistoryEntry(content: .text("The next one looks like a user ID"), received: true),
        ClipboardHistoryEntry(content: .text("12345678"), received: true),
        ClipboardHistoryEntry(content: .text("87654321"), received: true),
    ]
    return VStack {
        Button("Add") {
            history.append(ClipboardHistoryEntry(content: .text("Some copied text \(history.count + 1)"), received: Bool.random()))
        }.padding()
        ClipboardHistoryListView(history: history) { _ in }
            .frame(maxWidth: 300)
            .padding()
            .onAppear {
                SettingsStore.shared.settingsData.receiverId = "87654321"
            }
    }
}
