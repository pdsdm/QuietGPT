import SwiftUI
import UIKit

struct KeyboardScreen: View {
    @Environment(\.palette) private var palette
    @State private var styles = StyleStore.styles
    @State private var options = StyleStore.options
    @State private var instructions = StyleStore.instructions
    @State private var rules = StyleStore.rules
    @State private var people = StyleStore.people
    @State private var editing: RewriteStyle?
    @State private var editingPerson: RewriteStyle?
    @State private var editingRule: RuleEdit?
    @State private var editsInstructions = false
    @State private var sharesPack = false
    @State private var confirmingReset = false
    @State private var editMode = EditMode.inactive
    @State private var keyboardTest = ""
    @FocusState private var testsKeyboard: Bool

    private static let keyHeightRow = "keyHeightRow"

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    Text("Keyboard")
                        .font(QuietGPTFont.largeTitle)
                        .foregroundStyle(palette.text)
                        .listRowInsets(EdgeInsets(top: 24, leading: 4, bottom: 0, trailing: 0))
                        .listRowBackground(Color.clear)

                    Section {
                        PanelPreview(people: people.filter(\.isOn), styles: styles.filter(\.isOn), ruleCount: rules.count, showsAsk: options.showsAsk)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    } footer: {
                        Text("This is the panel in your keyboard. Tap a person or a style to rewrite what you wrote.")
                            .font(QuietGPTFont.footnote)
                            .foregroundStyle(palette.text2)
                    }

                    RulesSection(rules: $rules) { editingRule = $0 }

                    Section {
                        ForEach($people) { $person in
                            StyleRow(style: $person) {
                                editingPerson = person
                            }
                            .listRowBackground(palette.surface)
                        }
                        .onMove { people.move(fromOffsets: $0, toOffset: $1) }
                        .onDelete { people.remove(atOffsets: $0) }

                        Button {
                            editingPerson = RewriteStyle(title: "", prompt: "")
                        } label: {
                            Label("Add person", systemImage: "plus")
                                .font(QuietGPTFont.callout)
                                .foregroundStyle(palette.accent)
                        }
                        .listRowBackground(palette.surface)
                    } header: {
                        Text("People")
                    } footer: {
                        Text("Save how you write to one person. They show first in the keyboard.")
                            .font(QuietGPTFont.footnote)
                            .foregroundStyle(palette.text2)
                    }

                    Section {
                        ForEach($styles) { $style in
                            StyleRow(style: $style) {
                                editing = style
                            }
                            .listRowBackground(palette.surface)
                        }
                        .onMove { styles.move(fromOffsets: $0, toOffset: $1) }
                        .onDelete { styles.remove(atOffsets: $0) }

                        Button {
                            editing = RewriteStyle(title: "", prompt: "")
                        } label: {
                            Label("Add style", systemImage: "plus")
                                .font(QuietGPTFont.callout)
                                .foregroundStyle(palette.accent)
                        }
                        .listRowBackground(palette.surface)
                    } header: {
                        HStack {
                            Text("Styles")
                            Spacer()
                            Button(editMode.isEditing ? "Done" : "Order") {
                                withAnimation(Motion.snappy) {
                                    editMode = editMode.isEditing ? .inactive : .active
                                }
                            }
                            .font(QuietGPTFont.footnote)
                            .foregroundStyle(palette.accent)
                        }
                    } footer: {
                        Text("Turn styles on or off, drag to change the order, or swipe to delete.")
                            .font(QuietGPTFont.footnote)
                            .foregroundStyle(palette.text2)
                    }

                    Section {
                        Button {
                            sharesPack = true
                        } label: {
                            Label("Share styles", systemImage: "square.and.arrow.up")
                                .font(QuietGPTFont.callout)
                                .foregroundStyle(palette.accent)
                        }
                        .listRowBackground(palette.surface)
                    } header: {
                        Text("Share")
                    } footer: {
                        Text("Send your rules and styles as a file. To add a pack from another person, open the file on this iPhone.")
                            .font(QuietGPTFont.footnote)
                            .foregroundStyle(palette.text2)
                    }

                    Section("Typing") {
                        Picker(selection: $options.language) {
                            ForEach(KeyboardLanguage.allCases) { language in
                                Text(language.title).tag(language)
                            }
                        } label: {
                            Text("Language")
                                .font(QuietGPTFont.callout)
                                .foregroundStyle(palette.text)
                        }
                        .tint(palette.accent)
                        .listRowBackground(palette.surface)
                        toggle("Auto capitals", isOn: $options.autoCapitalize)
                        toggle("Double space adds a period", isOn: $options.periodShortcut)
                        toggle("Show Ask in the panel", isOn: $options.showsAsk)
                    }

                    Section {
                        sizeRow("Key height", value: $options.keyHeight, in: KeyboardOptions.keyHeights)
                            .id(Self.keyHeightRow)
                        sizeRow("Top margin", value: $options.topMargin, in: KeyboardOptions.topMargins)
                        TextField("Tap here to try the keyboard", text: $keyboardTest)
                            .focused($testsKeyboard)
                            .textContentType(KeyboardOptions.tuningField)
                            .font(QuietGPTFont.callout)
                            .listRowBackground(palette.surface)
                    } header: {
                        Text("Size")
                    } footer: {
                        Text("The keyboard changes while you move the slider. It takes at most half of the screen.")
                            .font(QuietGPTFont.footnote)
                            .foregroundStyle(palette.text2)
                    }

                    Section {
                        ForEach(people.filter(\.isOn)) { person in
                            topRowToggle(person.title, id: person.id.uuidString) {
                                StyleGlyph(value: person, isPerson: true, color: palette.text)
                            }
                        }
                        ForEach(styles.filter(\.isOn)) { style in
                            topRowToggle(style.title, id: style.id.uuidString) {
                                StyleGlyph(value: style, color: palette.text)
                            }
                        }
                        if options.showsAsk {
                            topRowToggle(String(localized: "Ask"), id: KeyboardOptions.topRowAsk) {
                                Image(systemName: "text.bubble")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(palette.text)
                            }
                        }
                    } header: {
                        Text("Top row")
                    } footer: {
                        Text("These show next to the QuietGPT logo, above the keys. The logo opens the panel. The row needs a top margin of 26 pt or more.")
                            .font(QuietGPTFont.footnote)
                            .foregroundStyle(palette.text2)
                    }

                    Section {
                        Button {
                            editsInstructions = true
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Base instructions")
                                    .font(QuietGPTFont.callout)
                                    .foregroundStyle(palette.text)
                                Text(instructions)
                                    .font(QuietGPTFont.footnote)
                                    .foregroundStyle(palette.text2)
                                    .lineLimit(3)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(palette.surface)
                    } header: {
                        Text("Advanced")
                    } footer: {
                        Text("QuietGPT reads these before your rules. Most people do not need to change them.")
                            .font(QuietGPTFont.footnote)
                            .foregroundStyle(palette.text2)
                    }

                    Section {
                        Button("Open Settings to add the keyboard") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(QuietGPTFont.callout)
                        .foregroundStyle(palette.accent)
                        .listRowBackground(palette.surface)

                        Button("Reset rules, people and styles", role: .destructive) {
                            confirmingReset = true
                        }
                        .font(QuietGPTFont.callout)
                        .foregroundStyle(palette.danger)
                        .listRowBackground(palette.surface)
                    } footer: {
                        Text("Settings > General > Keyboard > Keyboards > Add New Keyboard > QuietGPT. Full access is not needed.")
                            .font(QuietGPTFont.footnote)
                            .foregroundStyle(palette.text2)
                    }
                }
                .environment(\.editMode, $editMode)
                .background(KeyboardTapCatcher())
                .scrollContentBackground(.hidden)
                .background(palette.background.ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
                .animation(Motion.snappy, value: styles)
                .animation(Motion.snappy, value: options)
                .animation(Motion.snappy, value: rules)
                .animation(Motion.snappy, value: people)
                .onChange(of: testsKeyboard) { _, focused in
                    guard focused else { return }
                    Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        withAnimation(Motion.snappy) { proxy.scrollTo(Self.keyHeightRow, anchor: .top) }
                    }
                }
            }
        }
        .sheet(item: $editingPerson) { person in
            StyleEditor(style: person, kind: .person, isNew: !people.contains { $0.id == person.id }) { saved in
                if let index = people.firstIndex(where: { $0.id == saved.id }) {
                    people[index] = saved
                } else {
                    people.append(saved)
                }
            } onDelete: {
                people.removeAll { $0.id == person.id }
            }
        }
        .sheet(item: $editingRule) { edit in
            RuleEditor(edit: edit) { text in
                if let index = edit.index, rules.indices.contains(index) {
                    rules[index] = text
                } else {
                    rules.append(text)
                }
            } onDelete: {
                if let index = edit.index, rules.indices.contains(index) {
                    rules.remove(at: index)
                }
            }
        }
        .sheet(item: $editing) { style in
            StyleEditor(style: style, isNew: !styles.contains { $0.id == style.id }) { saved in
                if let index = styles.firstIndex(where: { $0.id == saved.id }) {
                    styles[index] = saved
                } else {
                    styles.append(saved)
                }
            } onDelete: {
                styles.removeAll { $0.id == style.id }
            }
        }
        .sheet(isPresented: $sharesPack) {
            PackExportScreen(styles: styles, rules: rules)
        }
        .sheet(isPresented: $editsInstructions) {
            InstructionsEditor(text: instructions) { instructions = $0 }
        }
        .confirmationDialog("Reset the keyboard?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) {
                StyleStore.reset()
                styles = StyleStore.styles
                options = StyleStore.options
                instructions = StyleStore.instructions
                rules = StyleStore.rules
                people = StyleStore.people
            }
        } message: {
            Text("This removes your rules and people, and brings back the default styles and instructions.")
        }
        .onChange(of: rules) { _, value in StyleStore.rules = value }
        .onChange(of: people) { _, value in StyleStore.people = value }
        .onChange(of: styles) { _, value in StyleStore.styles = value }
        .onChange(of: options) { old, value in
            StyleStore.options = value
            if old.layoutChoice != value.layoutChoice {
                StyleStore.savedLayout = value.layoutChoice
            }
        }
        .onChange(of: instructions) { _, value in StyleStore.instructions = value }
        .sensoryFeedback(.selection, trigger: styles.map(\.isOn))
        .sensoryFeedback(.selection, trigger: options.layoutChoice)
    }

    private func sizeRow(_ title: LocalizedStringKey, value: Binding<Double>, in range: ClosedRange<Double>) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(title)
                    .font(QuietGPTFont.callout)
                    .foregroundStyle(palette.text)
                Spacer()
                Text("\(Int(value.wrappedValue)) pt")
                    .font(QuietGPTFont.callout)
                    .foregroundStyle(palette.text2)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: 2)
                .tint(palette.accent)
                .accessibilityLabel(title)
        }
        .listRowBackground(palette.surface)
    }

    private func topRowToggle(_ title: String, id: String, @ViewBuilder icon: () -> some View) -> some View {
        Toggle(isOn: Binding {
            options.topRow.contains(id)
        } set: { isOn in
            options.topRow.removeAll { $0 == id }
            if isOn {
                options.topRow.append(id)
            }
        }) {
            HStack(spacing: 12) {
                icon()
                    .frame(width: 24)
                Text(title)
                    .font(QuietGPTFont.callout)
                    .foregroundStyle(palette.text)
            }
        }
        .tint(palette.toggle)
        .listRowBackground(palette.surface)
    }

    private func toggle(_ title: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(QuietGPTFont.callout)
                .foregroundStyle(palette.text)
        }
        .tint(palette.toggle)
        .listRowBackground(palette.surface)
    }
}

private struct StyleRow: View {
    @Binding var style: RewriteStyle
    let onEdit: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(style.title)
                        .font(QuietGPTFont.callout)
                        .foregroundStyle(style.isOn ? palette.text : palette.text3)
                    Text(style.prompt)
                        .font(QuietGPTFont.footnote)
                        .foregroundStyle(palette.text2)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Toggle("", isOn: $style.isOn)
                .labelsHidden()
                .tint(palette.toggle)
        }
        .padding(.vertical, 2)
    }
}

private struct PanelPreview: View {
    let people: [RewriteStyle]
    let styles: [RewriteStyle]
    let ruleCount: Int
    let showsAsk: Bool

    @Environment(\.colorScheme) private var scheme

    private var style: KeyStyle { .current(scheme) }

    private var status: String {
        switch ruleCount {
        case 0: String(localized: "on this iPhone")
        case 1: String(localized: "on this iPhone · 1 rule")
        default: String(localized: "on this iPhone · \(ruleCount) rules")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                LockMark()
                    .fill(Color(style.text))
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text(BrandFont.name)
                        .font(BrandFont.wordmark(size: 17))
                        .tracking(-0.4)
                        .foregroundStyle(Color(style.text))
                    Text(status)
                        .font(BrandFont.font(size: 11))
                        .foregroundStyle(Color(style.secondary))
                        .contentTransition(.opacity)
                }
            }
            .padding(.horizontal, 12)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(people) { StyleTile(value: $0, style: style, isPerson: true) }
                    ForEach(styles) { StyleTile(value: $0, style: style) }
                    if people.isEmpty && styles.isEmpty {
                        Text("No styles on")
                            .font(BrandFont.font(size: 15))
                            .foregroundStyle(Color(style.secondary))
                            .frame(height: 86)
                    }
                }
            }
            .contentMargins(.horizontal, 12, for: .scrollContent)
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)

            if showsAsk {
                HStack(spacing: 10) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(style.text))
                    Text("Ask for any change…")
                        .font(BrandFont.font(size: 15))
                        .foregroundStyle(Color(style.secondary))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Color(style.key), in: .capsule)
                .padding(.horizontal, 12)
                .transition(.opacity)
            }
        }
        .padding(.vertical, 12)
        .background(Color(style.background), in: .rect(cornerRadius: Radius.large, style: .continuous))
        .animation(Motion.snappy, value: people)
        .animation(Motion.snappy, value: styles)
        .animation(Motion.snappy, value: showsAsk)
    }
}

private struct StyleEditor: View {
    enum Kind {
        case style
        case person

        var newTitle: String { self == .style ? String(localized: "New style") : String(localized: "New person") }
        var deleteTitle: String { self == .style ? String(localized: "Delete style") : String(localized: "Delete person") }
        var namePlaceholder: String { self == .style ? String(localized: "For example, Friendly") : String(localized: "For example, Boss") }
        var promptHeader: String { self == .style ? String(localized: "What QuietGPT does") : String(localized: "How you write to this person") }
        var promptFooter: String {
            self == .style
                ? String(localized: "Write it as an order. For example: Make this message friendly and relaxed. Keep the same meaning.")
                : String(localized: "Write it as an order. For example: Write to my boss. Be polite and direct. Do not use emoji.")
        }
    }

    @State var style: RewriteStyle
    let kind: Kind
    let isNew: Bool
    let onSave: (RewriteStyle) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    init(style: RewriteStyle, kind: Kind = .style, isNew: Bool, onSave: @escaping (RewriteStyle) -> Void, onDelete: @escaping () -> Void) {
        _style = State(initialValue: style)
        self.kind = kind
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
    }

    private var canSave: Bool {
        !style.title.trimmingCharacters(in: .whitespaces).isEmpty
            && !style.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField(kind.namePlaceholder, text: $style.title)
                        .font(QuietGPTFont.callout)
                        .listRowBackground(palette.surface)
                }
                Section {
                    TextEditor(text: $style.prompt)
                        .font(QuietGPTFont.callout)
                        .frame(minHeight: 110)
                        .listRowBackground(palette.surface)
                } header: {
                    Text(kind.promptHeader)
                } footer: {
                    Text(kind.promptFooter)
                        .font(QuietGPTFont.footnote)
                }
                Section {
                    Toggle(isOn: $style.usesRules) {
                        Text("Use my rules")
                            .font(QuietGPTFont.callout)
                            .foregroundStyle(palette.text)
                    }
                    .tint(palette.toggle)
                    .listRowBackground(palette.surface)
                }
                TryItSection(request: style.prompt, usesRules: style.usesRules)
                if !isNew {
                    Section {
                        Button(kind.deleteTitle, role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                        .listRowBackground(palette.surface)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.background.ignoresSafeArea())
            .navigationTitle(isNew ? kind.newTitle : style.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        style.title = style.title.trimmingCharacters(in: .whitespaces)
                        style.prompt = style.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(style)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.large])
    }
}

private struct InstructionsEditor: View {
    @State var text: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .font(QuietGPTFont.callout)
                        .frame(minHeight: 200)
                        .listRowBackground(palette.surface)
                } footer: {
                    Text("QuietGPT reads these rules before each style.")
                        .font(QuietGPTFont.footnote)
                }
                Section {
                    Button("Use the default rules") {
                        withAnimation(Motion.snappy) { text = StyleStore.defaultInstructions }
                    }
                    .listRowBackground(palette.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.background.ignoresSafeArea())
            .navigationTitle("Base instructions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(text)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct TryItSection: View {
    let request: String
    let usesRules: Bool

    @Environment(\.palette) private var palette
    @State private var sample = "hey can u send me the file by tomorrow, thx"
    @State private var result = ""
    @State private var failure: String?
    @State private var isWriting = false
    @State private var task: Task<Void, Never>?

    private let rewriter = Rewriter()

    var body: some View {
        Section {
            TextField("Write a message", text: $sample, axis: .vertical)
                .font(QuietGPTFont.callout)
                .lineLimit(1...4)
                .listRowBackground(palette.surface)
            if !result.isEmpty || failure != nil {
                Text(failure ?? result)
                    .font(QuietGPTFont.callout)
                    .foregroundStyle(failure == nil ? palette.text : palette.danger)
                    .contentTransition(.opacity)
                    .listRowBackground(palette.raised)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Button {
                isWriting ? stop() : run()
            } label: {
                HStack {
                    Text(isWriting ? "Stop" : "Try it")
                    Spacer()
                    if isWriting {
                        ProgressView()
                    }
                }
            }
            .disabled(request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sample.isEmpty)
            .listRowBackground(palette.surface)
        } header: {
            Text("Try it")
        } footer: {
            Text("Runs on this iPhone.")
                .font(QuietGPTFont.footnote)
        }
        .animation(Motion.snappy, value: result.isEmpty)
        .onDisappear(perform: stop)
    }

    private func run() {
        task?.cancel()
        result = ""
        failure = nil
        guard rewriter.isAvailable else {
            failure = Rewriter.unavailableMessage
            return
        }
        isWriting = true
        let stream = rewriter.rewrite(sample, request: request, usesRules: usesRules)
        task = Task {
            do {
                for try await text in stream {
                    result = text
                }
            } catch is CancellationError {
                return
            } catch {
                failure = Rewriter.message(for: error)
            }
            isWriting = false
        }
    }

    private func stop() {
        task?.cancel()
        task = nil
        isWriting = false
    }
}
