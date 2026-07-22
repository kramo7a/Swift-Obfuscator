import Foundation
import IndexStoreDB

public struct SymbolRecord: Codable, Hashable, Sendable {
    public let usr: String
    public let name: String
    public let kind: String
    public let language: String
    public let propertiesRaw: UInt64
    public let properties: String

    public init(usr: String, name: String, kind: String, language: String, propertiesRaw: UInt64, properties: String) {
        self.usr = usr
        self.name = name
        self.kind = kind
        self.language = language
        self.propertiesRaw = propertiesRaw
        self.properties = properties
    }
}

public struct RelationRecord: Codable, Hashable, Sendable {
    public let usr: String
    public let name: String
    public let rolesRaw: UInt64
    public let roles: [String]
}

public struct OccurrenceRecord: Codable, Hashable, Sendable {
    public let symbol: SymbolRecord
    public let path: String
    public let line: Int
    public let utf8Column: Int
    public let moduleName: String
    public let isSystem: Bool
    public let rolesRaw: UInt64
    public let roles: [String]
    public let rolesDescription: String
    public let symbolProvider: String
    public let relations: [RelationRecord]

    public var usr: String {
        symbol.usr
    }
}

public struct USROccurrenceGroup: Sendable {
    public let usr: String
    public let symbol: SymbolRecord
    public let occurrences: [OccurrenceRecord]
}

public struct IndexSnapshot: Sendable {
    public let sourceFiles: [String]
    public let symbols: [SymbolRecord]
    public let occurrences: [OccurrenceRecord]

    public var groupsByUSR: [USROccurrenceGroup] {
        let grouped = Dictionary(grouping: occurrences, by: \.usr)
        return grouped.compactMap { usr, occurrences in
            guard let symbol = occurrences.first?.symbol else {
                return nil
            }
            return USROccurrenceGroup(
                usr: usr,
                symbol: symbol,
                occurrences: occurrences.sorted { lhs, rhs in
                    (lhs.path, lhs.line, lhs.utf8Column, lhs.rolesRaw) < (rhs.path, rhs.line, rhs.utf8Column, rhs.rolesRaw)
                }
            )
        }
        .sorted { lhs, rhs in
            (lhs.symbol.name, lhs.usr) < (rhs.symbol.name, rhs.usr)
        }
    }
}

extension SymbolRecord {
    init(_ symbol: Symbol) {
        self.init(
            usr: symbol.usr,
            name: symbol.name,
            kind: String(describing: symbol.kind),
            language: String(describing: symbol.language),
            propertiesRaw: symbol.properties.rawValue,
            properties: String(describing: symbol.properties)
        )
    }
}

extension OccurrenceRecord {
    init(_ occurrence: SymbolOccurrence) {
        self.init(
            symbol: SymbolRecord(occurrence.symbol),
            path: occurrence.location.path,
            line: occurrence.location.line,
            utf8Column: occurrence.location.utf8Column,
            moduleName: occurrence.location.moduleName,
            isSystem: occurrence.location.isSystem,
            rolesRaw: occurrence.roles.rawValue,
            roles: occurrence.roles.names,
            rolesDescription: String(describing: occurrence.roles),
            symbolProvider: String(describing: occurrence.symbolProvider),
            relations: occurrence.relations.map(RelationRecord.init)
        )
    }
}

extension RelationRecord {
    init(_ relation: SymbolRelation) {
        self.init(
            usr: relation.symbol.usr,
            name: relation.symbol.name,
            rolesRaw: relation.roles.rawValue,
            roles: relation.roles.names
        )
    }
}

private extension SymbolRole {
    var names: [String] {
        var result: [String] = []
        if contains(.declaration) { result.append("declaration") }
        if contains(.definition) { result.append("definition") }
        if contains(.reference) { result.append("reference") }
        if contains(.read) { result.append("read") }
        if contains(.write) { result.append("write") }
        if contains(.call) { result.append("call") }
        if contains(.dynamic) { result.append("dynamic") }
        if contains(.addressOf) { result.append("addressOf") }
        if contains(.implicit) { result.append("implicit") }
        if contains(.childOf) { result.append("childOf") }
        if contains(.baseOf) { result.append("baseOf") }
        if contains(.overrideOf) { result.append("overrideOf") }
        if contains(.receivedBy) { result.append("receivedBy") }
        if contains(.calledBy) { result.append("calledBy") }
        if contains(.extendedBy) { result.append("extendedBy") }
        if contains(.accessorOf) { result.append("accessorOf") }
        if contains(.containedBy) { result.append("containedBy") }
        if contains(.ibTypeOf) { result.append("ibTypeOf") }
        if contains(.specializationOf) { result.append("specializationOf") }
        if contains(.canonical) { result.append("canonical") }
        return result
    }
}
