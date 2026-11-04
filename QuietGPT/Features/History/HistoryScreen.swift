import SwiftData
import SwiftUI

struct HistoryScreen: View {
    var controller: ChatController
    var onOpen: (Conversation) -> Void
    var onNew: () -> Void

    @Environment(\.palette) private var palette
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]
    @State private var search = ""
    @State private var renaming: Conversation?
    @State private var newTitle = ""

    var body: some View {
        ZStack(alignment: .top) {
            palette.background.ignoresSafeArea()

            LiquidField(mode: .drift, mask: .fadeDown)
                .frame(height: 300)
                .ignoresSafeArea(edges: .top)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Chats")
                        .font(QuietGPTFont.largeTitle)
                        .foregroundStyle(palette.text)
                    Spacer()
                    Button(action: onNew) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(CircleIconButtonStyle(filled: true))
                    .accessibilityLabel("New chat")
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)

                SearchField(text: $search)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                if filtered.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
        }
        .alert("Rename chat", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $newTitle)
            Button("Save") {
                let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if let renaming, !title.isEmpty {
                    renaming.title = title
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    private var filtered: [Conversation] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return conversations }
        return conversations.filter {
            $0.title.localizedStandardContains(query) || $0.messages.contains { $0.text.localizedStandardContains(query) }
        }
    }

    private var list: some View {
        List {
            ForEach(HistoryGroup.group(filtered)) { group in
                Section {
                    ForEach(group.conversations) { conversation in
                        Button {
                            onOpen(conversation)
                        } label: {
                            HistoryRow(conversation: conversation)
                        }
                        .buttonStyle(PressableStyle(scale: 0.98))
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                        .listRowSeparatorTint(palette.line)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                withAnimation(Motion.spring) { controller.delete(conversation) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button("Rename", systemImage: "pencil") {
                                newTitle = conversation.title
                                renaming = conversation
                            }
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                withAnimation(Motion.spring) { controller.delete(conversation) }
                            }
                        }
                    }
                } header: {
                    Text(group.title)
                        .font(QuietGPTFont.footnote)
                        .foregroundStyle(palette.text3)
                        .textCase(nil)
                        .padding(.leading, 4)
                }
                .listSectionSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .animation(Motion.spring, value: filtered.map(\.id))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Text(search.isEmpty ? "No chats yet" : "Nothing found")
                .font(QuietGPTFont.title)
                .foregroundStyle(palette.text)
            Text(search.isEmpty ? "Your chats will live here, only on this iPhone." : "Try other words.")
                .font(QuietGPTFont.subheadline)
                .foregroundStyle(palette.text2)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .transition(.blurReplace)
    }
}

private struct HistoryRow: View {
    let conversation: Conversation

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(conversation.title)
                    .font(QuietGPTFont.body)
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                Spacer(minLength: 12)
                Text(conversation.updatedAt.quietGPTShortLabel)
                    .font(QuietGPTFont.monoSmall)
                    .foregroundStyle(palette.text3)
            }
            Text(conversation.preview)
                .font(QuietGPTFont.subheadline)
                .foregroundStyle(palette.text2)
                .lineLimit(1)
        }
        .padding(.vertical, 11)
        .contentShape(.rect)
    }
}

private struct SearchField: View {
    @Binding var text: String

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(palette.text2)
            TextField("Search", text: $text)
                .font(QuietGPTFont.body)
                .foregroundStyle(palette.text)
                .tint(palette.accent)
                .submitLabel(.search)
            if !text.isEmpty {
                Button {
                    withAnimation(Motion.snappy) { text = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(palette.text3)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Clear search")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(palette.raised, in: .rect(cornerRadius: Radius.small, style: .continuous))
        .animation(Motion.snappy, value: text.isEmpty)
    }
}

private struct HistoryGroup: Identifiable {
    let title: String
    let conversations: [Conversation]

    var id: String { title }

    static func group(_ conversations: [Conversation], now: Date = .now) -> [HistoryGroup] {
        let calendar = Calendar.current
        var buckets: [(String, [Conversation])] = [(String(localized: "Today"), []), (String(localized: "Yesterday"), []), (String(localized: "Last week"), []), (String(localized: "Earlier"), [])]
        for conversation in conversations {
            let date = conversation.updatedAt
            let index: Int
            if calendar.isDateInToday(date) {
                index = 0
            } else if calendar.isDateInYesterday(date) {
                index = 1
            } else if let days = calendar.dateComponents([.day], from: date, to: now).day, days < 7 {
                index = 2
            } else {
                index = 3
            }
            buckets[index].1.append(conversation)
        }
        return buckets.filter { !$0.1.isEmpty }.map { HistoryGroup(title: $0.0, conversations: $0.1) }
    }
}

private extension Date {
    var quietGPTShortLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) {
            return formatted(date: .omitted, time: .shortened)
        }
        if let days = calendar.dateComponents([.day], from: self, to: .now).day, days < 7 {
            return formatted(.dateTime.weekday(.abbreviated))
        }
        return formatted(.dateTime.month(.abbreviated).day())
    }
}
