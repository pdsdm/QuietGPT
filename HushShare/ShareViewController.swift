import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        let card = UIHostingController(rootView: RewriteCard(
            loadText: { [weak self] in await self?.sharedText() ?? "" },
            onClose: { [weak self] in self?.close() }
        ))
        card.view.backgroundColor = .clear
        addChild(card)
        card.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card.view)
        NSLayoutConstraint.activate([
            card.view.topAnchor.constraint(equalTo: view.topAnchor),
            card.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            card.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            card.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        card.didMove(toParent: self)
    }

    private func sharedText() async -> String {
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        for item in items {
            for provider in item.attachments ?? [] where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                if let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                    return text
                }
            }
            if let text = item.attributedContentText?.string, !text.isEmpty {
                return text
            }
        }
        return ""
    }

    private func close() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
