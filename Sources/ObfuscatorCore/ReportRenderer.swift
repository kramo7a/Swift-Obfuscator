import Foundation

public enum ReportRenderer {
    public static func renderDump(snapshot: IndexSnapshot) -> String {
        var lines: [String] = []
        lines.append("INDEX DUMP")
        lines.append("source files: \(snapshot.sourceFiles.count)")
        lines.append("symbols: \(snapshot.symbols.count)")
        lines.append("occurrences: \(snapshot.occurrences.count)")
        lines.append("")
        lines.append("SYMBOLS")
        for symbol in snapshot.symbols {
            lines.append("- \(symbol.name) | usr=\(symbol.usr) | kind=\(symbol.kind) | language=\(symbol.language) | properties=\(symbol.properties)")
        }
        lines.append("")
        lines.append("OCCURRENCES BY USR")
        for group in snapshot.occurrenceGroups {
            lines.append("- \(group.symbol.name) | usr=\(group.usr) | kind=\(group.symbol.kind) | count=\(group.occurrences.count)")
            for occurrence in group.occurrences {
                lines.append("  \(occurrence.path):\(occurrence.line):\(occurrence.utf8Column) | roles=\(occurrence.roles.joined(separator: ",")) | provider=\(occurrence.symbolProvider)")
                for relation in occurrence.relations {
                    lines.append("    relation \(relation.roles.joined(separator: ",")) -> \(relation.name) | usr=\(relation.usr)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    public static func renderDryRun(plan: RenamePlan, compact: Bool = false) -> String {
        var lines: [String] = []
        lines.append("DRY-RUN REPORT")
        lines.append("planned symbols: \(plan.renames.count)")
        lines.append("planned replacements: \(plan.edits.count)")
        lines.append("denied symbols: \(plan.rejections.count)")
        lines.append("conflicts: \(plan.editConflicts.count)")
        lines.append("")

        if !plan.renames.isEmpty {
            lines.append("PLANNED RENAMES")
            for entry in plan.renames {
                lines.append("- \(entry.oldName) -> \(entry.newName) | kind=\(entry.kind) | usr=\(entry.usr) | replacements=\(entry.edits.count)")
                if !compact {
                    for replacement in entry.edits {
                        lines.append("  \(replacement.path):\(replacement.line):\(replacement.utf8Column)")
                    }
                }
            }
            lines.append("")
        }

        if !plan.rejections.isEmpty {
            lines.append("DENIED")
            if compact {
                lines.append("- per-symbol denial details omitted by --compact-report")
            } else {
                for decision in plan.rejections {
                    lines.append("- \(decision.symbolName) | kind=\(decision.symbolKind) | usr=\(decision.usr)")
                    lines.append("  reasons: \(decision.reasons.joined(separator: "; "))")
                }
            }
            lines.append("")
        }

        if !plan.editConflicts.isEmpty {
            lines.append("CONFLICTS")
            for conflict in plan.editConflicts {
                lines.append("- \(conflict)")
            }
        }

        return lines.joined(separator: "\n")
    }
}
