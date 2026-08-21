import Foundation

public struct RenamePlan: Codable, Sendable {
    public struct Entry: Codable, Sendable {
        public let usr: String
        public let kind: String
        public let oldName: String
        public let newName: String
        public let edits: [SourcePatcher.Edit]

        private enum CodingKeys: String, CodingKey {
            case usr
            case kind
            case oldName
            case newName
            case edits = "replacements"
        }
    }

    public let renames: [RenamePlan.Entry]
    public let rejections: [RenameEligibility]
    public let editConflicts: [String]
    public let preservationEdits: [SourcePatcher.Edit]
    public let callableReport: CallableSignature.Report
    public let parameterSyntaxReport: ParameterSyntax.Report
    public let callSiteSyntaxReport: CallSiteSyntax.Report
    public let callArgumentBindingReport: CallArgumentBinding.Report
    public let callableReferenceSyntaxReport: CallableReferenceSyntax.Report
    public let callableReferenceBindingReport: CallableReferenceBinding.Report
    public let externalLabelReport: ExternalLabel.Report
    public let externalLabelRenameReport: ExternalLabel.RenameReport
    public let localBindingRenameReport: LocalBindingRename.Report
    public let enumCaseSemanticsReport: EnumCaseSemantics.Report
    public let enumRawValueReport: EnumRawValue.Report
    public let enumCaseSyntaxReport: EnumCaseSyntax.Report
    public let genericParameterReport: GenericParameterAnalysis.Report
    public let typeAliasSyntaxReport: TypeAliasSyntax.Report

    public init(
        renames: [RenamePlan.Entry],
        rejections: [RenameEligibility],
        editConflicts: [String],
        preservationEdits: [SourcePatcher.Edit] = [],
        callableReport: CallableSignature.Report = .empty,
        parameterSyntaxReport: ParameterSyntax.Report = .empty,
        callSiteSyntaxReport: CallSiteSyntax.Report = .empty,
        callArgumentBindingReport: CallArgumentBinding.Report = .empty,
        callableReferenceSyntaxReport: CallableReferenceSyntax.Report = .empty,
        callableReferenceBindingReport: CallableReferenceBinding.Report = .empty,
        externalLabelReport: ExternalLabel.Report = .empty,
        externalLabelRenameReport: ExternalLabel.RenameReport = .empty,
        localBindingRenameReport: LocalBindingRename.Report = .empty,
        enumCaseSemanticsReport: EnumCaseSemantics.Report = .empty,
        enumRawValueReport: EnumRawValue.Report = .empty,
        enumCaseSyntaxReport: EnumCaseSyntax.Report = .empty,
        genericParameterReport: GenericParameterAnalysis.Report = .empty,
        typeAliasSyntaxReport: TypeAliasSyntax.Report = .empty
    ) {
        self.renames = renames
        self.rejections = rejections
        self.editConflicts = editConflicts
        self.preservationEdits = preservationEdits
        self.callableReport = callableReport
        self.parameterSyntaxReport = parameterSyntaxReport
        self.callSiteSyntaxReport = callSiteSyntaxReport
        self.callArgumentBindingReport = callArgumentBindingReport
        self.callableReferenceSyntaxReport = callableReferenceSyntaxReport
        self.callableReferenceBindingReport = callableReferenceBindingReport
        self.externalLabelReport = externalLabelReport
        self.externalLabelRenameReport = externalLabelRenameReport
        self.localBindingRenameReport = localBindingRenameReport
        self.enumCaseSemanticsReport = enumCaseSemanticsReport
        self.enumRawValueReport = enumRawValueReport
        self.enumCaseSyntaxReport = enumCaseSyntaxReport
        self.genericParameterReport = genericParameterReport
        self.typeAliasSyntaxReport = typeAliasSyntaxReport
    }

    private enum CodingKeys: String, CodingKey {
        case renames = "entries"
        case rejections = "denied"
        case editConflicts = "conflicts"
        case preservationEdits = "supportReplacements"
        case callableReport = "parameterFacts"
        case parameterSyntaxReport = "parameterSyntaxFacts"
        case callSiteSyntaxReport = "parameterCallSiteSyntaxFacts"
        case callArgumentBindingReport = "parameterCallArgumentBindingFacts"
        case callableReferenceSyntaxReport = "parameterCallableReferenceSyntaxFacts"
        case callableReferenceBindingReport = "parameterCallableReferenceBindingFacts"
        case externalLabelReport = "parameterExternalLabelComponentFacts"
        case externalLabelRenameReport = "parameterExternalLabelRenameOutcome"
        case localBindingRenameReport = "parameterLocalBindingOutcome"
        case enumCaseSemanticsReport = "enumCaseComponentFacts"
        case enumRawValueReport = "compilerRawValueFacts"
        case enumCaseSyntaxReport = "enumCaseSyntaxFacts"
        case genericParameterReport = "genericParameterSyntaxFacts"
        case typeAliasSyntaxReport = "typealiasSyntaxFacts"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        renames = try container.decode([RenamePlan.Entry].self, forKey: .renames)
        rejections = try container.decode([RenameEligibility].self, forKey: .rejections)
        editConflicts = try container.decode([String].self, forKey: .editConflicts)
        preservationEdits =
            try container.decodeIfPresent(
                [SourcePatcher.Edit].self,
                forKey: .preservationEdits
            ) ?? []
        callableReport =
            try container.decodeIfPresent(
                CallableSignature.Report.self,
                forKey: .callableReport
            ) ?? .empty
        parameterSyntaxReport =
            try container.decodeIfPresent(
                ParameterSyntax.Report.self,
                forKey: .parameterSyntaxReport
            ) ?? .empty
        callSiteSyntaxReport =
            try container.decodeIfPresent(
                CallSiteSyntax.Report.self,
                forKey: .callSiteSyntaxReport
            ) ?? .empty
        callArgumentBindingReport =
            try container.decodeIfPresent(
                CallArgumentBinding.Report.self,
                forKey: .callArgumentBindingReport
            ) ?? .empty
        callableReferenceSyntaxReport =
            try container.decodeIfPresent(
                CallableReferenceSyntax.Report.self,
                forKey: .callableReferenceSyntaxReport
            ) ?? .empty
        callableReferenceBindingReport =
            try container.decodeIfPresent(
                CallableReferenceBinding.Report.self,
                forKey: .callableReferenceBindingReport
            ) ?? .empty
        externalLabelReport =
            try container.decodeIfPresent(
                ExternalLabel.Report.self,
                forKey: .externalLabelReport
            ) ?? .empty
        externalLabelRenameReport =
            try container.decodeIfPresent(
                ExternalLabel.RenameReport.self,
                forKey: .externalLabelRenameReport
            ) ?? .empty
        localBindingRenameReport =
            try container.decodeIfPresent(
                LocalBindingRename.Report.self,
                forKey: .localBindingRenameReport
            ) ?? .empty
        enumCaseSemanticsReport =
            try container.decodeIfPresent(
                EnumCaseSemantics.Report.self,
                forKey: .enumCaseSemanticsReport
            ) ?? .empty
        enumRawValueReport =
            try container.decodeIfPresent(
                EnumRawValue.Report.self,
                forKey: .enumRawValueReport
            ) ?? .empty
        enumCaseSyntaxReport =
            try container.decodeIfPresent(
                EnumCaseSyntax.Report.self,
                forKey: .enumCaseSyntaxReport
            ) ?? .empty
        genericParameterReport =
            try container.decodeIfPresent(
                GenericParameterAnalysis.Report.self,
                forKey: .genericParameterReport
            ) ?? .empty
        typeAliasSyntaxReport =
            try container.decodeIfPresent(
                TypeAliasSyntax.Report.self,
                forKey: .typeAliasSyntaxReport
            ) ?? .empty
    }

    public var edits: [SourcePatcher.Edit] {
        var seen: Set<String> = []
        return (renames.flatMap(\.edits) + preservationEdits)
            .sorted { lhs, rhs in
                (lhs.path, lhs.byteOffset, lhs.usr) < (rhs.path, rhs.byteOffset, rhs.usr)
            }
            .filter { edit in
                // One source token can carry more than one semantic USR (for
                // example a witness satisfying two protocol requirements).
                // Applying the identical byte edit twice would fail validation,
                // so keep one physical edit while retaining every semantic plan
                // entry and mapping.
                let key =
                    "\(edit.path):\(edit.byteOffset):\(edit.length):\(edit.oldName)->\(edit.newName)"
                return seen.insert(key).inserted
            }
    }
}
