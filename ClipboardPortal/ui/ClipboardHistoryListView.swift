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
}


#Preview {
    @State var history = [
        ClipboardHistoryEntry(clipboardContent: ClipboardContent(id: UUID(), type: .text, content: "Some copied text 1"), received: false),
        ClipboardHistoryEntry(clipboardContent: ClipboardContent(id: UUID(), type: .text, content: "Some copied text 2"), received: false),
    ]
    return VStack {
        Button("Add") {
            history.append(ClipboardHistoryEntry(clipboardContent: ClipboardContent(id: UUID(), type: .text, content: "Some copied text \(history.count + 1)"), received: Bool.random()))
        }.padding()
        ClipboardHistoryListView(history: history) { _ in }
            .padding()
    }
}
