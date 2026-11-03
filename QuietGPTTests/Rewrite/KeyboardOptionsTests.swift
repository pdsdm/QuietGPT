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

    @Test func savesLanguage() throws {
        var options = KeyboardOptions()
        options.language = .spanish
        let decoded = try JSONDecoder().decode(KeyboardOptions.self, from: JSONEncoder().encode(options))

        #expect(decoded == options)
        #expect(decoded.language.isSpanish)
        #expect(!KeyboardLanguage.english.isSpanish)
    }
}
