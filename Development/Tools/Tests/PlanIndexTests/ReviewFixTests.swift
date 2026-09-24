//
//  ReviewFixTests.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information

import Foundation
import Testing
@testable import PlanIndex

// MARK: - Escaping when the table is written

@Test func escapesAVerticalBarInATitleSoTheRowKeepsItsColumns() {
    let out = Tables.specTable([SpecRow(number: "001", title: "Encode a | b", phase: "—",
                                        status: "Planned", link: "001-x/plan.md")])
    #expect(out.contains(#"Encode a \| b"#))
    #expect(!out.contains("Encode a | b"))
}

@Test func escapesBracketsInADecisionRecordTitleSoTheLinkSurvives() {
    let out = Tables.adrTable([ADRRow(number: "0001", title: "Use [brackets] here", status: "Accepted",
                                      date: "2026-01-01", file: "0001-x.md")])
    #expect(out.contains(#"Use \[brackets\] here"#))
}

@Test func escapesABackslashBeforeAnythingElse() {
    // Otherwise a trailing backslash would consume the escape added after it.
    let out = Tables.specTable([SpecRow(number: "001", title: #"back\slash"#, phase: "—",
                                        status: "Planned", link: "001-x/plan.md")])
    #expect(out.contains(#"back\\slash"#))
}

@Test func escapesParenthesesInALinkDestination() {
    let out = Tables.adrTable([ADRRow(number: "0001", title: "t", status: "Accepted",
                                      date: "2026-01-01", file: "0001-a(b).md")])
    #expect(out.contains(#"0001-a\(b\).md"#))
}

// MARK: - Malformed table rows anywhere in the tree

@Test func reportsATableRowWhoseColumnCountDisagreesWithItsHeader() {
    let rows = Tables.malformedRows(in: """
    | a | b |
    |---|---|
    | one | two |
    | one | two | three |
    """)
    #expect(rows.count == 1)
    #expect(rows.first?.line == 4)
}

@Test func acceptsARowWhoseExtraBarIsEscaped() {
    let rows = Tables.malformedRows(in: """
    | a | b |
    |---|---|
    | one \\| still one | two |
    """)
    #expect(rows.isEmpty)
}

// MARK: - Messages name the folder that was actually read

@Test func errorMessagesNameTheFolderThatWasActuallyScanned() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("Planning-\(UUID().uuidString)")
    let fm = FileManager.default
    try fm.createDirectory(at: root.appendingPathComponent("Specs/001-x"), withIntermediateDirectories: true)
    try fm.createDirectory(at: root.appendingPathComponent("ADRs"), withIntermediateDirectories: true)
    try "---\nfeature: 001\ntitle: t\nphase: null\nstatus: Nope\nupdated: x\n---\n"
        .write(to: root.appendingPathComponent("Specs/001-x/plan.md"), atomically: true, encoding: .utf8)
    for p in ["Specs/README.md", "ADRs/README.md"] {
        try "\(beginMarker)\n\(endMarker)\n".write(to: root.appendingPathComponent(p), atomically: true, encoding: .utf8)
    }
    defer { try? fm.removeItem(at: root) }

    let report = Indexer(development: root).run(check: false)
    let statusError = try #require(report.errors.first { $0.contains("is not one of") })
    #expect(statusError.hasPrefix(root.lastPathComponent + "/"))
    #expect(!statusError.contains("Development/"))
}

// MARK: - Read failures say why

@Test func saysWhyAPlanCouldNotBeReadRatherThanCallingItAbsent() throws {
    let root = try makeUnreadableTree(plan: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let report = Indexer(development: root).run(check: false)
    let e = try #require(report.errors.first { $0.contains("plan.md") })
    #expect(!e.contains("has no plan.md"))      // the file is right there
    #expect(e.lowercased().contains("format") || e.lowercased().contains("couldn"))
}

@Test func reportsAnUnreadableDecisionRecordInsteadOfSkippingIt() throws {
    let root = try makeUnreadableTree(plan: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let report = Indexer(development: root).run(check: false)
    #expect(report.errors.contains { $0.contains("0001-broken.md") })
}

private func makeUnreadableTree(plan: Bool) throws -> URL {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("unreadable-\(UUID().uuidString)")
    let fm = FileManager.default
    try fm.createDirectory(at: root.appendingPathComponent("Specs/001-x"), withIntermediateDirectories: true)
    try fm.createDirectory(at: root.appendingPathComponent("ADRs"), withIntermediateDirectories: true)
    for p in ["Specs/README.md", "ADRs/README.md"] {
        try "\(beginMarker)\n\(endMarker)\n".write(to: root.appendingPathComponent(p), atomically: true, encoding: .utf8)
    }
    // Bytes that are not valid text: present, but unreadable. Portable, unlike chmod games.
    let bad = Data([0xFF, 0xFE, 0x00, 0x01])
    if plan {
        try bad.write(to: root.appendingPathComponent("Specs/001-x/plan.md"))
    } else {
        try "---\nfeature: 001\ntitle: t\nphase: null\nstatus: Planned\nupdated: x\n---\n"
            .write(to: root.appendingPathComponent("Specs/001-x/plan.md"), atomically: true, encoding: .utf8)
        try bad.write(to: root.appendingPathComponent("ADRs/0001-broken.md"))
    }
    return root
}

// MARK: - The command line refuses what it does not recognise

@Test func acceptsTheCheckFlag() throws {
    let cmd = try Plans.parse(["--check"])
    #expect(cmd.check == true)
}

@Test func defaultsToRewritingWhenNoFlagIsGiven() throws {
    #expect(try Plans.parse([]).check == false)
}

@Test func refusesAMistypedFlagInsteadOfIgnoringIt() {
    // The previous hand-rolled reader accepted this and ran in rewrite mode while
    // printing the same success line, so automation could report green having
    // verified nothing.
    #expect(throws: (any Error).self) { _ = try Plans.parse(["--chekc"]) }
}

@Test func refusesAStrayPositionalArgument() {
    #expect(throws: (any Error).self) { _ = try Plans.parse(["SomeOtherFolder"]) }
}

// MARK: - Degenerate frontmatter is reported, not fatal

@Test func reportsAnEmptyFrontmatterBlockInsteadOfTrapping() {
    // The closing marker sits where the content would start, so the naive
    // arithmetic produced a backwards range and killed the process. A malformed
    // document must produce a readable error, not take the checker down with it.
    #expect(throws: (any Error).self) {
        try Frontmatter.decode(PlanFrontmatter.self, from: "---\n---\n")
    }
}

@Test func reportsAFrontmatterBlockHoldingOnlyBlankLines() {
    #expect(throws: (any Error).self) {
        try Frontmatter.decode(PlanFrontmatter.self, from: "---\n\n---\n")
    }
}

@Test func reportsAnEmptyFrontmatterWithNoTrailingNewline() {
    #expect(throws: (any Error).self) {
        try Frontmatter.decode(PlanFrontmatter.self, from: "---\n---")
    }
}

// MARK: - Windows line endings

@Test func acceptsFrontmatterWrittenWithWindowsLineEndings() throws {
    let front = try Frontmatter.decode(PlanFrontmatter.self, from:
        "---\r\nfeature: 002\r\ntitle: t\r\nphase: null\r\nstatus: Planned\r\nupdated: 2026-01-01\r\n---\r\nbody")
    #expect(front.feature == "002")
}

// MARK: - A line starting with a bar is not always a table

@Test func ignoresALineThatStartsWithABarButHoldsNoColumns() {
    // A list continuation written as "| - item" has one bar and no columns. Treating
    // it as a header would make every following real table row look wrong.
    let rows = Tables.malformedRows(in: """
    | - a continuation, not a table
    | - another one

    | a | b |
    |---|---|
    | one | two |
    """)
    #expect(rows.isEmpty)
}

// MARK: - A failed write says why

@Test func reportsWhyAnIndexCouldNotBeWritten() throws {
    let fm = FileManager.default
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("readonly-\(UUID().uuidString)")
    try fm.createDirectory(at: root.appendingPathComponent("Specs/001-x"), withIntermediateDirectories: true)
    try fm.createDirectory(at: root.appendingPathComponent("ADRs"), withIntermediateDirectories: true)
    try "---\nfeature: 001\ntitle: t\nphase: null\nstatus: Planned\nupdated: x\n---\n"
        .write(to: root.appendingPathComponent("Specs/001-x/plan.md"), atomically: true, encoding: .utf8)
    for p in ["Specs/README.md", "ADRs/README.md"] {
        try "\(beginMarker)\n\(endMarker)\n".write(to: root.appendingPathComponent(p), atomically: true, encoding: .utf8)
    }
    let specsDir = root.appendingPathComponent("Specs")
    try fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: specsDir.path)
    defer {
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: specsDir.path)
        try? fm.removeItem(at: root)
    }

    let report = Indexer(development: root).run(check: false)
    let e = try #require(report.errors.first { $0.contains("Specs/README.md") })
    #expect(!e.hasSuffix("could not be written"))   // must say why, not just that
    #expect(e.lowercased().contains("permission") || e.lowercased().contains("couldn"))
}

// MARK: - The closing fence must be a line of its own

@Test func refusesADocumentWhoseFrontmatterIsNeverClosed() {
    // A horizontal rule in the body is not a terminator. Accepting one meant a
    // document missing its closing fence parsed anyway, from whatever happened to
    // come first.
    #expect(throws: Frontmatter.ParseError("frontmatter is not closed with ---")) {
        try Frontmatter.decode(PlanFrontmatter.self, from:
            "---\nfeature: 1\ntitle: t\nphase: null\nstatus: Planned\nupdated: x\n----------\n")
    }
    #expect(throws: Frontmatter.ParseError("frontmatter is not closed with ---")) {
        try Frontmatter.decode(PlanFrontmatter.self, from:
            "---\nfeature: 1\ntitle: t\nphase: null\nstatus: Planned\nupdated: x\n--- notes\n")
    }
}

@Test func stillAcceptsAProperlyClosedDocumentEndingAtTheFence() throws {
    let front = try Frontmatter.decode(PlanFrontmatter.self, from:
        "---\nfeature: 1\ntitle: t\nphase: null\nstatus: Planned\nupdated: x\n---")
    #expect(front.title == "t")
}

// MARK: - Divider rows are structural, not guessed from punctuation

@Test func flagsAOneColumnRowWhoseOnlyCellIsADash() {
    // Treated as a divider before, because it strips to nothing and holds a dash,
    // so a genuinely malformed row was skipped rather than reported.
    let rows = Tables.malformedRows(in: "| a | b | c |\n|---|---|---|\n| x | y | z |\n| - |\n")
    #expect(rows.count == 1)
    #expect(rows.first?.columns == 1)
}

@Test func stillSkipsTheRealDividerRowIncludingTheMinimalForm() {
    #expect(Tables.malformedRows(in: "| a | b |\n|-|-|\n| x | y |\n").isEmpty)
    #expect(Tables.malformedRows(in: "| a | b |\n|:--|--:|\n| x | y |\n").isEmpty)
}

// MARK: - "Empty" means empty, not "starts with three dashes"

@Test func doesNotCallAnUnclosedDocumentEmptyJustBecauseItsBodyStartsWithDashes() {
    #expect(throws: Frontmatter.ParseError("frontmatter is not closed with ---")) {
        try Frontmatter.decode(PlanFrontmatter.self, from: "---\n---foo\nbar\n")
    }
}

@Test func stillReportsAGenuinelyEmptyBlock() {
    #expect(throws: Frontmatter.ParseError("frontmatter is empty")) {
        try Frontmatter.decode(PlanFrontmatter.self, from: "---\n---\n")
    }
}

// MARK: - An unreadable index says why

@Test func saysWhyAnIndexFileCouldNotBeRead() throws {
    let fm = FileManager.default
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("unreadable-index-\(UUID().uuidString)")
    try fm.createDirectory(at: root.appendingPathComponent("Specs"), withIntermediateDirectories: true)
    try fm.createDirectory(at: root.appendingPathComponent("ADRs"), withIntermediateDirectories: true)
    try Data([0xFF, 0xFE, 0x00]).write(to: root.appendingPathComponent("Specs/README.md"))
    try "\(beginMarker)\n\(endMarker)\n".write(to: root.appendingPathComponent("ADRs/README.md"),
                                               atomically: true, encoding: .utf8)
    defer { try? fm.removeItem(at: root) }

    let report = Indexer(development: root).run(check: false)
    let e = try #require(report.errors.first { $0.contains("Specs/README.md") })
    #expect(!e.hasSuffix("cannot be read"))
    #expect(e.lowercased().contains("format") || e.lowercased().contains("couldn"))
}

// MARK: - A number must match its folder or file exactly, not merely start it

@Test func refusesAFolderWhoseNumberOnlyStartsWithTheFeatureNumber() throws {
    // "0220-foo" begins with "022", so a prefix test accepted it and produced an
    // index row numbered 022 pointing at folder 0220.
    let root = try makeNumberedTree(folder: "0220-foo", feature: "022")
    defer { try? FileManager.default.removeItem(at: root) }
    let report = Indexer(development: root).run(check: false)
    #expect(report.errors.contains { $0.contains("does not match folder") })
}

@Test func stillAcceptsAFolderWhoseNumberMatchesExactly() throws {
    let root = try makeNumberedTree(folder: "022-foo", feature: "022")
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(Indexer(development: root).run(check: false).errors.isEmpty)
}

@Test func refusesADecisionRecordWhoseNumberDisagreesWithItsFileName() throws {
    let root = try makeNumberedTree(folder: "001-x", feature: "001", adrFile: "0001-a.md", adrNumber: "0002")
    defer { try? FileManager.default.removeItem(at: root) }
    let report = Indexer(development: root).run(check: false)
    #expect(report.errors.contains { $0.contains("does not match file") })
}

private func makeNumberedTree(folder: String, feature: String,
                              adrFile: String = "0001-a.md", adrNumber: String = "0001") throws -> URL {
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("num-\(UUID().uuidString)")
    let fm = FileManager.default
    try fm.createDirectory(at: root.appendingPathComponent("Specs/\(folder)"), withIntermediateDirectories: true)
    try fm.createDirectory(at: root.appendingPathComponent("ADRs"), withIntermediateDirectories: true)
    try "---\nfeature: \(feature)\ntitle: t\nphase: null\nstatus: Planned\nupdated: 2026-01-01\n---\n"
        .write(to: root.appendingPathComponent("Specs/\(folder)/plan.md"), atomically: true, encoding: .utf8)
    try "---\nadr: \(adrNumber)\ntitle: t\nstatus: Accepted\ndate: 2026-01-01\n---\n"
        .write(to: root.appendingPathComponent("ADRs/\(adrFile)"), atomically: true, encoding: .utf8)
    for p in ["Specs/README.md", "ADRs/README.md"] {
        try "\(beginMarker)\n\(endMarker)\n".write(to: root.appendingPathComponent(p), atomically: true, encoding: .utf8)
    }
    return root
}

// MARK: - A missing folder is reported as a missing folder

@Test func namesTheMissingFolderRatherThanAFileItNeverOpened() throws {
    let fm = FileManager.default
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("nofolder-\(UUID().uuidString)")
    try fm.createDirectory(at: root.appendingPathComponent("ADRs"), withIntermediateDirectories: true)
    try "\(beginMarker)\n\(endMarker)\n".write(to: root.appendingPathComponent("ADRs/README.md"),
                                               atomically: true, encoding: .utf8)
    defer { try? fm.removeItem(at: root) }   // Specs/ deliberately absent

    let report = Indexer(development: root).run(check: false)
    let e = try #require(report.errors.first { $0.contains("Specs") })
    // Pointing at Specs/README.md would name a file the tool never tried to open.
    #expect(!e.contains("README.md"))
    #expect(e.contains("Specs") && e.lowercased().contains("exist"))
}

// MARK: - Any unreadable document is reported, not just the ones with frontmatter

@Test func reportsAnUnreadableDocumentThatIsNeitherAPlanNorARecord() throws {
    let fm = FileManager.default
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("corrupt-\(UUID().uuidString)")
    try fm.createDirectory(at: root.appendingPathComponent("Specs"), withIntermediateDirectories: true)
    try fm.createDirectory(at: root.appendingPathComponent("ADRs"), withIntermediateDirectories: true)
    for p in ["Specs/README.md", "ADRs/README.md"] {
        try "\(beginMarker)\n\(endMarker)\n".write(to: root.appendingPathComponent(p),
                                                   atomically: true, encoding: .utf8)
    }
    try Data([0xFF, 0xFE, 0x00]).write(to: root.appendingPathComponent("constitution.md"))
    defer { try? fm.removeItem(at: root) }

    _ = Indexer(development: root).run(check: false)          // make the indexes current
    let report = Indexer(development: root).run(check: true)  // then check
    #expect(report.errors.contains { $0.contains("constitution.md") })
}

@Test func doesNotReportTheSameUnreadableFileTwice() throws {
    let fm = FileManager.default
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dupe-\(UUID().uuidString)")
    try fm.createDirectory(at: root.appendingPathComponent("Specs/001-x"), withIntermediateDirectories: true)
    try fm.createDirectory(at: root.appendingPathComponent("ADRs"), withIntermediateDirectories: true)
    for p in ["Specs/README.md", "ADRs/README.md"] {
        try "\(beginMarker)\n\(endMarker)\n".write(to: root.appendingPathComponent(p),
                                                   atomically: true, encoding: .utf8)
    }
    try Data([0xFF, 0xFE, 0x00]).write(to: root.appendingPathComponent("Specs/001-x/plan.md"))
    defer { try? fm.removeItem(at: root) }

    let report = Indexer(development: root).run(check: false)
    #expect(report.errors.filter { $0.contains("001-x/plan.md") }.count == 1)
}

// MARK: - Coverage honesty: a ticked task still cites, and only `verifies` claims a test

private func makeCoverageTree(spec: String, tasks: String, planExtra: String = "SC-001") throws -> URL {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("coverage-\(UUID().uuidString)")
    let fm = FileManager.default
    try fm.createDirectory(at: root.appendingPathComponent("Specs/002-thing"), withIntermediateDirectories: true)
    try fm.createDirectory(at: root.appendingPathComponent("ADRs"), withIntermediateDirectories: true)
    try """
    ---
    feature: 002
    title: A thing
    phase: null
    status: Planned
    updated: 2026-08-31
    ---
    # A thing
    \(planExtra)
    """.write(to: root.appendingPathComponent("Specs/002-thing/plan.md"), atomically: true, encoding: .utf8)
    try spec.write(to: root.appendingPathComponent("Specs/002-thing/spec.md"), atomically: true, encoding: .utf8)
    try tasks.write(to: root.appendingPathComponent("Specs/002-thing/tasks.md"), atomically: true, encoding: .utf8)
    try "---\nadr: 1\ntitle: A choice\nstatus: Accepted\ndate: 2026-05-07\n---\n"
        .write(to: root.appendingPathComponent("ADRs/0001-a-choice.md"), atomically: true, encoding: .utf8)
    for p in ["Specs/README.md", "ADRs/README.md"] {
        try "# Index\n\n\(beginMarker)\n\(endMarker)\n".write(to: root.appendingPathComponent(p), atomically: true, encoding: .utf8)
    }
    return root
}

private let coveredSpec = """
# Spec

### Acceptance scenarios

1. **Given** x, **when** y, **then** z — covers FR-001, FR-002.

- **FR-001** First.
- **FR-002** Second.
- **SC-001** An outcome.
"""

@Test func aTickedTaskStillAttributesItsCitations() throws {
    // `- [x]` marked the slice landed — but the cite still counts, since a
    // finished task does not stop serving its requirement. Recognising only
    // `- [ ]` made the first merge misread completion as a coverage gap.
    let tasks = "- [x] T001 Build it (FR-001)\n- [ ] T002 Tests (verifies FR-001)\n- [ ] T003 Rest (FR-002)\n"
    let root = try makeCoverageTree(spec: coveredSpec, tasks: tasks)
    defer { try? FileManager.default.removeItem(at: root) }
    let report = Indexer(development: root).run(check: false)
    let text = report.coverage.joined(separator: "\n")
    #expect(text.contains("FR-001 → T001, T002 · tests: T002 · scenario: 1"))
}

@Test func onlyAVerifiesCiteClaimsTestCoverage() throws {
    // Naming a test file is a cite about where tests live, not a claim that
    // this task's tests exercise the requirement. Before the marker existed the
    // map credited any task whose prose said "test".
    let tasks = """
    - [ ] T001 Build it (FR-001)
    - [ ] T002 Update `Sources/XTests/FooTests.swift` (FR-002)
    - [ ] T003 Test it (verifies FR-001)
    """
    let root = try makeCoverageTree(spec: coveredSpec, tasks: tasks)
    defer { try? FileManager.default.removeItem(at: root) }
    let report = Indexer(development: root).run(check: false)
    let text = report.coverage.joined(separator: "\n")
    #expect(text.contains("FR-001 → T001, T003 · tests: T003 · scenario: 1"))
    #expect(text.contains("FR-002 → T002 · tests: — · scenario: 1"))
}

@Test func warningsDoNotFailTheCheck() throws {
    // Scenario-only verification warns without erroring — device-verified is an
    // honest state, and `warning:` exists so it is not lost among the notes.
    let root = try makeCoverageTree(spec: coveredSpec, tasks: "- [ ] T001 Do it (FR-001, FR-002)\n")
    defer { try? FileManager.default.removeItem(at: root) }
    let report = Indexer(development: root).run(check: false)
    #expect(!report.warnings.isEmpty)
    #expect(!report.isFailure)
}

// MARK: - Definitions live in the sections that define them

@Test func aBoldedIDOutsideTheDefinitionSectionsIsNotADefinition() throws {
    // **FR-009** is bolded for emphasis inside a scenario; it is not a
    // definition, so nothing owes it a cite. Before the scan was scoped to the
    // defining sections, that tag minted a phantom requirement whose "never
    // cited" error then blamed tasks.md.
    let spec = """
    # Spec

    ### Functional requirements

    - **FR-001** The only one.

    ### Measurable outcomes

    - **SC-001** An outcome.

    ### Acceptance scenarios

    1. **Given** x, **when** y, **then** **FR-009** elsewhere — covers FR-001.
    """
    let root = try makeCoverageTree(spec: spec, tasks: "- [ ] T001 Do it (verifies FR-001)\n")
    defer { try? FileManager.default.removeItem(at: root) }
    let report = Indexer(development: root).run(check: false)
    #expect(report.errors.isEmpty)
    #expect(!report.coverage.joined(separator: "\n").contains("FR-009"))
}

@Test func aSpecWithoutDefinitionSectionsIsStillScannedWhole() throws {
    // A minimal spec with no requirement headings keeps the old behaviour:
    // bolded IDs anywhere in it are definitions.
    let spec = "# Spec\n\n- **FR-001** The only one.\n- **SC-001** An outcome.\n"
    let root = try makeCoverageTree(spec: spec, tasks: "- [ ] T001 Do it (verifies FR-001)\n")
    defer { try? FileManager.default.removeItem(at: root) }
    let report = Indexer(development: root).run(check: false)
    #expect(report.errors.isEmpty)
    #expect(report.coverage.joined(separator: "\n").contains("FR-001 → T001"))
}

// MARK: - A scenario's tag survives losing its indent

@Test func aFlushLeftCoversLineStillAttributesToItsScenario() throws {
    // A wrapped "covers" line that loses its indent used to end the scenario,
    // silently unmapping its requirements.
    let spec = """
    # Spec

    ### Acceptance scenarios

    1. **Given** x, **when** y, **then** z —
    covers FR-001

    - **FR-001** First.
    - **SC-001** An outcome.
    """
    let root = try makeCoverageTree(spec: spec, tasks: "- [ ] T001 Do it (verifies FR-001)\n")
    defer { try? FileManager.default.removeItem(at: root) }
    let report = Indexer(development: root).run(check: false)
    #expect(report.coverage.joined(separator: "\n").contains("FR-001 → T001 · tests: T001 · scenario: 1"))
}

// MARK: - A template is not a feature; a cited record must be listed

@Test func theTemplateFolderPrintsNoCoverageMap() throws {
    // _template satisfies the sibling checks it demonstrates, but it is not a
    // feature — a coverage line for it is permanent noise on every run.
    let root = try makeCoverageTree(spec: coveredSpec, tasks: "- [ ] T001 Do it (verifies FR-001)\n")
    defer { try? FileManager.default.removeItem(at: root) }
    let template = root.appendingPathComponent("Specs/_template")
    try FileManager.default.createDirectory(at: template, withIntermediateDirectories: true)
    try "---\nfeature: NNN\ntitle: skeleton\nphase: null\nstatus: Planned\nupdated: YYYY-MM-DD\n---\n"
        .write(to: template.appendingPathComponent("plan.md"), atomically: true, encoding: .utf8)
    try coveredSpec.write(to: template.appendingPathComponent("spec.md"), atomically: true, encoding: .utf8)
    try "- [ ] T001 Do it (verifies FR-001)\n"
        .write(to: template.appendingPathComponent("tasks.md"), atomically: true, encoding: .utf8)
    let report = Indexer(development: root).run(check: false)
    #expect(report.coverage.allSatisfy { !$0.contains("_template") })
}

@Test func aDecisionRecordCitedButNotListedWarns() throws {
    // The adrs: field checks listed→exists; this is the other direction. A
    // mention is not proof the record belongs to the feature — but a record the
    // plan relies on without listing is exactly the omission the field is for,
    // so it warns for a human to resolve.
    let root = try makeCoverageTree(spec: coveredSpec, tasks: "- [ ] T001 Do it (verifies FR-001)\n")
    defer { try? FileManager.default.removeItem(at: root) }
    let plan = root.appendingPathComponent("Specs/002-thing/plan.md")
    let text = try String(contentsOf: plan, encoding: .utf8)
    try text.replacingOccurrences(of: "updated: 2026-08-31", with: "updated: 2026-08-31\nadrs: [0001]")
        .appending("\nThe run never bypasses Tor — ADR 0002's rule.\n")
        .write(to: plan, atomically: true, encoding: .utf8)
    let report = Indexer(development: root).run(check: false)
    #expect(report.warnings.contains { $0.contains("ADR 0002") && $0.contains("absent from plan.md's adrs:") })
    #expect(!report.warnings.contains { $0.contains("ADR 0001") })
}

@Test func anADRListTailCitesEveryNumberInIt() throws {
    // "ADRs 0001 and 0002" names two records; a pattern that stops at the
    // first digit group silently drops the tail.
    let root = try makeCoverageTree(spec: coveredSpec, tasks: "- [ ] T001 Do it (verifies FR-001)\n")
    defer { try? FileManager.default.removeItem(at: root) }
    let plan = root.appendingPathComponent("Specs/002-thing/plan.md")
    let text = try String(contentsOf: plan, encoding: .utf8)
    try text.replacingOccurrences(of: "updated: 2026-08-31", with: "updated: 2026-08-31\nadrs: [0001]")
        .appending("\nTiming per ADRs 0001 and 0002.\n")
        .write(to: plan, atomically: true, encoding: .utf8)
    let report = Indexer(development: root).run(check: false)
    #expect(report.warnings.contains { $0.contains("ADR 0002") && $0.contains("absent from plan.md's adrs:") })
    #expect(!report.warnings.contains { $0.contains("ADR 0001") })
}

@Test func aPlanOnlyFeatureStillGetsVerificationScrutiny() throws {
    // With no tasks.md nothing can carry a `verifies` cite — but a plan-cited
    // requirement with no scenario still has no verification path (the error
    // tier), and scenario-only still warns. Gating both on `tasks != nil`
    // made plan-only features invisible to the check.
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("planonly-\(UUID().uuidString)")
    let fm = FileManager.default
    try fm.createDirectory(at: root.appendingPathComponent("Specs/002-thing"), withIntermediateDirectories: true)
    try fm.createDirectory(at: root.appendingPathComponent("ADRs"), withIntermediateDirectories: true)
    try """
    ---
    feature: 002
    title: A thing
    phase: null
    status: Planned
    updated: 2026-08-31
    ---
    # A thing
    FR-001 FR-002 SC-001
    """.write(to: root.appendingPathComponent("Specs/002-thing/plan.md"), atomically: true, encoding: .utf8)
    try """
    # Spec

    ### Acceptance scenarios

    1. **Given** x, **when** y, **then** z — covers FR-002.

    - **FR-001** First.
    - **FR-002** Second.
    - **SC-001** An outcome.
    """.write(to: root.appendingPathComponent("Specs/002-thing/spec.md"), atomically: true, encoding: .utf8)
    for p in ["Specs/README.md", "ADRs/README.md"] {
        try "\(beginMarker)\n\(endMarker)\n".write(to: root.appendingPathComponent(p), atomically: true, encoding: .utf8)
    }
    defer { try? fm.removeItem(at: root) }

    let report = Indexer(development: root).run(check: false)
    #expect(report.errors.contains { $0.contains("FR-001") && $0.contains("no verification path") })
    #expect(report.warnings.contains { $0.contains("FR-002") && $0.contains("scenario") })
}
