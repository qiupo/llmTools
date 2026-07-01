import Foundation

public enum InputSizePolicy {
    public static let fallbackContextLength = 4096
    public static let maximumInputCharacters = 12_000
    public static let automaticSelectionMaximumCharacters = 6_000
    public static let reservedPromptAndResponseCharacters = 1_024

    public static func maximumInputCharacters(forContextLength contextLength: Int?) -> Int {
        let resolvedContextLength = max(contextLength ?? fallbackContextLength, 1)
        let contextBound = max(1_000, resolvedContextLength - reservedPromptAndResponseCharacters)
        return min(maximumInputCharacters, contextBound)
    }

    public static func maximumAutomaticSelectionCharacters(forContextLength contextLength: Int?) -> Int {
        min(automaticSelectionMaximumCharacters, maximumInputCharacters(forContextLength: contextLength))
    }
}
