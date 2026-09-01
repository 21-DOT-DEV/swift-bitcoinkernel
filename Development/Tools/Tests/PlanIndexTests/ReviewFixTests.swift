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
