// NaturalLanguageProbe.swift — direct Swift-module acceptance probe.
// It intentionally imports NaturalLanguage in Swift, while the embedding
// runtime test uses NativeNLBridge.m separately.
import Foundation
import NaturalLanguage

public enum NaturalLanguageProbe {
    public static var portugueseSentenceModelAvailable: Bool {
        NLEmbedding.sentenceEmbedding(for: NLLanguage.portuguese) != nil
    }
}
