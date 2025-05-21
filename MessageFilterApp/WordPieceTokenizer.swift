//
//  WordPieceTokenizer.swift
//  MessageFilterApp
//

import Foundation
import CoreML

class WordPieceTokenizer {
    private let vocab: [String: Int]
    private let unkToken = "[UNK]"
    private let maxInputLength: Int

    init(vocab: [String: Int], maxLength: Int = 128) {
        self.vocab = vocab
        self.maxInputLength = maxLength
    }

    static func loadVocab(from file: String) -> [String: Int]? {
        guard let path = Bundle.main.path(forResource: file, ofType: nil),
              let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }
        let tokens = content.components(separatedBy: .newlines)
        var vocab: [String: Int] = [:]
        for (index, token) in tokens.enumerated() where !token.isEmpty {
            vocab[token] = index
        }
        return vocab
    }
    func tokenize(_ text: String) -> ([Int32], [Int32]) {
        let cleaned = text.lowercased()
        var tokens: [String] = []

        for word in cleaned.split(separator: " ") {
            var current = String(word)
            var subTokens: [String] = []

            while !current.isEmpty {
                var match: String? = nil
                var i = current.count
                while i > 0 {
                    let prefix = String(current.prefix(i))
                    let test = subTokens.isEmpty ? prefix : "##" + prefix
                    if vocab[test] != nil {
                        match = test
                        break
                    }
                    i -= 1
                }
                if let matched = match {
                    subTokens.append(matched)
                    current.removeFirst(matched.replacingOccurrences(of: "##", with: "").count)
                } else {
                    subTokens.append(unkToken)
                    break
                }
            }
            tokens.append(contentsOf: subTokens)
        }

        var inputIds = tokens.map { Int32(vocab[$0] ?? vocab[unkToken]!) }
        inputIds = [Int32(vocab["[CLS]"]!)] + inputIds.prefix(maxInputLength - 2) + [Int32(vocab["[SEP]"]!)]

        var attentionMask = Array(repeating: Int32(1), count: inputIds.count)
        while inputIds.count < maxInputLength {
            inputIds.append(0)
            attentionMask.append(0)
        }

        return (inputIds, attentionMask)
    }
}

extension MLMultiArray {
    static func from(_ array: [Int32]) -> MLMultiArray? {
        guard let mlArray = try? MLMultiArray(shape: [NSNumber(value: array.count)], dataType: .int32) else {
            return nil
        }
        for (i, value) in array.enumerated() {
            mlArray[i] = NSNumber(value: value)
        }
        return mlArray
    }
}
