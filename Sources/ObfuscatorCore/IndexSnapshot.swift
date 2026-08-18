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
        if contains(.declaration) { result.append(IndexRole.declaration.rawValue) }
        if contains(.definition) { result.append(IndexRole.definition.rawValue) }
        if contains(.reference) { result.append(IndexRole.reference.rawValue) }
        if contains(.read) { result.append(IndexRole.read.rawValue) }
        if contains(.write) { result.append(IndexRole.write.rawValue) }
        if contains(.call) { result.append(IndexRole.call.rawValue) }
        if contains(.dynamic) { result.append(IndexRole.dynamic.rawValue) }
        if contains(.addressOf) { result.append(IndexRole.addressOf.rawValue) }
        if contains(.implicit) { result.append(IndexRole.implicit.rawValue) }
        if contains(.childOf) { result.append(IndexRole.childOf.rawValue) }
        if contains(.baseOf) { result.append(IndexRole.baseOf.rawValue) }
        if contains(.overrideOf) { result.append(IndexRole.overrideOf.rawValue) }
        if contains(.receivedBy) { result.append(IndexRole.receivedBy.rawValue) }
        if contains(.calledBy) { result.append(IndexRole.calledBy.rawValue) }
        if contains(.extendedBy) { result.append(IndexRole.extendedBy.rawValue) }
        if contains(.accessorOf) { result.append(IndexRole.accessorOf.rawValue) }
        if contains(.containedBy) { result.append(IndexRole.containedBy.rawValue) }
        if contains(.ibTypeOf) { result.append(IndexRole.ibTypeOf.rawValue) }
        if contains(.specializationOf) { result.append(IndexRole.specializationOf.rawValue) }
        if contains(.canonical) { result.append(IndexRole.canonical.rawValue) }
        return result
    }
}
