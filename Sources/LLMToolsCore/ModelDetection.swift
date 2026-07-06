import Foundation

public enum ModelDetectionError: Error, LocalizedError, Sendable {
    case pathDoesNotExist(URL)
    case unsupported(URL)
    case multipleGGUFFiles(URL)

    public var errorDescription: String? {
        switch self {
        case .pathDoesNotExist(let url):
            return "Model path does not exist: \(url.path)"
        case .unsupported(let url):
            return "Unsupported model location: \(url.path)"
        case .multipleGGUFFiles(let url):
            return "Multiple GGUF files were found in \(url.path). Pick the exact file to use."
        }
    }
}

public enum ModelDetection {
    public static func detect(from url: URL) throws -> (format: ModelFormat, resolvedPath: URL, sizeClass: String) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            throw ModelDetectionError.pathDoesNotExist(url)
        }

        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            let contents = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
            let ggufFiles = contents.filter { $0.pathExtension.lowercased() == "gguf" }
            if ggufFiles.count == 1 {
                return (.gguf, ggufFiles[0], inferSizeClass(from: ggufFiles[0].lastPathComponent))
            }
            if ggufFiles.count > 1 {
                let primaryGGUFFiles = ggufFiles.filter { !isMMProjFile($0) }
                if primaryGGUFFiles.count == 1 {
                    return (.gguf, primaryGGUFFiles[0], inferSizeClass(from: primaryGGUFFiles[0].lastPathComponent))
                }
                throw ModelDetectionError.multipleGGUFFiles(url)
            }

            if containsMLXFiles(in: contents) {
                return (.mlx, url, inferSizeClass(from: url.lastPathComponent))
            }

            if let nestedGGUF = try firstGGUFFileRecursively(in: url) {
                return (.gguf, nestedGGUF, inferSizeClass(from: nestedGGUF.lastPathComponent))
            }

            throw ModelDetectionError.unsupported(url)
        }

        if url.pathExtension.lowercased() == "gguf" {
            return (.gguf, url, inferSizeClass(from: url.lastPathComponent))
        }

        throw ModelDetectionError.unsupported(url)
    }

    public static func isLocalVisionModel(at url: URL) -> Bool {
        guard let directory = localModelDirectory(for: url) else {
            return false
        }
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ), containsMLXFiles(in: contents) else {
            return false
        }
        guard let config = jsonDictionary(at: directory.appendingPathComponent("config.json")) else {
            return false
        }

        let hasVisionConfig = config["vision_config"] != nil
            || config["image_token_id"] != nil
            || config["vision_start_token_id"] != nil
            || config["vision_end_token_id"] != nil
        guard hasVisionConfig else {
            return false
        }

        let processorFiles = [
            "processor_config.json",
            "preprocessor_config.json",
            "video_preprocessor_config.json"
        ]
        let processorText = processorFiles
            .compactMap { try? String(contentsOf: directory.appendingPathComponent($0), encoding: .utf8) }
            .joined(separator: "\n")
            .lowercased()
        if processorText.contains("vlprocessor")
            || processorText.contains("vision")
            || processorText.contains("image_processor")
            || processorText.contains("imageprocessor") {
            return true
        }

        return false
    }

    private static func containsMLXFiles(in contents: [URL]) -> Bool {
        let names = Set(contents.map { $0.lastPathComponent.lowercased() })
        let hasConfig = names.contains("config.json")
        let hasTokenizer = names.contains("tokenizer.json") || names.contains("tokenizer.model") || names.contains("tokenizer_config.json")
        let hasWeights = contents.contains { $0.pathExtension.lowercased() == "safetensors" || $0.pathExtension.lowercased() == "npz" }
        return hasConfig && hasTokenizer && hasWeights
    }

    private static func firstGGUFFileRecursively(in directory: URL) throws -> URL? {
        let fm = FileManager.default
        var fallback: URL?
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return nil
        }
        while let element = enumerator.nextObject() {
            if let url = element as? URL, url.pathExtension.lowercased() == "gguf" {
                if isMMProjFile(url) {
                    fallback = fallback ?? url
                } else {
                    return url
                }
            }
        }
        return fallback
    }

    private static func inferSizeClass(from name: String) -> String {
        let lower = name.lowercased()
        for token in ["35b", "30b", "27b", "14b", "9b", "7b", "4b", "1.5b", "0.8b", "0.5b"] {
            if containsBoundedToken(token, in: lower) {
                return token
            }
        }
        return "custom"
    }

    private static func isMMProjFile(_ url: URL) -> Bool {
        url.deletingPathExtension().lastPathComponent.lowercased().contains("mmproj")
    }

    private static func localModelDirectory(for url: URL) -> URL? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return nil
        }
        return isDirectory.boolValue ? url : url.deletingLastPathComponent()
    }

    private static func jsonDictionary(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        return dictionary
    }

    private static func containsBoundedToken(_ token: String, in text: String) -> Bool {
        var searchStart = text.startIndex
        while let range = text.range(of: token, range: searchStart..<text.endIndex) {
            let beforeIsBoundary = range.lowerBound == text.startIndex || isBoundary(text[text.index(before: range.lowerBound)])
            let afterIsBoundary = range.upperBound == text.endIndex || isBoundary(text[range.upperBound])
            if beforeIsBoundary && afterIsBoundary {
                return true
            }
            searchStart = range.upperBound
        }
        return false
    }

    private static func isBoundary(_ character: Character) -> Bool {
        !(character.isLetter || character.isNumber)
    }
}
