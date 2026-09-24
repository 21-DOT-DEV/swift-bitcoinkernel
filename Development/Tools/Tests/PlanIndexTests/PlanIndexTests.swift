//
//  PlanIndexTests.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information

import Foundation
import Testing
@testable import PlanIndex

// MARK: - Schema

@Test func decodesARealPlanBlock() throws {
    let front = try Frontmatter.decode(PlanFrontmatter.self, from: """
    ---
    feature: 002
    title: Keep Screen Awake toggle
    phase: null
    status: Implemented
    updated: 2026-08-31
    adrs: [4]
    ---
    # body
    """)
    #expect(front.feature == "002")        // leading zeros survive; no quoting needed
    #expect(front.updated == "2026-08-31") // stays text rather than becoming a date
    #expect(front.phase == nil)
    #expect(front.adrs == [4])
}

@Test func refusesAFieldTheSchemaDoesNotDeclare() {
    // 'adr' where 'adrs' was meant. Decoding ignores unrecognised fields by
    // default, so without the key-set check this would pass and be dropped.
    #expect(throws: Frontmatter.ParseError(
        "unknown field(s): adr")) {
        try Frontmatter.decode(PlanFrontmatter.self, from:
            "---\nfeature: 002\ntitle: t\nphase: null\nstatus: Planned\nupdated: x\nadr: [4]\n---\n")
    }
}

@Test func reportsAMissingRequiredField() {
    #expect(throws: Frontmatter.ParseError(
        "frontmatter is missing required key 'status'")) {
        try Frontmatter.decode(PlanFrontmatter.self, from:
            "---\nfeature: 002\ntitle: t\nphase: null\nupdated: x\n---\n")
    }
}

@Test func decodesADecisionRecordIncludingItsSupersessionFields() throws {
    let front = try Frontmatter.decode(ADRFrontmatter.self, from:
        "---\nadr: 0001\ntitle: A choice\nstatus: Accepted\ndate: 2026-05-07\nsupersedes: []\nsuperseded_by: null\n---\n")
    #expect(front.adr == "0001")
    #expect(front.supersedes == [])
    #expect(front.supersededBy == nil)
}

@Test func refusesAnUnknownFieldOnADecisionRecord() {
    #expect(throws: Frontmatter.ParseError("unknown field(s): supercedes")) {
        try Frontmatter.decode(ADRFrontmatter.self, from:
            "---\nadr: 1\ntitle: t\nstatus: Accepted\ndate: x\nsupercedes: []\n---\n")
    }
}

@Test func refusesAMissingOrUnclosedBlock() {
    #expect(throws: Frontmatter.ParseError("missing frontmatter")) {
        try Frontmatter.decode(PlanFrontmatter.self, from: "# No frontmatter\n")
    }
}

// MARK: - Tables

@Test func rendersASpecTable() {
    let out = Tables.specTable([SpecRow(number: "001", title: "Icons", phase: "—",
                                       status: "In Progress", link: "001-icons/plan.md")])
    #expect(out.contains("| 001 | Icons | — | In Progress | [plan.md](001-icons/plan.md) |"))
}

@Test func replacesOnlyTheBlockBetweenMarkers() throws {
    let text = "before\n\(beginMarker)\nstale\n\(endMarker)\nafter\n"
    let out = try #require(Tables.replacingIndex(in: text, with: "fresh"))
    #expect(out == "before\n\(beginMarker)\nfresh\n\(endMarker)\nafter\n")
}

@Test func refusesWhenAMarkerIsMissing() {
    #expect(Tables.replacingIndex(in: "no markers here", with: "x") == nil)
}

// MARK: - End to end, against real files in a temporary directory

private func makeTree(status: String = "Implemented", feature: String = "002",
                      adrStatus: String = "Accepted", adrNumber: String = "1",
                      omitADRDate: Bool = false, planExtra: String = "",
                      siblings: [String: String] = [:]) throws -> URL {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("plan-index-\(UUID().uuidString)")
    let fm = FileManager.default
    try fm.createDirectory(at: root.appendingPathComponent("Specs/002-thing"), withIntermediateDirectories: true)
    try fm.createDirectory(at: root.appendingPathComponent("Specs/_template"), withIntermediateDirectories: true)
    try fm.createDirectory(at: root.appendingPathComponent("ADRs"), withIntermediateDirectories: true)
    try """
    ---
    feature: \(feature)
    title: A thing
    phase: null
    status: \(status)
    updated: 2026-08-31
    ---
    # A thing
    \(planExtra)
    """.write(to: root.appendingPathComponent("Specs/002-thing/plan.md"), atomically: true, encoding: .utf8)
    for (name, text) in siblings {
        try text.write(to: root.appendingPathComponent("Specs/002-thing/\(name)"),
                       atomically: true, encoding: .utf8)
    }
    try "---\nfeature: NNN\ntitle: skeleton\nphase: null\nstatus: Planned\nupdated: YYYY-MM-DD\n---\n"
        .write(to: root.appendingPathComponent("Specs/_template/plan.md"), atomically: true, encoding: .utf8)
    let dateLine = omitADRDate ? "" : "date: 2026-05-07\n"
    try "---\nadr: \(adrNumber)\ntitle: A choice\nstatus: \(adrStatus)\n\(dateLine)---\n"
        .write(to: root.appendingPathComponent("ADRs/0001-a-choice.md"), atomically: true, encoding: .utf8)
    // Neither of these is a decision record and neither must be indexed.
    try "# not a record\n".write(to: root.appendingPathComponent("ADRs/NOTES.md"), atomically: true, encoding: .utf8)
    for p in ["Specs/README.md", "ADRs/README.md"] {
        try "# Index\n\n\(beginMarker)\n\(endMarker)\n".write(to: root.appendingPathComponent(p), atomically: true, encoding: .utf8)
    }
    return root
}

@Test func generatesBothIndexesAndSkipsTheTemplate() throws {
    let root = try makeTree()
    defer { try? FileManager.default.removeItem(at: root) }

    let report = Indexer(development: root).run(check: false)
    #expect(report.errors.isEmpty)
    #expect(report.specCount == 1)          // _template is not a feature
    #expect(report.adrCount == 1)

    let specs = try String(contentsOf: root.appendingPathComponent("Specs/README.md"), encoding: .utf8)
    #expect(specs.contains("| 002 | A thing | — | Implemented | [plan.md](002-thing/plan.md) |"))
    let adrs = try String(contentsOf: root.appendingPathComponent("ADRs/README.md"), encoding: .utf8)
    #expect(adrs.contains("| 0001 | [A choice](0001-a-choice.md) | Accepted | 2026-05-07 |"))
}

@Test func checkModeFailsWhenTheIndexIsStale() throws {
    let root = try makeTree()
    defer { try? FileManager.default.removeItem(at: root) }
    let report = Indexer(development: root).run(check: true)
    #expect(report.isFailure)
    #expect(report.errors.contains { $0.contains("index is out of date") })
}

@Test func rejectsAStatusOutsideTheThreeAllowedValues() throws {
    let root = try makeTree(status: "Shipped")
    defer { try? FileManager.default.removeItem(at: root) }
    let report = Indexer(development: root).run(check: false)
    #expect(report.errors.contains { $0.contains("status 'Shipped' is not one of") })
}

@Test func rejectsAFeatureNumberThatDisagreesWithItsFolder() throws {
    let root = try makeTree(feature: "007")
    defer { try? FileManager.default.removeItem(at: root) }
    let report = Indexer(development: root).run(check: false)
    #expect(report.errors.contains { $0.contains("does not match folder") })
}

@Test func aSecondRunReportsNothingToDo() throws {
    let root = try makeTree()
    defer { try? FileManager.default.removeItem(at: root) }
    _ = Indexer(development: root).run(check: false)
    let second = Indexer(development: root).run(check: true)
    #expect(!second.isFailure)
    #expect(second.rewritten.isEmpty)
}


// MARK: - Decision records

@Test func rejectsADecisionRecordStatusOutsideTheThreeAllowedValues() throws {
    let root = try makeTree(adrStatus: "Draft")
    defer { try? FileManager.default.removeItem(at: root) }
    let report = Indexer(development: root).run(check: false)
    #expect(report.errors.contains { $0.contains("status 'Draft' is not one of") })
}

@Test func reportsADecisionRecordMissingARequiredKey() throws {
    let root = try makeTree(omitADRDate: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let report = Indexer(development: root).run(check: false)
    #expect(report.errors.contains { $0.contains("missing required key 'date'") })
}

@Test func skipsFilesInTheDecisionRecordsFolderThatAreNotNumbered() throws {
    let root = try makeTree()
    defer { try? FileManager.default.removeItem(at: root) }
    let report = Indexer(development: root).run(check: false)
    #expect(report.adrCount == 1)   // NOTES.md and README.md are not records
    let index = try String(contentsOf: root.appendingPathComponent("ADRs/README.md"), encoding: .utf8)
    #expect(!index.contains("NOTES"))
}

@Test func padsDecisionRecordNumbersToFourDigits() throws {
    let root = try makeTree(adrNumber: "7")
    defer { try? FileManager.default.removeItem(at: root) }
    _ = Indexer(development: root).run(check: false)
    let index = try String(contentsOf: root.appendingPathComponent("ADRs/README.md"), encoding: .utf8)
    #expect(index.contains("| 0007 |"))
}

@Test func rendersADecisionRecordTable() {
    let out = Tables.adrTable([ADRRow(number: "0002", title: "A choice", status: "Superseded",
                                      date: "2026-05-07", file: "0002-a-choice.md")])
    #expect(out.contains("| 0002 | [A choice](0002-a-choice.md) | Superseded | 2026-05-07 |"))
}

// MARK: - Sibling checks

private let siblingSpec = """
# Spec — a thing

### Acceptance scenarios

1. **Given** x, **when** y, **then** z — covers FR-001, FR-002.

- **FR-001** First requirement.
- **FR-002** Second requirement.
- **SC-001** A measurable outcome.
"""

private let siblingTasks = """
# Tasks

- [ ] T001 Do the first thing (FR-001)
- [ ] T002 Do the second thing (FR-002)
"""

@Test func siblingsWithoutFrontmatterAndFullCoveragePass() throws {
    let root = try makeTree(planExtra: "Verifies SC-001.",
                            siblings: ["spec.md": siblingSpec, "tasks.md": siblingTasks])
    defer { try? FileManager.default.removeItem(at: root) }
    let report = Indexer(development: root).run(check: false)
    #expect(report.errors.isEmpty)
}

@Test func aSiblingWithFrontmatterIsRejected() throws {
    let root = try makeTree(siblings: ["spec.md": "---\nstatus: Planned\n---\n# Spec\n"])
    defer { try? FileManager.default.removeItem(at: root) }
    let report = Indexer(development: root).run(check: false)
    #expect(report.errors.contains { $0.contains("sibling files carry no frontmatter") })
}

@Test func aRequirementNoTaskCitesIsRejected() throws {
    let root = try makeTree(planExtra: "SC-001",
                            siblings: ["spec.md": siblingSpec,
                                       "tasks.md": "- [ ] T001 Only the first (FR-001)\n"])
    defer { try? FileManager.default.removeItem(at: root) }
    let report = Indexer(development: root).run(check: false)
    #expect(report.errors.contains { $0.contains("FR-002 is defined in spec.md but never cited") })
}

@Test func aCitedRequirementTheSpecDoesNotDefineIsRejected() throws {
    let root = try makeTree(planExtra: "SC-001",
                            siblings: ["spec.md": siblingSpec,
                                       "tasks.md": "- [ ] T001 (FR-001, FR-099)\n- [ ] T002 (FR-002)\n"])
    defer { try? FileManager.default.removeItem(at: root) }
    let report = Indexer(development: root).run(check: false)
    #expect(report.errors.contains { $0.contains("FR-099 is cited but spec.md defines no such requirement") })
}

@Test func anOutcomeThePlanNeverVerifiesIsRejected() throws {
    let root = try makeTree(siblings: ["spec.md": siblingSpec, "tasks.md": siblingTasks])
    defer { try? FileManager.default.removeItem(at: root) }
    let report = Indexer(development: root).run(check: false)
    #expect(report.errors.contains { $0.contains("SC-001 is defined in spec.md but never cited") })
}

@Test func aSpecWithoutTasksChecksRequirementsAgainstThePlan() throws {
    let root = try makeTree(planExtra: "FR-001, FR-002, SC-001",
                            siblings: ["spec.md": siblingSpec])
    defer { try? FileManager.default.removeItem(at: root) }
    let report = Indexer(development: root).run(check: false)
    #expect(report.errors.isEmpty)
}

@Test func aSpecWithoutTasksStillRequiresCoverageInThePlan() throws {
    let root = try makeTree(planExtra: "SC-001", siblings: ["spec.md": siblingSpec])
    defer { try? FileManager.default.removeItem(at: root) }
    let report = Indexer(development: root).run(check: false)
    #expect(report.errors.contains { $0.contains("FR-002 is defined in spec.md but never cited") })
}

@Test func anUnreadableSiblingReportsTheSystemsReason() throws {
    let root = try makeTree(siblings: ["research.md": "# R\n"])
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("Specs/002-thing/research.md")
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }
    let report = Indexer(development: root).run(check: false)
    #expect(report.errors.contains { $0.contains("research.md") })
}

@Test func frontmatterAfterCRLFIsStillFrontmatter() throws {
    let root = try makeTree(siblings: ["research.md": "\r\n---\nstatus: Planned\n---\n# R\n"])
    defer { try? FileManager.default.removeItem(at: root) }
    let report = Indexer(development: root).run(check: false)
    #expect(report.errors.contains { $0.contains("sibling files carry no frontmatter") })
}

@Test func anOutcomeThePlanCitesButTheSpecDoesNotDefineIsRejected() throws {
    let root = try makeTree(planExtra: "SC-001 and SC-099",
                            siblings: ["spec.md": siblingSpec, "tasks.md": siblingTasks])
    defer { try? FileManager.default.removeItem(at: root) }
    let report = Indexer(development: root).run(check: false)
    #expect(report.errors.contains { $0.contains("SC-099 is cited but spec.md defines no such outcome") })
}

@Test func frontmatterAfterALeadingBlankLineIsStillFrontmatter() throws {
    let root = try makeTree(siblings: ["research.md": "\n---\nstatus: Planned\n---\n# R\n"])
    defer { try? FileManager.default.removeItem(at: root) }
    let report = Indexer(development: root).run(check: false)
    #expect(report.errors.contains { $0.contains("sibling files carry no frontmatter") })
}

@Test func aPlainTextCrossReferenceIsNotTreatedAsADefinition() throws {
    // The spec mentions FR-002 of another feature in prose; only the bold
    // **FR-NNN** form defines one, so tasks.md owes no citation for it.
    let spec = "# Spec\n\n- **FR-001** The only requirement.\n\nSee also 003's FR-002.\n- **SC-001** An outcome.\n"
    let root = try makeTree(planExtra: "SC-001",
                            siblings: ["spec.md": spec,
                                       "tasks.md": "- [ ] T001 (verifies FR-001)\n"])
    defer { try? FileManager.default.removeItem(at: root) }
    let report = Indexer(development: root).run(check: false)
    #expect(report.errors.isEmpty)
}

@Test func aQualifiedCiteToAnotherFeatureIsNotDangling() throws {
    // `003/FR-004` and `003's FR-004` point at the other feature's spec; a bare
    // FR-004 in the same file would still be dangling — only qualified forms
    // are exempt.
    let root = try makeTree(planExtra: "SC-001 and 003/FR-004",
                            siblings: ["spec.md": siblingSpec,
                                       "tasks.md": siblingTasks
                                        + "- [ ] T003 See 003's FR-009 (FR-001)\n"])
    defer { try? FileManager.default.removeItem(at: root) }
    let report = Indexer(development: root).run(check: false)
    #expect(report.errors.isEmpty)
}

@Test func anAdrThePlanListsButDoesNotExistIsRejected() throws {
    let root = try makeTree(planExtra: "")
    defer { try? FileManager.default.removeItem(at: root) }
    // The fixture writes no adrs: field; add one naming a record that is not there.
    let plan = root.appendingPathComponent("Specs/002-thing/plan.md")
    let text = try String(contentsOf: plan, encoding: .utf8)
    try text.replacingOccurrences(of: "updated: 2026-08-31", with: "updated: 2026-08-31\nadrs: [0001, 0007]")
        .write(to: plan, atomically: true, encoding: .utf8)
    let report = Indexer(development: root).run(check: false)
    #expect(report.errors.contains { $0.contains("adrs lists 0007 but no such record exists") })
    #expect(!report.errors.contains { $0.contains("adrs lists 0001") })
}

@Test func researchCitingAnUndefinedRequirementIsRejected() throws {
    let root = try makeTree(planExtra: "SC-001",
                            siblings: ["spec.md": siblingSpec, "tasks.md": siblingTasks,
                                       "research.md": "# R\n\nEvidence for FR-042.\n"])
    defer { try? FileManager.default.removeItem(at: root) }
    let report = Indexer(development: root).run(check: false)
    #expect(report.errors.contains { $0.contains("FR-042 is cited but spec.md defines no such requirement") })
}

@Test func tasksCitingARequirementWithNoSpecToDefineItIsRejected() throws {
    let root = try makeTree(siblings: ["tasks.md": "- [ ] T001 (FR-001)\n"])
    defer { try? FileManager.default.removeItem(at: root) }
    let report = Indexer(development: root).run(check: false)
    #expect(report.errors.contains { $0.contains("FR-001 is cited but spec.md defines no such requirement") })
}

@Test func anUnreadableTasksFileDoesNotCascadeIntoCoverageErrors() throws {
    let root = try makeTree(planExtra: "SC-001",
                            siblings: ["spec.md": siblingSpec, "tasks.md": siblingTasks])
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("Specs/002-thing/tasks.md")
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }
    let report = Indexer(development: root).run(check: false)
    #expect(report.errors.contains { $0.contains("tasks.md") && !$0.contains("never cited") })
    #expect(!report.errors.contains { $0.contains("never cited") })
}

@Test func aTemplateMarkerInANumberedFolderIsRejected() throws {
    let root = try makeTree(siblings: ["research.md": "<!--\nDelete this comment before committing.\n-->\n# R\n"])
    defer { try? FileManager.default.removeItem(at: root) }
    let report = Indexer(development: root).run(check: false)
    #expect(report.errors.contains { $0.contains("\"Delete this comment\" marker was not removed") })
}

@Test func coverageMapsRequirementsToTasksTestsAndScenarios() throws {
    let spec = """
    # Spec

    ### Acceptance scenarios

    1. **Given** x, **when** y, **then** z — covers FR-001

    - **FR-001** First.
    - **FR-002** Second.
    - **SC-001** An outcome.
    """
    let tasks = """
    - [ ] T001 Build it (FR-001)
      continuation line
    - [ ] T002 [P] Tests for it — `Sources/XTests/FooTests.swift` (verifies FR-001, FR-002)
    """
    let root = try makeTree(planExtra: "SC-001",
                            siblings: ["spec.md": spec, "tasks.md": tasks])
    defer { try? FileManager.default.removeItem(at: root) }
    let report = Indexer(development: root).run(check: false)
    let text = report.coverage.joined(separator: "\n")
    #expect(text.contains("2/2 requirements cited, 2/2 test-verified, 1/1 outcomes verified"))
    #expect(text.contains("FR-001 → T001, T002 · tests: T002 · scenario: 1"))
    #expect(text.contains("FR-002 → T002 · tests: T002 · scenario: —"))
    #expect(text.contains("SC-001 → plan.md ✓"))
}

@Test func aRequirementVerifiedOnlyByAScenarioWarns() throws {
    // A scenario is a verification path — demonstrated on-device — so this is a
    // warning, not an error; but the gap in automated coverage is still said
    // plainly rather than folded into a citation count.
    let root = try makeTree(planExtra: "SC-001",
                            siblings: ["spec.md": siblingSpec,
                                       "tasks.md": "- [ ] T001 (FR-001)\n- [ ] T002 (FR-002)\n"])
    defer { try? FileManager.default.removeItem(at: root) }
    let report = Indexer(development: root).run(check: false)
    #expect(report.warnings.contains { $0.contains("FR-001") && $0.contains("no `verifies` cite") })
    #expect(report.warnings.contains { $0.contains("FR-002") && $0.contains("no `verifies` cite") })
    #expect(report.errors.isEmpty)
}

@Test func aRequirementWithNoVerificationPathIsAnError() throws {
    // Neither a `verifies` cite nor an acceptance scenario — the requirement is
    // named but nothing anywhere checks it, which is a failure, not a warning.
    let spec = "# Spec\n\n- **FR-001** Cited but unverifiable.\n- **SC-001** An outcome.\n"
    let root = try makeTree(planExtra: "SC-001",
                            siblings: ["spec.md": spec,
                                       "tasks.md": "- [ ] T001 Do it (FR-001)\n"])
    defer { try? FileManager.default.removeItem(at: root) }
    let report = Indexer(development: root).run(check: false)
    #expect(report.errors.contains { $0.contains("FR-001") && $0.contains("no verification path") })
}

// MARK: - Nesting

@Test func aNestedFieldIsRefusedBecauseTheSchemaDoesNotDeclareIt() {
    #expect(throws: Frontmatter.ParseError("unknown field(s): nested")) {
        try Frontmatter.decode(PlanFrontmatter.self, from:
            "---\nfeature: 1\ntitle: t\nphase: null\nstatus: Planned\nupdated: x\nnested:\n  a: b\n---\n")
    }
}
