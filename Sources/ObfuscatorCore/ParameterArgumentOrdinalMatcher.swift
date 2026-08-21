import Foundation

struct ParameterOrdinalMatchParameter {
    let parameterUSR: String
    let externalLabel: ExternalLabel
    let hasDefaultValue: Bool
    let isVariadic: Bool
    let trailingClosureCompatibility: ParameterSyntax.TrailingClosureSupport
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
        signature: CallableSignature,
        parametersByUSR: [String: ParameterSyntax.Parameter]
    ) -> ParameterOrdinalParametersResult {
        guard signature.isStructurallyComplete else {
            return .failure(
                "parameter signature is structurally incomplete: "
                    + signature.structuralReasons.joined(separator: "; ")
            )
        }
        let signatureParameters = signature.parameters.sorted { $0.ordinal < $1.ordinal }
        guard signatureParameters.map(\.ordinal) == Array(signatureParameters.indices) else {
            return .failure("parameter ordinals are not contiguous")
        }
        var parameters: [ParameterOrdinalMatchParameter] = []
        for signatureParameter in signatureParameters {
            guard let syntaxRole = parametersByUSR[signatureParameter.parameterUSR] else {
                return .failure(
                    "parameter declaration syntax roles unavailable for \(signatureParameter.parameterUSR)"
                )
            }
            guard
                labelsAgree(
                    indexed: signatureParameter.externalLabel,
                    syntax: syntaxRole.externalLabel
                )
            else {
                return .failure(
                    "indexed and compiler-syntax external labels disagree for "
                        + signatureParameter.parameterUSR
                )
            }
            parameters.append(
                ParameterOrdinalMatchParameter(
                    parameterUSR: signatureParameter.parameterUSR,
                    externalLabel: signatureParameter.externalLabel,
                    hasDefaultValue: syntaxRole.hasDefaultValue,
                    isVariadic: syntaxRole.isVariadic,
                    trailingClosureCompatibility: syntaxRole.trailingClosureCompatibility
                ))
        }
        return .success(parameters)
    }

    static func assignment(
        arguments: [CallSiteSyntax.Argument],
        parameters: [ParameterOrdinalMatchParameter],
        canOmitNamedLabels: Bool = false
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
                guard
                    argument(
                        arguments[argumentIndex],
                        matches: parameters[ordinal],
                        repeatsVariadic: repeatsVariadic,
                        canOmitNamedLabels: canOmitNamedLabels
                    )
                else {
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
        argumentTokens: [SourceToken],
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
        indexed: ExternalLabel,
        syntax: ParameterSyntax.LabelRole
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
        _ argument: CallSiteSyntax.Argument,
        matches parameter: ParameterOrdinalMatchParameter,
        repeatsVariadic: Bool,
        canOmitNamedLabels: Bool
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
        case .parenthesized(let label):
            switch parameter.externalLabel {
            case .omitted:
                return label == nil
            case .named(let name):
                return label == nil && canOmitNamedLabels
                    || label?.name == name
            case .unavailable:
                return false
            }
        case .firstTrailingClosure:
            return parameter.trailingClosureCompatibility != .definitelyNonCallable
        case .additionalTrailingClosure(let label):
            if parameter.trailingClosureCompatibility != .definitelyNonCallable,
                case .named(let name) = parameter.externalLabel
            {
                return label.name == name
            }
            return false
        }
    }
}

extension CallSiteSyntax.Argument {
    var labelToken: SourceToken? {
        switch self {
        case .parenthesized(let label):
            return label
        case .firstTrailingClosure:
            return nil
        case .additionalTrailingClosure(let label):
            return label
        }
    }
}
