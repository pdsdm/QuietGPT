import Foundation
import Testing
@testable import QuietGPT

struct KeyboardOptionsTests {
    @Test func keepsOldOptionsWithoutLanguage() throws {
        let data = Data(#"{"autoCapitalize":false,"periodShortcut":true,"showsAsk":false}"#.utf8)
        let options = try JSONDecoder().decode(KeyboardOptions.self, from: data)

        #expect(options.autoCapitalize == false)
        #expect(options.showsAsk == false)
        #expect(options.language == .automatic)
    }

    @Test func newerLocalLanguageWins() {
        var options = KeyboardOptions()
        options.language = .english
        let newer = LanguageChoice(language: .spanish, date: (options.languageDate ?? .now).addingTimeInterval(5))

        options.adopt(newer)

        #expect(options.language == .spanish)
        #expect(options.languageDate == newer.date)
    }

    @Test func olderLocalLanguageLoses() {
        var options = KeyboardOptions()
        options.language = .english

        options.adopt(LanguageChoice(language: .spanish, date: .distantPast))
        options.adopt(nil)

        #expect(options.language == .english)
    }

    @Test func undoNeedsTheCursorAfterTheRewrite() {
        #expect(RewriteUndo.cursorFollows("new text", before: "Hello new text"))
        #expect(RewriteUndo.cursorFollows("a long new text", before: "new text"))
        #expect(!RewriteUndo.cursorFollows("new text", before: "new text and more"))
        #expect(!RewriteUndo.cursorFollows("new text", before: ""))
    }

    @Test func savesLanguage() throws {
        var options = KeyboardOptions()
        options.language = .spanish
        let decoded = try JSONDecoder().decode(KeyboardOptions.self, from: JSONEncoder().encode(options))

        #expect(decoded == options)
        #expect(decoded.language.isSpanish)
        #expect(!KeyboardLanguage.english.isSpanish)
    }
}
