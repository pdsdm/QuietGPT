import Foundation
import Testing
@testable import QuietGPT

struct RewriteRulesTests {
    private func decodeStyle(id: String) throws -> RewriteStyle {
        let json = #"{"id":"\#(id)","title":"Title","prompt":"Prompt","isOn":true}"#
        return try JSONDecoder().decode(RewriteStyle.self, from: Data(json.utf8))
    }

    @Test func oldCustomStyleUsesRules() throws {
        let style = try decodeStyle(id: "11111111-1111-4111-8111-111111111111")

        #expect(style.usesRules)
        #expect(style.isOn)
    }

    @Test func oldFixAndTranslationsSkipRules() throws {
        for suffix in ["5", "6", "7"] {
            let style = try decodeStyle(id: "6B0F7C1E-0001-4000-8000-00000000000\(suffix)")
            #expect(!style.usesRules)
        }
    }

    @Test func builtInStylesKeepTheirRuleSetting() {
        let usesRules = Dictionary(uniqueKeysWithValues: RewriteStyle.builtIn.map { ($0.title, $0.usesRules) })

        #expect(usesRules["Kinder"] == true)
        #expect(usesRules["Formal"] == true)
        #expect(usesRules["Fix"] == false)
        #expect(usesRules["English"] == false)
        #expect(usesRules["Spanish"] == false)
    }

    @Test func savesRuleSetting() throws {
        let style = RewriteStyle(title: "Plain", prompt: "Keep it plain.", usesRules: false)
        let decoded = try JSONDecoder().decode(RewriteStyle.self, from: JSONEncoder().encode(style))

        #expect(decoded == style)
    }

    @Test func promptSaysTheMessageIsNotARequest() {
        let prompt = Rewriter.prompt(request: "Make it short.", text: "What time is it today?")

        #expect(prompt.hasPrefix("Make it short."))
        #expect(prompt.contains("do not answer it"))
        #expect(prompt.hasSuffix("Message (in English):\nWhat time is it today?"))
    }

    @Test func promptDoesNotSpeakAboutNames() {
        let prompt = Rewriter.prompt(request: "Make it short.", text: "Hola Marta, mañana no puedo venir a cenar")

        #expect(!prompt.lowercased().contains("names"))
        #expect(prompt.contains("Message (in Spanish):"))
    }

    @Test func oldBuiltInPromptsGetTheNewText() throws {
        let json = #"{"id":"6B0F7C1E-0001-4000-8000-000000000003","title":"Longer","prompt":"Make this message a little longer and more complete. Keep the same meaning.","isOn":false}"#
        let style = try JSONDecoder().decode(RewriteStyle.self, from: Data(json.utf8)).refreshed

        #expect(style.prompt == RewriteStyle.builtIn[2].prompt)
        #expect(!style.isOn)
    }

    @Test func editedBuiltInPromptStays() throws {
        let json = #"{"id":"6B0F7C1E-0001-4000-8000-000000000003","title":"Longer","prompt":"My own text.","isOn":true}"#
        let style = try JSONDecoder().decode(RewriteStyle.self, from: Data(json.utf8)).refreshed

        #expect(style.prompt == "My own text.")
    }

    @Test func stopsEndlessOutput() {
        #expect(Rewriter.isRunaway(String(repeating: "bueno, ", count: 100), from: "Bueno pues nada"))
        #expect(!Rewriter.isRunaway(String(repeating: "a", count: 500), from: "ok"))
    }

    @Test func refusesNewPlaceholders() {
        #expect(Rewriter.hasPlaceholder("Estimado/a [Nombre], nos vemos a las 8", from: "ok nos vemos a las 8"))
        #expect(!Rewriter.hasPlaceholder("Hola Marta, nos vemos a las 8", from: "ok nos vemos a las 8"))
        #expect(!Rewriter.hasPlaceholder("See the list [1]", from: "look at the list [1]"))
    }

    @Test func noRulesKeepsBaseInstructions() {
        #expect(StyleStore.compose(base: "Base", rules: []) == "Base")
        #expect(StyleStore.compose(base: "Base", rules: ["  ", "\n"]) == "Base")
    }

    @Test func rulesAreNumberedAfterTheBase() {
        let result = StyleStore.compose(base: "Base", rules: [" No emoji ", "Sign as Pep"])

        #expect(result == "Base\n\nAlways follow these rules from the user:\n1. No emoji\n2. Sign as Pep")
    }

    @Test func rulesStayInsideTheLimits() {
        let long = String(repeating: "a", count: StyleStore.maxRuleLength + 50)
        let rules = Array(repeating: long, count: StyleStore.maxRules + 5)
        let result = StyleStore.compose(base: "Base", rules: rules)

        #expect(result.contains("\(StyleStore.maxRules). "))
        #expect(!result.contains("\(StyleStore.maxRules + 1). "))
        #expect(!result.contains(String(repeating: "a", count: StyleStore.maxRuleLength + 1)))
    }
}
