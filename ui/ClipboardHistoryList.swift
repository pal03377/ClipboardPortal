import SwiftUI

struct ClipboardHistoryList: View {
    var history: [ClipboardHistoryEntry]
    var onSend: (ClipboardContent) -> Void

    var body: some View {
        List(history.reversed(), id: \.self) { entry in
            ClipboardHistoryListEntry(entry: entry) {
                onSend(entry.clipboardContent)
            }.padding(.vertical, 4)
        }
        .scrollContentBackground(.hidden) // Transparent background instead of default darker background
        .frame(maxWidth: 400, maxHeight: 140)
    }
}

struct ClipboardHistoryListEntry: View {
    var entry: ClipboardHistoryEntry
    var onSend: () -> Void
    @State var showingActions = false

    var body: some View {
        HStack {
            Image(systemName: entry.received ? "arrow.down" : "arrow.up")
            Text(entry.clipboardContent.content)
                .lineLimit(4)
                .truncationMode(.tail)
            HStack {
                Spacer()
                Button {} label: { Image(systemName: "doc.on.doc") }
                    .copyContent(entry.clipboardContent)
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
}


#Preview {
    @State var history = [
        ClipboardHistoryEntry(clipboardContent: ClipboardContent(id: UUID(), type: .text, content: "Some copied text"), received: false),
        ClipboardHistoryEntry(clipboardContent: ClipboardContent(id: UUID(), type: .text, content: "Some copied text"), received: false),
        ClipboardHistoryEntry(clipboardContent: ClipboardContent(id: UUID(), type: .text, content: "Some copied text"), received: true),
        ClipboardHistoryEntry(clipboardContent: ClipboardContent(id: UUID(), type: .text, content: "Some copied text"), received: false),
    ]
    return ClipboardHistoryList(history: history) { _ in }
        .padding()
}
