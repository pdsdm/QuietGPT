import Testing
@testable import QuietGPT

struct LFMPromptTests {
    @Test func rendersTheChatTemplateWithThinkingOff() {
        let history = [ChatTurn(role: .user, text: "Hi"), ChatTurn(role: .assistant, text: "Hello!")]
        let text = LFMPrompt.text(history: history, prompt: "Q2", thinking: false)

        #expect(text.hasPrefix("<|startoftext|><|im_start|>system\nYou are QuietGPT, a private assistant on the user's iPhone."))
        #expect(text.hasSuffix("<|im_end|>\n<|im_start|>user\nHi<|im_end|>\n<|im_start|>assistant\n<think></think>Hello!<|im_end|>\n<|im_start|>user\nQ2<|im_end|>\n<|im_start|>assistant\n<think></think>"))
    }

    @Test func opensTheThinkingBlockWhenThinkingIsOn() {
        #expect(LFMPrompt.text(history: [], prompt: "Q", thinking: true).hasSuffix("<|im_start|>assistant\n<think>"))
    }

    @Test func nextTurnContinuesTheSameText() {
        let history = [ChatTurn(role: .user, text: "Hi"), ChatTurn(role: .assistant, text: "Hello!")]
        let first = LFMPrompt.text(history: history, prompt: "Q2", thinking: false)
        let continued = first + "A2" + LFMPrompt.next(prompt: "Q3", thinking: false)
        let full = LFMPrompt.text(history: history + [ChatTurn(role: .user, text: "Q2"), ChatTurn(role: .assistant, text: "A2")], prompt: "Q3", thinking: false)

        #expect(continued == full)
    }

    @Test func removesAThinkingLeak() {
        let reply = "The user wants a short answer.</think>Paris is the capital of France."

        #expect(LFMPrompt.clean(reply, thinking: false, final: true) == "Paris is the capital of France.")
    }

    @Test func showsNothingWhileItThinks() {
        #expect(LFMPrompt.clean("Let me plan the steps", thinking: true, final: false) == "")
        #expect(LFMPrompt.clean("Plan.</think>Done.", thinking: true, final: false) == "Done.")
    }

    @Test func removesASignature() {
        #expect(LFMPrompt.clean("See you at six.\n\nQuietGPT", thinking: false, final: true) == "See you at six.")
        #expect(LFMPrompt.clean("See you at six. QuietGPT", thinking: false, final: true) == "See you at six.")
    }

    @Test func removesAClosingOffer() {
        let reply = "Keep one wake time.\n\nDim the lights an hour before bed. Would you like more tips?"

        #expect(LFMPrompt.clean(reply, thinking: false, final: true) == "Keep one wake time.\n\nDim the lights an hour before bed.")
        #expect(LFMPrompt.clean("Bed by ten.\n\n¿Quieres más ideas?", thinking: false, final: true) == "Bed by ten.")
    }

    @Test func keepsARealQuestionAndTheIdentityAnswer() {
        #expect(LFMPrompt.clean("Is it today or tomorrow?", thinking: false, final: true) == "Is it today or tomorrow?")
        #expect(LFMPrompt.clean("I'm QuietGPT, a private assistant that runs on your iPhone.", thinking: false, final: true) == "I'm QuietGPT, a private assistant that runs on your iPhone.")
    }
}
