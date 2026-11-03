import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let stylePack = UTType(exportedAs: "\(Bundle.main.bundleIdentifier ?? "com.pdsdm.hush").stylepack")
}

extension StylePack: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .stylePack) { pack in
            let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appending(path: pack.fileName).appendingPathExtension(StylePack.fileExtension)
            try pack.encoded().write(to: file, options: .atomic)
            return SentTransferredFile(file)
        }
    }

    private var fileName: String {
        let name = name.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty || name.hasPrefix(".") ? "QuietGPT styles" : name
    }

    static func read(from url: URL) throws -> StylePack {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= maxBytes else { throw Failure.tooLarge }
        return try decode(Data(contentsOf: url))
    }
}

struct PackExportScreen: View {
    let styles: [RewriteStyle]
    let rules: [String]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var name = "My styles"
    @State private var selectedStyles: Set<RewriteStyle.ID>
    @State private var selectedRules: Set<String>

    init(styles: [RewriteStyle], rules: [String]) {
        let allowed = styles.filter { $0.title.count <= StylePack.maxTitleLength && $0.prompt.count <= StylePack.maxPromptLength }
        self.styles = allowed
        self.rules = rules
        _selectedStyles = State(initialValue: Set(allowed.prefix(StylePack.maxStyles).map(\.id)))
        _selectedRules = State(initialValue: Set(rules))
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var pack: StylePack {
        StylePack(
            name: trimmedName,
            rules: rules.filter(selectedRules.contains),
            styles: styles.filter { selectedStyles.contains($0.id) }
        )
    }

    private var canShare: Bool {
        !trimmedName.isEmpty
            && (!selectedStyles.isEmpty || !selectedRules.isEmpty)
            && selectedStyles.count <= StylePack.maxStyles
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Pack name") {
                    TextField("For example, Team styles", text: $name)
                        .font(QuietGPTFont.callout)
                        .listRowBackground(palette.surface)
                        .onChange(of: name) { _, value in
                            if value.count > StylePack.maxTitleLength {
                                name = String(value.prefix(StylePack.maxTitleLength))
                            }
                        }
                }

                if !rules.isEmpty {
                    Section("Rules") {
                        ForEach(rules, id: \.self) { rule in
                            selectionRow(rule, subtitle: nil, isOn: selectedRules.contains(rule)) {
                                selectedRules.formSymmetricDifference([rule])
                            }
                        }
                    }
                }

                Section {
                    ForEach(styles) { style in
                        selectionRow(style.title, subtitle: style.prompt, isOn: selectedStyles.contains(style.id)) {
                            selectedStyles.formSymmetricDifference([style.id])
                        }
                    }
                } header: {
                    Text("Styles")
                } footer: {
                    Text(selectedStyles.count > StylePack.maxStyles
                         ? "A pack can have \(StylePack.maxStyles) styles or fewer."
                         : "People are not shared, because they can contain private facts.")
                        .font(QuietGPTFont.footnote)
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.background.ignoresSafeArea())
            .navigationTitle("Share styles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    ShareLink("Share", item: pack, preview: SharePreview(trimmedName))
                        .disabled(!canShare)
                }
            }
        }
    }

    private func selectionRow(_ title: String, subtitle: String?, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(QuietGPTFont.callout)
                        .foregroundStyle(palette.text)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle)
                            .font(QuietGPTFont.footnote)
                            .foregroundStyle(palette.text2)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? palette.accent : palette.text3)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowBackground(palette.surface)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

struct PackImportScreen: View {
    let pack: StylePack
    let onAdd: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    private var merged: StylePack.Merged {
        pack.merged(styles: StyleStore.styles, rules: StyleStore.rules)
    }

    private var summary: String {
        let merged = merged
        var parts = [merged.addedStyles == 0 && merged.addedRules == 0
            ? "You already have everything in this pack."
            : "This adds \(count(merged.addedStyles, "style")) and \(count(merged.addedRules, "rule"))."]
        if merged.skippedRules > 0 {
            parts.append("\(count(merged.skippedRules, "rule")) will not be added, because the limit is \(StyleStore.maxRules) rules.")
        }
        return parts.joined(separator: " ")
    }

    private func count(_ value: Int, _ noun: String) -> String {
        value == 1 ? "1 \(noun)" : "\(value) \(noun)s"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Read these before you add them. QuietGPT follows them when it rewrites your messages.")
                        .font(QuietGPTFont.callout)
                        .foregroundStyle(palette.text)
                        .listRowBackground(palette.surface)
                }

                if !pack.rules.isEmpty {
                    Section("Rules") {
                        ForEach(Array(pack.rules.enumerated()), id: \.offset) { _, rule in
                            Text(rule)
                                .font(QuietGPTFont.callout)
                                .foregroundStyle(palette.text)
                                .listRowBackground(palette.surface)
                        }
                    }
                }

                if !pack.styles.isEmpty {
                    Section("Styles") {
                        ForEach(Array(pack.styles.enumerated()), id: \.offset) { _, style in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(style.title)
                                    .font(QuietGPTFont.callout)
                                    .foregroundStyle(palette.text)
                                Text(style.prompt)
                                    .font(QuietGPTFont.footnote)
                                    .foregroundStyle(palette.text2)
                            }
                            .padding(.vertical, 2)
                            .listRowBackground(palette.surface)
                        }
                    }
                }

                Section {
                    EmptyView()
                } footer: {
                    Text(summary)
                        .font(QuietGPTFont.footnote)
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.background.ignoresSafeArea())
            .navigationTitle(pack.name.isEmpty ? "Style pack" : pack.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let merged = merged
                        StyleStore.styles = merged.styles
                        StyleStore.rules = merged.rules
                        onAdd()
                        dismiss()
                    }
                    .disabled(merged.addedStyles == 0 && merged.addedRules == 0)
                }
            }
        }
    }
}
