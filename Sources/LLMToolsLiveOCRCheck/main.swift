import AppKit
import Foundation
import LLMToolsCore

@main
struct LLMToolsLiveOCRCheck {
    static func main() async throws {
        let options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
        let engine = TaskEngine()
        await engine.bootstrap()

        let model = try await ensureVisionModel(options: options, engine: engine)
        try await configureOCRDefaults(modelID: model.id, engine: engine)

        let probe = try await engine.testVisionCapability(id: model.id)
        let registry = await engine.registry()
        let image = try await MainActor.run {
            try makeFixtureImage(preferences: registry.preferences.ocr)
        }

        let ocr = try await engine.runOCR(
            image: image,
            mode: .plainText,
            modelID: model.id,
            persistHistory: false
        )
        try requireOCRText(ocr.text)

        let explanation = try await engine.runOCR(
            image: image,
            mode: .explainImage,
            modelID: model.id,
            persistHistory: false
        )
        guard !explanation.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LiveOCRCheckError("Image explanation returned empty output.")
        }

        print("LLMToolsLiveOCRCheck passed")
        print("Model: \(model.name) (\(model.apiModelID ?? model.id.uuidString))")
        print("Model ID: \(model.id.uuidString)")
        print("Probe output: \(oneLine(probe.message, limit: 180))")
        print("OCR output: \(oneLine(ocr.text, limit: 240))")
        print("Explanation output: \(oneLine(explanation.text, limit: 240))")
    }

    private static func ensureVisionModel(options: Options, engine: TaskEngine) async throws -> ModelDescriptor {
        let snapshot = await engine.registry()
        if let explicitID = options.existingModelID {
            guard let model = snapshot.models.first(where: { $0.id == explicitID }) else {
                throw LiveOCRCheckError("Model \(explicitID.uuidString) was not found in the registry.")
            }
            return model
        }

        if let existing = snapshot.models.first(where: {
            $0.providerConfiguration?.apiStyle == .openAICompatible
                && $0.providerConfiguration?.modelID == options.providerModelID
        }) {
            if existing.capabilities.supportsImage {
                return existing
            }
            return try await engine.resetModelCapabilities(id: existing.id)
        }

        guard let template = snapshot.models.first(where: {
            guard let configuration = $0.providerConfiguration else { return false }
            return $0.enabled
                && configuration.apiStyle == .openAICompatible
                && configuration.baseURL != nil
                && !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }), let configuration = template.providerConfiguration, let baseURL = configuration.baseURL else {
            throw LiveOCRCheckError(
                "No configured OpenAI-compatible provider model with an inline API key was found. Add a provider model first."
            )
        }

        return try await engine.addProviderModel(
            providerID: configuration.providerID,
            name: "\(template.providerDisplayName) · \(options.providerModelID)",
            modelID: options.providerModelID,
            apiKey: configuration.apiKey,
            baseURL: baseURL.absoluteString,
            contextLength: template.contextLength
        )
    }

    private static func configureOCRDefaults(modelID: UUID, engine: TaskEngine) async throws {
        try await engine.updatePreferences { preferences in
            preferences.ocr.enabled = true
            preferences.ocr.modelID = modelID
            preferences.ocr.defaultMode = .plainText
            preferences.ocr.useModelRecognitionByDefault = true
            preferences.ocr.persistHistory = false
        }
    }

    @MainActor
    private static func makeFixtureImage(preferences: OCRPreferences) throws -> OCRImageInput {
        let size = NSSize(width: 960, height: 420)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 64, weight: .bold),
            .foregroundColor: NSColor.black
        ]
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 34, weight: .regular),
            .foregroundColor: NSColor.black
        ]
        NSString(string: "LLMTOOLS OCR 2026").draw(
            in: NSRect(x: 72, y: 235, width: 820, height: 90),
            withAttributes: titleAttributes
        )
        NSString(string: "Phase 3 live vision check").draw(
            in: NSRect(x: 72, y: 155, width: 820, height: 58),
            withAttributes: subtitleAttributes
        )
        NSString(string: "Plain text mode + image explanation").draw(
            in: NSRect(x: 72, y: 95, width: 820, height: 52),
            withAttributes: subtitleAttributes
        )
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw LiveOCRCheckError("Could not generate OCR fixture image.")
        }
        return try OCRImagePreprocessor.normalizeImageData(
            png,
            preferences: preferences,
            fileName: "phase3-live-ocr.png",
            sourceDescription: "Generated live OCR fixture"
        )
    }

    private static func requireOCRText(_ text: String) throws {
        let normalized = text
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        guard normalized.contains("llmtools"), normalized.contains("2026") else {
            throw LiveOCRCheckError("OCR output did not contain the fixture text markers: \(oneLine(text, limit: 240))")
        }
    }

    private static func oneLine(_ value: String, limit: Int) -> String {
        let collapsed = value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if collapsed.count <= limit {
            return collapsed
        }
        let end = collapsed.index(collapsed.startIndex, offsetBy: limit)
        return String(collapsed[..<end]) + "..."
    }
}

private struct Options {
    var providerModelID: String = "Qwen/Qwen3-VL-8B-Instruct"
    var existingModelID: UUID?

    static func parse(_ args: [String]) throws -> Options {
        var options = Options()
        var index = 0
        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--provider-model":
                index += 1
                guard index < args.count else {
                    throw LiveOCRCheckError("--provider-model requires a model ID.")
                }
                options.providerModelID = args[index]
            case "--model-id":
                index += 1
                guard index < args.count, let id = UUID(uuidString: args[index]) else {
                    throw LiveOCRCheckError("--model-id requires a registry UUID.")
                }
                options.existingModelID = id
            case "--help", "-h":
                print("""
                Usage:
                  swift run LLMToolsLiveOCRCheck [--provider-model <provider-model-id>]
                  swift run LLMToolsLiveOCRCheck --model-id <registry-uuid>

                The check uses the real llmTools registry, configures the selected model as the OCR model,
                runs a live vision probe, OCRs a generated text image, and runs image explanation.
                """)
                Foundation.exit(0)
            default:
                throw LiveOCRCheckError("Unknown argument: \(arg)")
            }
            index += 1
        }
        return options
    }
}

private struct LiveOCRCheckError: Error, CustomStringConvertible, LocalizedError {
    var description: String
    var errorDescription: String? { description }

    init(_ description: String) {
        self.description = description
    }
}
