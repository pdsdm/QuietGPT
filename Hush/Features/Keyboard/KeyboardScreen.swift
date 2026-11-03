import SwiftUI
import UIKit

struct KeyboardScreen: View {
    @Environment(\.palette) private var palette
    @State private var styles = StyleStore.styles
    @State private var options = StyleStore.options
    @State private var instructions = StyleStore.instructions
    @State private var editing: RewriteStyle?
    @State private var editsInstructions = false
    @State private var confirmingReset = false
    @State private var editMode = EditMode.inactive

    var body: some View {
        NavigationStack {
            List {
                Text("Keyboard")
                    .font(HushFont.largeTitle)
                    .foregroundStyle(palette.text)
                    .listRowInsets(EdgeInsets(top: 24, leading: 4, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)

                Section {
                    BarPreview(styles: styles.filter(\.isOn), showsAsk: options.showsAsk)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } footer: {
                    Text("This is the bar above your keys. Tap a style to rewrite what you wrote.")
                        .font(HushFont.footnote)
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
                            .font(HushFont.callout)
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
                        .font(HushFont.footnote)
                        .foregroundStyle(palette.accent)
                    }
                } footer: {
                    Text("Turn styles on or off, drag to change the order, or swipe to delete.")
                        .font(HushFont.footnote)
                        .foregroundStyle(palette.text2)
                }

                Section {
                    Button {
                        editsInstructions = true
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(instructions)
                                .font(HushFont.footnote)
                                .foregroundStyle(palette.text)
                                .lineLimit(4)
                                .multilineTextAlignment(.leading)
                            Text("Edit")
                                .font(HushFont.footnote)
                                .foregroundStyle(palette.accent)
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(palette.surface)
                } header: {
                    Text("Base instructions")
                } footer: {
                    Text("Hush follows these rules for every style.")
                        .font(HushFont.footnote)
                        .foregroundStyle(palette.text2)
                }

                Section("Typing") {
                    toggle("Auto capitals", isOn: $options.autoCapitalize)
                    toggle("Double space adds a period", isOn: $options.periodShortcut)
                    toggle("Show Ask in the bar", isOn: $options.showsAsk)
                }

                Section {
                    Button("Open Settings to add the keyboard") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(HushFont.callout)
                    .foregroundStyle(palette.accent)
                    .listRowBackground(palette.surface)

                    Button("Reset styles and instructions", role: .destructive) {
                        confirmingReset = true
                    }
                    .font(HushFont.callout)
                    .foregroundStyle(palette.danger)
                    .listRowBackground(palette.surface)
                } footer: {
                    Text("Settings > General > Keyboard > Keyboards > Add New Keyboard > Hush. Full access is not needed.")
                        .font(HushFont.footnote)
                        .foregroundStyle(palette.text2)
                }
            }
            .environment(\.editMode, $editMode)
            .scrollContentBackground(.hidden)
            .background(palette.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .animation(Motion.snappy, value: styles)
            .animation(Motion.snappy, value: options)
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
        .sheet(isPresented: $editsInstructions) {
            InstructionsEditor(text: instructions) { instructions = $0 }
        }
        .confirmationDialog("Reset the keyboard?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) {
                StyleStore.reset()
                styles = StyleStore.styles
                options = StyleStore.options
                instructions = StyleStore.instructions
            }
        } message: {
            Text("This brings back the default styles and instructions.")
        }
        .onChange(of: styles) { _, value in StyleStore.styles = value }
        .onChange(of: options) { _, value in StyleStore.options = value }
        .onChange(of: instructions) { _, value in StyleStore.instructions = value }
        .sensoryFeedback(.selection, trigger: styles.map(\.isOn))
    }

    private func toggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(HushFont.callout)
                .foregroundStyle(palette.text)
        }
        .tint(palette.accent)
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
                        .font(HushFont.callout)
                        .foregroundStyle(style.isOn ? palette.text : palette.text3)
                    Text(style.prompt)
                        .font(HushFont.footnote)
                        .foregroundStyle(palette.text2)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Toggle("", isOn: $style.isOn)
                .labelsHidden()
                .tint(palette.accent)
        }
        .padding(.vertical, 2)
    }
}

private struct BarPreview: View {
    let styles: [RewriteStyle]
    let showsAsk: Bool

    @Environment(\.colorScheme) private var scheme

    private var style: KeyStyle { .current(scheme) }

    private var titles: [String] {
        Array((styles.map(\.title) + (showsAsk ? ["Ask"] : [])).prefix(3))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(titles.enumerated()), id: \.element) { index, title in
                    Text(title)
                        .font(.system(size: 16))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(Color(style.text))
                        .frame(maxWidth: .infinity)
                        .overlay(alignment: .trailing) {
                            if index < titles.count - 1 {
                                Rectangle()
                                    .fill(Color(style.separator))
                                    .frame(width: 1, height: 24)
                            }
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
                if titles.isEmpty {
                    Text("No styles on")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(style.secondary))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 44)
            HStack(spacing: 6) {
                ForEach(Array("qwertyuiop"), id: \.self) { letter in
                    Text(String(letter).uppercased())
                        .font(.system(size: 20))
                        .foregroundStyle(Color(style.text))
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(Color(style.key), in: .rect(cornerRadius: KeyStyle.radius, style: .continuous))
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
        .background(Color(style.background), in: .rect(cornerRadius: 26, style: .continuous))
        .animation(Motion.snappy, value: titles)
    }
}

private struct StyleEditor: View {
    @State var style: RewriteStyle
    let isNew: Bool
    let onSave: (RewriteStyle) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    init(style: RewriteStyle, isNew: Bool, onSave: @escaping (RewriteStyle) -> Void, onDelete: @escaping () -> Void) {
        _style = State(initialValue: style)
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
                    TextField("For example, Friendly", text: $style.title)
                        .font(HushFont.callout)
                        .listRowBackground(palette.surface)
                }
                Section {
                    TextEditor(text: $style.prompt)
                        .font(HushFont.callout)
                        .frame(minHeight: 110)
                        .listRowBackground(palette.surface)
                } header: {
                    Text("What Hush does")
                } footer: {
                    Text("Write it as an order. For example: Make this message friendly and relaxed. Keep the same meaning.")
                        .font(HushFont.footnote)
                }
                TryItSection(request: style.prompt)
                if !isNew {
                    Section {
                        Button("Delete style", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                        .listRowBackground(palette.surface)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.background.ignoresSafeArea())
            .navigationTitle(isNew ? "New style" : style.title)
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
                        .font(HushFont.callout)
                        .frame(minHeight: 200)
                        .listRowBackground(palette.surface)
                } footer: {
                    Text("Hush reads these rules before each style.")
                        .font(HushFont.footnote)
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
                .font(HushFont.callout)
                .lineLimit(1...4)
                .listRowBackground(palette.surface)
            if !result.isEmpty || failure != nil {
                Text(failure ?? result)
                    .font(HushFont.callout)
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
                .font(HushFont.footnote)
        }
        .animation(Motion.snappy, value: result.isEmpty)
        .onDisappear(perform: stop)
    }

    private func run() {
        task?.cancel()
        result = ""
        failure = nil
        guard rewriter.isAvailable else {
            failure = "Turn on Apple Intelligence in Settings to try styles."
            return
        }
        isWriting = true
        let stream = rewriter.rewrite(sample, request: request)
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
