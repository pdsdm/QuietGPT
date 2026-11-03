import SwiftUI

struct RuleEdit: Identifiable {
    let id = UUID()
    var index: Int?
    var text = ""
}

struct RulesSection: View {
    @Binding var rules: [String]
    let onEdit: (RuleEdit) -> Void

    @Environment(\.palette) private var palette

    private static let examples = [
        "Do not use emoji.",
        "Do not use exclamation marks.",
        "Use short sentences."
    ]

    var body: some View {
        Section {
            ForEach(Array(rules.enumerated()), id: \.offset) { index, rule in
                Button {
                    onEdit(RuleEdit(index: index, text: rule))
                } label: {
                    Text(rule)
                        .font(QuietGPTFont.callout)
                        .foregroundStyle(palette.text)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .listRowBackground(palette.surface)
            }
            .onDelete { rules.remove(atOffsets: $0) }

            if rules.isEmpty {
                ForEach(Self.examples, id: \.self) { example in
                    Button {
                        withAnimation(Motion.snappy) { rules.append(example) }
                    } label: {
                        Label(example, systemImage: "plus.circle")
                            .font(QuietGPTFont.callout)
                            .foregroundStyle(palette.text2)
                    }
                    .listRowBackground(palette.surface)
                }
            }

            if rules.count < StyleStore.maxRules {
                Button {
                    onEdit(RuleEdit())
                } label: {
                    Label("Add rule", systemImage: "plus")
                        .font(QuietGPTFont.callout)
                        .foregroundStyle(palette.accent)
                }
                .listRowBackground(palette.surface)
            }
        } header: {
            Text("My rules")
        } footer: {
            Text(rules.count < StyleStore.maxRules
                 ? "QuietGPT follows these rules in each rewrite. You can turn them off for one style."
                 : "You have the maximum of \(StyleStore.maxRules) rules.")
                .font(QuietGPTFont.footnote)
                .foregroundStyle(palette.text2)
        }
    }
}

struct RuleEditor: View {
    let edit: RuleEdit
    let onSave: (String) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var text: String

    init(edit: RuleEdit, onSave: @escaping (String) -> Void, onDelete: @escaping () -> Void) {
        self.edit = edit
        self.onSave = onSave
        self.onDelete = onDelete
        _text = State(initialValue: edit.text)
    }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("For example, Do not use emoji.", text: $text, axis: .vertical)
                        .font(QuietGPTFont.callout)
                        .lineLimit(2...5)
                        .listRowBackground(palette.surface)
                        .onChange(of: text) { _, value in
                            if value.count > StyleStore.maxRuleLength {
                                text = String(value.prefix(StyleStore.maxRuleLength))
                            }
                        }
                } footer: {
                    Text("\(text.count) of \(StyleStore.maxRuleLength) characters. Short rules work best.")
                        .font(QuietGPTFont.footnote)
                }
                if edit.index != nil {
                    Section {
                        Button("Delete rule", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                        .listRowBackground(palette.surface)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.background.ignoresSafeArea())
            .navigationTitle(edit.index == nil ? "New rule" : "Edit rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(trimmed)
                        dismiss()
                    }
                    .disabled(trimmed.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
