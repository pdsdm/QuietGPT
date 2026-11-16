import CoreML
import Foundation

struct Case: Decodable {
    let id: String
    let text: String?
    let ids: [Int32]
    let greedy: [Int32]
}

let arguments = CommandLine.arguments
let core = CoreMLCore(folder: URL(fileURLWithPath: arguments[1]), compiledFolder: URL(fileURLWithPath: arguments[3]))
let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: URL(fileURLWithPath: arguments[2])))
let loadStart = Date()
try core.load()
print(String(format: "load %.2f s", Date().timeIntervalSince(loadStart)))
var allMatch = true
for item in cases {
    var tokens = "-"
    if let text = item.text {
        tokens = try core.tokenize(text) == item.ids ? "same" : "DIFFERENT"
        allMatch = allMatch && tokens == "same"
    }
    var reused = 0
    let prefillStart = Date()
    if let text = item.text, let end = text.range(of: "<|im_end|>\n") {
        reused = try core.begin(prefix: String(text[..<end.upperBound]), ids: item.ids)
    } else {
        try core.reset()
    }
    var logits = try core.feed(Array(item.ids[reused...]))
    let prefill = Date().timeIntervalSince(prefillStart)
    var output: [Int32] = []
    let decodeStart = Date()
    for _ in item.greedy {
        let token = logits.withUnsafeBufferPointer(CoreMLSampler.argmax)
        output.append(token)
        logits = try core.step(token)
    }
    let decode = Date().timeIntervalSince(decodeStart)
    let prefix = zip(output, item.greedy).prefix { $0 == $1 }.count
    let same = zip(output, item.greedy).filter { $0 == $1 }.count
    allMatch = allMatch && prefix == item.greedy.count
    print(String(format: "%-16@ reused %3d  prompt %4d  tokens %@  first diff at %2d/%d  same %2d  prefill %.2f s  decode %.1f tok/s",
                 item.id as NSString, reused, item.ids.count, tokens, prefix, item.greedy.count, same, prefill, Double(item.greedy.count) / decode))
}
print(allMatch ? "ALL MATCH" : "DIFFERENCES")

enum TextEngineError: Error {
    case notReady
    case tooLong
    case failed
}
