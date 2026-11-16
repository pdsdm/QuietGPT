#if DEBUG
import CoreML
import Foundation
import os

enum CoreMLPlanReport {
    private static let logger = Logger(subsystem: "QuietGPT", category: "coreml")

    static func run(compiledFolder: URL) async {
        let files = (try? FileManager.default.contentsOfDirectory(at: compiledFolder, includingPropertiesForKeys: nil)) ?? []
        let models = files.filter { $0.pathExtension == "mlmodelc" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        if models.isEmpty {
            logger.error("Compute plan: no compiled parts in \(compiledFolder.path, privacy: .public)")
        }
        for url in models {
            for function in await functions(url) {
                let configuration = MLModelConfiguration()
                configuration.computeUnits = .cpuAndNeuralEngine
                configuration.functionName = function
                do {
                    let plan = try await MLComputePlan.load(contentsOf: url, configuration: configuration)
                    guard case .program(let program) = plan.modelStructure else { continue }
                    let name = function ?? "main"
                    guard let body = program.functions[name] ?? program.functions.first?.value else { continue }
                    var counts: [String: Int] = [:]
                    var others: [String: Int] = [:]
                    visit(body.block, plan: plan) { operation, device in
                        counts[device, default: 0] += 1
                        if device != "ANE" {
                            others[operation.operatorName, default: 0] += 1
                        }
                    }
                    let summary = counts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
                    let detail = others.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
                    logger.notice("Compute plan \(url.lastPathComponent, privacy: .public) \(name, privacy: .public): \(summary, privacy: .public)\(detail.isEmpty ? "" : " · not ANE: " + detail, privacy: .public)")
                } catch {
                    logger.error("Compute plan \(url.lastPathComponent, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                }
            }
        }
        logger.notice("Compute plan done")
    }

    private static func functions(_ url: URL) async -> [String?] {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        guard let plan = try? await MLComputePlan.load(contentsOf: url, configuration: configuration),
              case .program(let program) = plan.modelStructure
        else { return [nil] }
        let names = program.functions.keys.sorted()
        return names.count > 1 ? names : [nil]
    }

    private static func visit(_ block: MLModelStructure.Program.Block, plan: MLComputePlan, count: (MLModelStructure.Program.Operation, String) -> Void) {
        for operation in block.operations {
            if let usage = plan.deviceUsage(for: operation) {
                let device = switch usage.preferred {
                case .neuralEngine: "ANE"
                case .gpu: "GPU"
                case .cpu: "CPU"
                @unknown default: "other"
                }
                count(operation, device)
            }
            for inner in operation.blocks {
                visit(inner, plan: plan, count: count)
            }
        }
    }
}
#endif
