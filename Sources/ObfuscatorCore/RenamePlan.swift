import Foundation

public struct RenamePlanEntry: Codable, Sendable {
    public let usr: String
    public let kind: String
    public let oldName: String
    public let newName: String
    public let replacements: [SourceReplacement]
}

public struct RenamePlan: Codable, Sendable {
    public let entries: [RenamePlanEntry]
    public let denied: [SafetyDecision]
    public let conflicts: [String]
    public let supportReplacements: [SourceReplacement]
    public let parameterFacts: ParameterFactsSummary
    public let parameterSyntaxFacts: ParameterSyntaxFactsSummary
    public let parameterCallSiteSyntaxFacts: ParameterCallSiteSyntaxFactsSummary
    public let parameterCallArgumentBindingFacts: ParameterCallArgumentBindingFactsSummary
    public let parameterCallableReferenceSyntaxFacts: ParameterCallableReferenceSyntaxFactsSummary
    public let parameterCallableReferenceBindingFacts: ParameterCallableReferenceBindingFactsSummary
    public let parameterExternalLabelComponentFacts: ParameterExternalLabelComponentFactsSummary
    public let parameterExternalLabelRenameOutcome: ParameterExternalLabelRenameOutcomeSummary
    public let parameterLocalBindingOutcome: ParameterLocalBindingOutcomeSummary
    public let enumCaseComponentFacts: EnumCaseComponentFactsSummary
    public let compilerRawValueFacts: CompilerRawValueFactsSummary
    public let enumCaseSyntaxFacts: EnumCaseSyntaxFactsSummary
    public let genericParameterSyntaxFacts: GenericParameterSyntaxFactsSummary
    public let typealiasSyntaxFacts: TypealiasSyntaxFactsSummary

    public init(
        entries: [RenamePlanEntry],
        denied: [SafetyDecision],
        conflicts: [String],
        supportReplacements: [SourceReplacement] = [],
        parameterFacts: ParameterFactsSummary = .empty,
        parameterSyntaxFacts: ParameterSyntaxFactsSummary = .empty,
        parameterCallSiteSyntaxFacts: ParameterCallSiteSyntaxFactsSummary = .empty,
        parameterCallArgumentBindingFacts: ParameterCallArgumentBindingFactsSummary = .empty,
        parameterCallableReferenceSyntaxFacts: ParameterCallableReferenceSyntaxFactsSummary = .empty,
        parameterCallableReferenceBindingFacts: ParameterCallableReferenceBindingFactsSummary = .empty,
        parameterExternalLabelComponentFacts: ParameterExternalLabelComponentFactsSummary = .empty,
        parameterExternalLabelRenameOutcome: ParameterExternalLabelRenameOutcomeSummary = .empty,
        parameterLocalBindingOutcome: ParameterLocalBindingOutcomeSummary = .empty,
        enumCaseComponentFacts: EnumCaseComponentFactsSummary = .empty,
        compilerRawValueFacts: CompilerRawValueFactsSummary = .empty,
        enumCaseSyntaxFacts: EnumCaseSyntaxFactsSummary = .empty,
        genericParameterSyntaxFacts: GenericParameterSyntaxFactsSummary = .empty,
        typealiasSyntaxFacts: TypealiasSyntaxFactsSummary = .empty
    ) {
        self.entries = entries
        self.denied = denied
        self.conflicts = conflicts
        self.supportReplacements = supportReplacements
        self.parameterFacts = parameterFacts
        self.parameterSyntaxFacts = parameterSyntaxFacts
        self.parameterCallSiteSyntaxFacts = parameterCallSiteSyntaxFacts
        self.parameterCallArgumentBindingFacts = parameterCallArgumentBindingFacts
        self.parameterCallableReferenceSyntaxFacts = parameterCallableReferenceSyntaxFacts
        self.parameterCallableReferenceBindingFacts = parameterCallableReferenceBindingFacts
        self.parameterExternalLabelComponentFacts = parameterExternalLabelComponentFacts
        self.parameterExternalLabelRenameOutcome = parameterExternalLabelRenameOutcome
        self.parameterLocalBindingOutcome = parameterLocalBindingOutcome
        self.enumCaseComponentFacts = enumCaseComponentFacts
        self.compilerRawValueFacts = compilerRawValueFacts
        self.enumCaseSyntaxFacts = enumCaseSyntaxFacts
        self.genericParameterSyntaxFacts = genericParameterSyntaxFacts
        self.typealiasSyntaxFacts = typealiasSyntaxFacts
    }

    private enum CodingKeys: String, CodingKey {
        case entries
        case denied
        case conflicts
        case supportReplacements
        case parameterFacts
        case parameterSyntaxFacts
        case parameterCallSiteSyntaxFacts
        case parameterCallArgumentBindingFacts
        case parameterCallableReferenceSyntaxFacts
        case parameterCallableReferenceBindingFacts
        case parameterExternalLabelComponentFacts
        case parameterExternalLabelRenameOutcome
        case parameterLocalBindingOutcome
        case enumCaseComponentFacts
        case compilerRawValueFacts
        case enumCaseSyntaxFacts
        case genericParameterSyntaxFacts
        case typealiasSyntaxFacts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entries = try container.decode([RenamePlanEntry].self, forKey: .entries)
        denied = try container.decode([SafetyDecision].self, forKey: .denied)
        conflicts = try container.decode([String].self, forKey: .conflicts)
        supportReplacements =
            try container.decodeIfPresent(
                [SourceReplacement].self,
                forKey: .supportReplacements
            ) ?? []
        parameterFacts =
            try container.decodeIfPresent(
                ParameterFactsSummary.self,
                forKey: .parameterFacts
            ) ?? .empty
        parameterSyntaxFacts =
            try container.decodeIfPresent(
                ParameterSyntaxFactsSummary.self,
                forKey: .parameterSyntaxFacts
            ) ?? .empty
        parameterCallSiteSyntaxFacts =
            try container.decodeIfPresent(
                ParameterCallSiteSyntaxFactsSummary.self,
                forKey: .parameterCallSiteSyntaxFacts
            ) ?? .empty
        parameterCallArgumentBindingFacts =
            try container.decodeIfPresent(
                ParameterCallArgumentBindingFactsSummary.self,
                forKey: .parameterCallArgumentBindingFacts
            ) ?? .empty
        parameterCallableReferenceSyntaxFacts =
            try container.decodeIfPresent(
                ParameterCallableReferenceSyntaxFactsSummary.self,
                forKey: .parameterCallableReferenceSyntaxFacts
            ) ?? .empty
        parameterCallableReferenceBindingFacts =
            try container.decodeIfPresent(
                ParameterCallableReferenceBindingFactsSummary.self,
                forKey: .parameterCallableReferenceBindingFacts
            ) ?? .empty
        parameterExternalLabelComponentFacts =
            try container.decodeIfPresent(
                ParameterExternalLabelComponentFactsSummary.self,
                forKey: .parameterExternalLabelComponentFacts
            ) ?? .empty
        parameterExternalLabelRenameOutcome =
            try container.decodeIfPresent(
                ParameterExternalLabelRenameOutcomeSummary.self,
                forKey: .parameterExternalLabelRenameOutcome
            ) ?? .empty
        parameterLocalBindingOutcome =
            try container.decodeIfPresent(
                ParameterLocalBindingOutcomeSummary.self,
                forKey: .parameterLocalBindingOutcome
            ) ?? .empty
        enumCaseComponentFacts =
            try container.decodeIfPresent(
                EnumCaseComponentFactsSummary.self,
                forKey: .enumCaseComponentFacts
            ) ?? .empty
        compilerRawValueFacts =
            try container.decodeIfPresent(
                CompilerRawValueFactsSummary.self,
                forKey: .compilerRawValueFacts
            ) ?? .empty
        enumCaseSyntaxFacts =
            try container.decodeIfPresent(
                EnumCaseSyntaxFactsSummary.self,
                forKey: .enumCaseSyntaxFacts
            ) ?? .empty
        genericParameterSyntaxFacts =
            try container.decodeIfPresent(
                GenericParameterSyntaxFactsSummary.self,
                forKey: .genericParameterSyntaxFacts
            ) ?? .empty
        typealiasSyntaxFacts =
            try container.decodeIfPresent(
                TypealiasSyntaxFactsSummary.self,
                forKey: .typealiasSyntaxFacts
            ) ?? .empty
    }

    public var replacements: [SourceReplacement] {
        var seen: Set<String> = []
        return (entries.flatMap(\.replacements) + supportReplacements)
            .sorted { lhs, rhs in
                (lhs.path, lhs.byteOffset, lhs.usr) < (rhs.path, rhs.byteOffset, rhs.usr)
            }
            .filter { replacement in
                // One source token can carry more than one semantic USR (for
                // example a witness satisfying two protocol requirements).
                // Applying the identical byte edit twice would fail validation,
                // so keep one physical edit while retaining every semantic plan
                // entry and mapping.
                let key =
                    "\(replacement.path):\(replacement.byteOffset):\(replacement.length):\(replacement.oldName)->\(replacement.newName)"
                return seen.insert(key).inserted
            }
    }
}
