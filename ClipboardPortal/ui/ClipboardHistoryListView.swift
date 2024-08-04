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
    @EnvironmentObject var settingsStore: SettingsStore // Store for quickly setting the friend ID when receiving it
    @State var showingActions = false
    @State var isSetFriendCodePopupOpen = false

    var body: some View {
        HStack {
            Image(systemName: entry.received ? "arrow.down" : "arrow.up")
            Text("\(entry.content)")
                .lineLimit(4)
                .truncationMode(.tail)
            if entry.received && settingsStore.settingsData.receiverId == "\(entry.content)" {
                Image(systemName: "person.fill.checkmark")
                    .help("This is your friend's ID.")
            }
            else if case let ClipboardContent.text(textContent) = entry.content, looksLikeUserId(textContent), entry.received {
                Button("Set friend ID") {
                    settingsStore.settingsData.receiverId = textContent
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
        ClipboardHistoryEntry(content: .text("The next one looks like a user ID"), received: true),
        ClipboardHistoryEntry(content: .text("12345678"), received: true),
        ClipboardHistoryEntry(content: .text("87654321"), received: true),
    ]
    @State var settingsStore = SettingsStore.shared
    return VStack {
        Button("Add") {
            history.append(ClipboardHistoryEntry(content: .text("Some copied text \(history.count + 1)"), received: Bool.random()))
        }.padding()
        ClipboardHistoryListView(history: history) { _ in }
            .padding()
            .environmentObject(settingsStore)
            .onAppear {
                settingsStore.settingsData.receiverId = "87654321"
            }
    }
}
