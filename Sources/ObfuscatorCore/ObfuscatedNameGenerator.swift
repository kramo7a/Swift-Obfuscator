import Foundation

public struct ObfuscatedNameGenerator: Sendable {
    public var prefix: String
    private var counter: Int

    public init(prefix: String = "O", start: Int = 0) {
        self.prefix = prefix
        self.counter = start
    }

    public mutating func nextName(avoiding reserved: Set<String>) -> String {
        while true {
            let candidate = prefix + Self.encoded(counter)
            counter += 1
            if !reserved.contains(candidate), isPlainSwiftIdentifier(candidate) {
                return candidate
            }
        }
    }

    private static func encoded(_ value: Int) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        var number = value
        var characters: [Character] = []
        repeat {
            characters.append(alphabet[number % alphabet.count])
            number /= alphabet.count
        } while number > 0
        return String(characters.reversed())
    }
}
