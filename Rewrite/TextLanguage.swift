import Foundation
import NaturalLanguage

enum TextLanguage {
    static let settledLetters = 20

    private static let minimumLetters = 4
    private static let shortLetters = 8
    private static let freeLetters = 12
    private static let freeConfidence = 0.8
    private static let hintedConfidence = 0.6
    private static let shortConfidence = 0.99

    private static let known = [
        "en", "es", "ca", "fr", "de", "it", "pt", "nl", "sv", "da", "nb", "fi", "pl", "tr", "ru", "uk",
        "el", "ar", "he", "hi", "ja", "ko", "zh", "vi", "th", "id", "ro", "cs", "hu", "gl", "eu"
    ]

    private static let catalanWords: Set<String> = [
        "amb", "però", "perquè", "què", "això", "allò", "aquest", "aquesta", "aquests", "aquestes", "també", "doncs",
        "llavors", "encara", "després", "abans", "avui", "demà", "ahir", "ara", "aviat", "gens", "res", "molt", "moltes",
        "gràcies", "sisplau", "siusplau", "adéu", "perdó", "nosaltres", "vosaltres", "meva", "teva", "seva", "dels", "pels",
        "els", "ens", "ho", "és", "són", "ets", "sóc", "estic", "estàs", "tinc", "tenim", "vull", "vols", "volem", "puc",
        "pots", "podries", "vaig", "anem", "vinc", "faig", "crec", "saps", "hem", "heu", "veiem", "veure", "parlem",
        "arribo", "sento", "matí", "vespre", "feina", "cotxe", "nen", "sopar", "dinar", "esmorzar", "quan", "bé"
    ]

    private static let likelyDrift: Set<String> = ["es", "en"]

    private static let translationStems = ["translat", "traduc", "tradui", "traduz", "tradueix", "ubersetz"]

    static var likely: [String] {
        var codes: [String] = []
        switch StyleStore.options.language {
        case .spanish: codes.append("es")
        case .english: codes.append("en")
        case .automatic: break
        }
        codes += Locale.preferredLanguages.compactMap { Locale(identifier: $0).language.languageCode?.identifier }
        codes += ["en", "es"]
        var seen = Set<String>()
        return codes.filter { seen.insert($0).inserted }
    }

    static func letters(in text: String) -> Int {
        text.count(where: \.isLetter)
    }

    static func code(of text: String, likely: [String] = likely) -> String? {
        let count = letters(in: text)
        guard count >= minimumLetters else { return nil }
        if isCatalan(text) { return "ca" }
        if count >= freeLetters, let free = best(text), free.confidence >= freeConfidence {
            return free.code
        }
        guard let hinted = best(text, among: likely), hinted.confidence >= hintedConfidence else { return nil }
        if count < shortLetters, hinted.code != likely.first, hinted.confidence < shortConfidence {
            return nil
        }
        return hinted.code
    }

    static func isCatalan(_ text: String) -> Bool {
        let words = text.lowercased().split { !$0.isLetter }.map(String.init)
        let hits = Set(words).intersection(catalanWords).count
        return hits >= 2 || (hits == 1 && words.count <= 3)
    }

    static func single(of text: String, likely: [String] = likely) -> String? {
        guard let whole = code(of: text, likely: likely) else { return nil }
        let parts = text.split { $0.isNewline || ".!?:;\"“”«»".contains($0) }
        for part in parts where letters(in: String(part)) >= settledLetters {
            guard code(of: String(part), likely: likely) == whole else { return nil }
        }
        return whole
    }

    static func name(of code: String) -> String? {
        let english = Locale(identifier: "en")
        return english.localizedString(forLanguageCode: code) ?? english.localizedString(forIdentifier: code)
    }

    static func differs(_ output: String, from expected: String) -> Bool {
        guard letters(in: output) >= freeLetters else { return false }
        let catalan = isCatalan(output)
        guard !catalan || expected != "ca" else { return false }
        guard !catalan else { return true }
        guard let free = best(output), free.confidence >= freeConfidence, free.code != expected else { return false }
        guard expected != "ca" else { return likelyDrift.contains(free.code) }
        guard let pair = best(output, among: [expected, free.code]) else { return false }
        return pair.code != expected && pair.confidence >= freeConfidence
    }

    static func namesLanguage(_ request: String, likely: [String] = likely) -> Bool {
        let words = Set(fold(request).split { !$0.isLetter }.map(String.init))
        guard !words.isEmpty else { return false }
        if words.contains(where: { word in translationStems.contains { word.hasPrefix($0) } }) {
            return true
        }
        let locales = Set(["en"] + likely).map { Locale(identifier: $0) }
        for code in known {
            for locale in locales + [Locale(identifier: code)] {
                guard let name = locale.localizedString(forLanguageCode: code) else { continue }
                if words.contains(fold(name)) { return true }
            }
        }
        return false
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en"))
    }

    private static func best(_ text: String, among codes: [String] = []) -> (code: String, confidence: Double)? {
        let recognizer = NLLanguageRecognizer()
        if let first = codes.first {
            let rest = codes.dropFirst()
            var hints = [NLLanguage(first): rest.isEmpty ? 1 : 0.5]
            for code in rest {
                hints[NLLanguage(code)] = 0.5 / Double(rest.count)
            }
            recognizer.languageHints = hints
        }
        recognizer.processString(text)
        guard let top = recognizer.languageHypotheses(withMaximum: 1).first else { return nil }
        return (base(top.key.rawValue), top.value)
    }

    private static func base(_ code: String) -> String {
        code.split(separator: "-").first.map(String.init) ?? code
    }
}
