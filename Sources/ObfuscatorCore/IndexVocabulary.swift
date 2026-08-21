import Foundation

/// Stable names emitted by IndexStoreDB for Swift declaration kinds.
///
/// `IndexSnapshot.Symbol` keeps the original string so snapshots remain forward-compatible
/// with symbol kinds introduced by newer toolchains. Core code should use these
/// cases instead of repeating the wire-format strings.
enum IndexSymbolKind: String, Sendable {
    case actor
    case `class`
    case classMethod
    case classProperty
    case constructor
    case `enum`
    case enumConstant
    case `extension`
    case function
    case instanceMethod
    case instanceProperty
    case parameter
    case `protocol`
    case staticMethod
    case staticProperty
    case `struct`
    case `typealias`
    case variable

    static func rawValues(_ kinds: Self...) -> Set<String> {
        Set(kinds.map(\.rawValue))
    }
}

/// Stable role names emitted by IndexStoreDB for occurrences and relations.
enum IndexRole: String, CaseIterable, Sendable {
    case declaration
    case definition
    case reference
    case read
    case write
    case call
    case dynamic
    case addressOf
    case implicit
    case childOf
    case baseOf
    case overrideOf
    case receivedBy
    case calledBy
    case extendedBy
    case accessorOf
    case containedBy
    case ibTypeOf
    case specializationOf
    case canonical

    static let lexicalRawValues = Set(
        [
            Self.declaration,
            .definition,
            .reference,
            .read,
            .write,
            .call,
            .dynamic,
            .addressOf,
        ].map(\.rawValue)
    )
}

enum IndexUSR {
    private static let objectiveCCompatiblePrefix = "c:"

    static func isObjectiveCCompatible(_ usr: String) -> Bool {
        usr.hasPrefix(objectiveCCompatiblePrefix)
    }
}

enum IndexSymbolName {
    static let getterPrefix = "getter:"
    static let setterPrefix = "setter:"

    static func isSyntheticAccessor(_ name: String) -> Bool {
        let lowercasedName = name.lowercased()
        return lowercasedName.hasPrefix(getterPrefix) || lowercasedName.hasPrefix(setterPrefix)
    }
}

extension IndexSnapshot.Symbol {
    func isKind(_ expectedKind: IndexSymbolKind) -> Bool {
        kind == expectedKind.rawValue
    }
}

extension IndexSnapshot.Occurrence {
    func hasRole(_ role: IndexRole) -> Bool {
        roles.contains(role.rawValue)
    }
}

extension IndexSnapshot.Relation {
    func hasRole(_ role: IndexRole) -> Bool {
        roles.contains(role.rawValue)
    }
}
