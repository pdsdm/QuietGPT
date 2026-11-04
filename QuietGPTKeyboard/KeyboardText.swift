import Foundation

enum KeyboardText {
    private(set) static var bundle = Bundle.main

    static func use(spanish: Bool) {
        let path = Bundle.main.path(forResource: spanish ? "es" : "en", ofType: "lproj")
        bundle = path.flatMap(Bundle.init(path:)) ?? .main
        Rewriter.bundle = bundle
    }

    static func string(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: bundle)
    }
}
