import Foundation
import Testing
@testable import QuietGPT

struct TextLanguageTests {
    private let likely = ["es", "en"]

    @Test func shortSpanishIsNotAnotherLanguage() {
        for text in ["vale", "que tal?", "jajaja si", "mas corta", "si claro", "no se", "pásame el link porfa"] {
            #expect(TextLanguage.code(of: text, likely: likely) == "es", "\(text)")
        }
    }

    @Test func shortEnglishStaysEnglish() {
        for text in ["no problem", "thanks", "no problem tio"] {
            #expect(TextLanguage.code(of: text, likely: likely) == "en", "\(text)")
        }
    }

    @Test func unclearShortWordIsNotTheOtherLanguage() {
        #expect(TextLanguage.code(of: "dime", likely: likely) != "en")
        #expect(TextLanguage.code(of: "genial", likely: likely) != "en")
    }

    @Test func findsCatalan() {
        for text in ["Bon dia, demà no puc venir", "ens veiem a les 8", "vale, fins ara", "gràcies", "escriu un correu al meu cap, que demà no vinc"] {
            #expect(TextLanguage.code(of: text, likely: likely) == "ca", "\(text)")
        }
        #expect(!TextLanguage.isCatalan("Hola Marta, mañana no puedo venir a cenar"))
        #expect(!TextLanguage.isCatalan("hey can u send me the file by tomorrow, thx"))
    }

    @Test func checksCatalanOutput() {
        #expect(!TextLanguage.differs("Bon dia, ho sento molt, però demà no puc venir.", from: "ca"))
        #expect(TextLanguage.differs("Buenos días, lo siento mucho, pero mañana no puedo venir.", from: "ca"))
        #expect(TextLanguage.differs("Bon dia, ho sento molt, però demà no puc venir.", from: "es"))
    }

    @Test func veryShortTextHasNoLanguage() {
        for text in ["ok", "si", "no", "hi", "2+2?", "👍", ""] {
            #expect(TextLanguage.code(of: text, likely: likely) == nil, "\(text)")
        }
    }

    @Test func otherLanguagesAreFound() {
        #expect(TextLanguage.code(of: "je suis en retard, désolé", likely: likely) == "fr")
        #expect(TextLanguage.code(of: "ci vediamo domani alle 8", likely: likely) == "it")
        #expect(TextLanguage.code(of: "こんにちは、元気ですか", likely: likely) == "ja")
    }

    @Test func mixedWordsKeepTheMainLanguage() {
        #expect(TextLanguage.single(of: "Envíame el PDF del meeting cuando puedas", likely: likely) == "es")
        #expect(TextLanguage.single(of: "tengo una reunion con el team de marketing", likely: likely) == "es")
    }

    @Test func twoLanguagesGiveNoSingleLanguage() {
        let text = "resume esto en pocas palabras: The quick brown fox jumps over the lazy dog near the old river bank."

        #expect(TextLanguage.single(of: text, likely: likely) == nil)
    }

    @Test func findsOutputInAnotherLanguage() {
        #expect(TextLanguage.differs("Hi Marta, I'm so sorry but I can't come to dinner tomorrow.", from: "es"))
        #expect(TextLanguage.differs("Está bem, obrigado pela mensagem", from: "es"))
        #expect(TextLanguage.differs("Hola Marta, lo siento mucho pero mañana no puedo ir.", from: "en"))
    }

    @Test func acceptsOutputInTheSameLanguage() {
        #expect(!TextLanguage.differs("Hola Marta, lo siento mucho pero mañana no voy a poder ir a cenar.", from: "es"))
        #expect(!TextLanguage.differs("Envíame el PDF del meeting cuando puedas, por favor.", from: "es"))
        #expect(!TextLanguage.differs("Hey, could you send me the file by tomorrow? Thanks!", from: "en"))
        #expect(!TextLanguage.differs("mas corta", from: "es"))
        #expect(!TextLanguage.differs("¡Vale!", from: "es"))
        #expect(!TextLanguage.differs("Okay!", from: "es"))
    }

    @Test func findsRequestsThatSetTheLanguage() {
        for request in ["Translate this message into natural English.", "Tradúcelo al francés", "en inglés", "Write it in German", "ponlo en català"] {
            #expect(TextLanguage.namesLanguage(request, likely: likely), "\(request)")
        }
    }

    @Test func otherRequestsDoNotSetTheLanguage() {
        for request in ["Make this message kinder and warmer. Keep the same meaning.", "más informal", "hazlo más corto", "No emoji", "Sign as Pep", ""] {
            #expect(!TextLanguage.namesLanguage(request, likely: likely), "\(request)")
        }
    }

    @Test func builtInStylesKeepTheLanguageExceptTranslations() {
        let keeps = Dictionary(uniqueKeysWithValues: RewriteStyle.builtIn.map {
            ($0.id.uuidString.suffix(1), Rewriter.keepsLanguage(request: $0.prompt, rules: [], likely: likely))
        })

        #expect(keeps == ["1": true, "2": true, "3": true, "4": true, "5": true, "6": false, "7": false])
    }

    @Test func aRuleAboutLanguageStopsTheCheck() {
        #expect(!Rewriter.keepsLanguage(request: "Make it short.", rules: ["Always write in English"], likely: likely))
        #expect(Rewriter.keepsLanguage(request: "Make it short.", rules: ["No emoji"], likely: likely))
    }

    @Test func promptUsesTheGivenLanguage() {
        let prompt = Rewriter.prompt(request: "Make it short.", text: "vale", language: "es")

        #expect(prompt.hasSuffix("Message (in Spanish):\nvale"))
        #expect(prompt.contains("Rewrite it.\n"))
    }

    @Test func firmPromptNamesTheLanguage() {
        let prompt = Rewriter.prompt(request: "Make it short.", text: "vale", language: "es", firm: true)

        #expect(prompt.contains("Rewrite it in Spanish.\n"))
    }

    @Test func chatExpectsTheLanguageOfThePrompt() {
        #expect(ReplyEngine.language(of: "dame una receta de tortilla", after: [], likely: likely) == "es")
        #expect(ReplyEngine.language(of: "what is the capital of Spain?", after: [], likely: likely) == "en")
    }

    @Test func chatUsesTheEarlierLanguageForVeryShortPrompts() {
        let history = [ChatTurn(role: .user, text: "capital de francia"), ChatTurn(role: .assistant, text: "París.")]

        #expect(ReplyEngine.language(of: "ok", after: history, likely: likely) == "es")
        #expect(ReplyEngine.language(of: "ok", after: [], likely: likely) == nil)
    }

    @Test func chatDoesNotCheckWhenTheUserSetsTheLanguage() {
        let history = [ChatTurn(role: .user, text: "escribe un email en inglés a mi jefe"), ChatTurn(role: .assistant, text: "Dear Mr. Smith,")]

        #expect(ReplyEngine.language(of: "traduce buenos días al francés", after: [], likely: likely) == nil)
        #expect(ReplyEngine.language(of: "hazlo más corto", after: history, likely: likely) == nil)
    }

    @Test func chatRetryNamesTheLanguage() {
        #expect(ReplyEngine.firm("capital de francia", in: "es") == "capital de francia\n\nReply in Spanish.")
    }
}
