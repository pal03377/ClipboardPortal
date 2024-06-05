import SwiftUI

struct ClipboardHistoryList: View {
    var history: [ClipboardHistoryEntry]
    var onSend: (ClipboardContent) -> Void

    var body: some View {
        ScrollViewReader { scrollView in
            ScrollView(.vertical) {
                LazyVStack {
                    ForEach(history.reversed(), id: \.self) { entry in
                        ClipboardHistoryListEntry(entry: entry) {
                            onSend(entry.clipboardContent)
                        }.padding(.vertical, 4)
                    }
                }
                .onAppear { // When a new history entry is added
                    guard let firstEntry = history.first else { return }
                    scrollView.scrollTo(firstEntry) // Scroll up to see the newest entry
                }
                .scrollContentBackground(.hidden) // Transparent background instead of default darker background
            }
        }.frame(maxWidth: 400, maxHeight: 140)
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
        ClipboardHistoryList(history: history) { _ in }
            .padding()
    }
}
