import Foundation

struct ParameterOrdinalMatchParameter {
    let parameterUSR: String
    let externalLabel: ParameterExternalLabel
    let hasDefaultValue: Bool
    let isVariadic: Bool
    let trailingClosureCompatibility: ParameterTrailingClosureCompatibility
}

enum ParameterOrdinalParametersResult {
    case success([ParameterOrdinalMatchParameter])
    case failure(String)
}

enum ParameterOrdinalAssignmentResult {
    case unique([Int])
    case ambiguous
    case unmatched
}

enum ParameterArgumentOrdinalMatcher {
    static func parameters(
        component: ParameterRenameComponent,
        parameterRolesByUSR: [String: ParameterDeclarationSyntaxRoles]
    ) -> ParameterOrdinalParametersResult {
        guard component.isStructurallyComplete else {
            return .failure(
                "parameter component is structurally incomplete: "
                    + component.structuralReasons.joined(separator: "; ")
            )
        }
        let members = component.members.sorted { $0.ordinal < $1.ordinal }
        guard members.map(\.ordinal) == Array(members.indices) else {
            return .failure("parameter ordinals are not contiguous")
        }
        var parameters: [ParameterOrdinalMatchParameter] = []
        for member in members {
            guard let syntaxRole = parameterRolesByUSR[member.parameterUSR] else {
                return .failure(
                    "parameter declaration syntax roles unavailable for \(member.parameterUSR)"
                )
            }
            guard labelsAgree(indexed: member.externalLabel, syntax: syntaxRole.externalLabel) else {
                return .failure(
                    "indexed and compiler-syntax external labels disagree for "
                        + member.parameterUSR
                )
            }
            parameters.append(ParameterOrdinalMatchParameter(
                parameterUSR: member.parameterUSR,
                externalLabel: member.externalLabel,
                hasDefaultValue: syntaxRole.hasDefaultValue,
                isVariadic: syntaxRole.isVariadic,
                trailingClosureCompatibility: syntaxRole.trailingClosureCompatibility
            ))
        }
        return .success(parameters)
    }

    static func assignment(
        arguments: [ParameterCallArgumentSyntaxRole],
        parameters: [ParameterOrdinalMatchParameter]
    ) -> ParameterOrdinalAssignmentResult {
        var solutions: [[Int]] = []
        var current: [Int] = []

        func parametersCanBeOmitted(_ range: Range<Int>) -> Bool {
            range.allSatisfy {
                parameters[$0].hasDefaultValue || parameters[$0].isVariadic
            }
        }

        func search(argumentIndex: Int, previousOrdinal: Int?) {
            guard solutions.count < 2 else {
                return
            }
            guard argumentIndex < arguments.count else {
                let remainingStart = previousOrdinal.map { $0 + 1 } ?? 0
                guard parametersCanBeOmitted(remainingStart..<parameters.count) else {
                    return
                }
                solutions.append(current)
                return
            }

            let minimumOrdinal: Int
            if let previousOrdinal, parameters[previousOrdinal].isVariadic {
                minimumOrdinal = previousOrdinal
            } else {
                minimumOrdinal = previousOrdinal.map { $0 + 1 } ?? 0
            }
            guard minimumOrdinal < parameters.count else {
                return
            }

            for ordinal in minimumOrdinal..<parameters.count {
                let repeatsVariadic = previousOrdinal == ordinal
                if !repeatsVariadic {
                    let skippedStart = previousOrdinal.map { $0 + 1 } ?? 0
                    guard parametersCanBeOmitted(skippedStart..<ordinal) else {
                        break
                    }
                }
                guard argument(
                    arguments[argumentIndex],
                    matches: parameters[ordinal],
                    repeatsVariadic: repeatsVariadic
                ) else {
                    continue
                }
                current.append(ordinal)
                search(argumentIndex: argumentIndex + 1, previousOrdinal: ordinal)
                current.removeLast()
                if solutions.count >= 2 {
                    return
                }
            }
        }

        search(argumentIndex: 0, previousOrdinal: nil)
        switch solutions.count {
        case 0:
            return .unmatched
        case 1:
            return .unique(solutions[0])
        default:
            return .ambiguous
        }
    }

    static func fullNameOrdinals(
        argumentTokens: [SourceTokenRange],
        parameters: [ParameterOrdinalMatchParameter]
    ) -> [Int]? {
        guard argumentTokens.count == parameters.count else {
            return nil
        }
        for (token, parameter) in zip(argumentTokens, parameters) {
            switch parameter.externalLabel {
            case .omitted:
                guard token.name == "_" else {
                    return nil
                }
            case .named(let name):
                guard token.name == name else {
                    return nil
                }
            case .unavailable:
                return nil
            }
        }
        return Array(parameters.indices)
    }

    private static func labelsAgree(
        indexed: ParameterExternalLabel,
        syntax: ParameterExternalLabelSyntaxRole
    ) -> Bool {
        switch (indexed, syntax) {
        case (.named(let indexedName), .named(let token)):
            return indexedName == token.name
        case (.omitted, .omitted), (.omitted, .none):
            return true
        default:
            return false
        }
    }

    private static func argument(
        _ argument: ParameterCallArgumentSyntaxRole,
        matches parameter: ParameterOrdinalMatchParameter,
        repeatsVariadic: Bool
    ) -> Bool {
        if repeatsVariadic {
            guard parameter.isVariadic else {
                return false
            }
            switch argument {
            case .parenthesized(label: nil):
                return true
            case .firstTrailingClosure:
                return parameter.trailingClosureCompatibility != .definitelyNonCallable
            case .parenthesized(label: .some), .additionalTrailingClosure:
                return false
            }
        }

        switch argument {
        case .parenthesized(label: let label):
            switch parameter.externalLabel {
            case .omitted:
                return label == nil
            case .named(let name):
                return label?.name == name
            case .unavailable:
                return false
            }
        case .firstTrailingClosure:
            return parameter.trailingClosureCompatibility != .definitelyNonCallable
        case .additionalTrailingClosure(label: let label):
            if parameter.trailingClosureCompatibility != .definitelyNonCallable,
               case .named(let name) = parameter.externalLabel {
                return label.name == name
            }
            return false
        }
    }
}

extension ParameterCallArgumentSyntaxRole {
    var labelToken: SourceTokenRange? {
        switch self {
        case .parenthesized(label: let label):
            return label
        case .firstTrailingClosure:
            return nil
        case .additionalTrailingClosure(label: let label):
            return label
        }
    }
}
