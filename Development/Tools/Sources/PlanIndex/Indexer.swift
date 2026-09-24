//
//  Indexer.swift
//  21-DOT-DEV/swift-bitcoinkernel
//
//  Copyright (c) 2026-present Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information

import Foundation

public let beginMarker = "<!-- BEGIN GENERATED INDEX -->"
public let endMarker = "<!-- END GENERATED INDEX -->"
public let softLineLimit = 250

/// Sibling files a feature folder may carry beside plan.md. spec.md defines
/// requirement and outcome IDs; tasks.md and plan.md are the citation targets.
public let specSiblings = ["spec.md", "tasks.md", "research.md"]

public let specStatuses = ["Planned", "In Progress", "Implemented"]
public let adrStatuses = ["Proposed", "Accepted", "Superseded"]

public struct Report: Sendable {
    public var errors: [String] = []
    /// Warnings are problems a human should see but a check cannot prove —
    /// they print under their own prefix and never decide `isFailure`. Keeping
    /// them out of `notes` matters: that stream also carries the routine
    /// length advisories, and a real gap printed there is scrolled past.
    public var warnings: [String] = []
    public var notes: [String] = []
    /// The requirement→work map, printed between the notes and the outcome line.
    /// Computed at check time rather than stored in any file: a persisted matrix
    /// is a snapshot that decays; this one is current on every run.
    public var coverage: [String] = []
    public var rewritten: [String] = []
    public var specCount = 0
    public var adrCount = 0
    public var isFailure: Bool { !errors.isEmpty }
}

public struct SpecRow: Equatable, Sendable {
    public let number: String, title: String, phase: String, status: String, link: String
}

public struct ADRRow: Equatable, Sendable {
    public let number: String, title: String, status: String, date: String, file: String
}

public enum Tables {
    /// Escaping happens here, at the moment a value becomes Markdown, rather than
    /// when the file is read. A title is data; this tool renders it to more than one
    /// place, and refusing a character because a table dislikes it would reject a
    /// value that is perfectly valid everywhere else.
    ///
    /// The backslash goes first: escaping it afterwards would consume the escapes
    /// added before it.
    static func cell(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "|", with: "\\|")
    }

    /// Text inside `[...]`: an unmatched bracket ends the link early.
    static func linkText(_ s: String) -> String {
        cell(s).replacingOccurrences(of: "[", with: "\\[")
               .replacingOccurrences(of: "]", with: "\\]")
    }

    /// A destination inside `(...)`: an unmatched parenthesis ends the link early.
    static func linkDestination(_ s: String) -> String {
        cell(s).replacingOccurrences(of: "(", with: "\\(")
               .replacingOccurrences(of: ")", with: "\\)")
    }

    public static func specTable(_ rows: [SpecRow]) -> String {
        (["| # | Feature | Phase | Status | Plan |", "|---|---|---|---|---|"]
            + rows.map { "| \(cell($0.number)) | \(cell($0.title)) | \(cell($0.phase)) | \(cell($0.status)) | [plan.md](\(linkDestination($0.link))) |" })
            .joined(separator: "\n")
    }

    public static func adrTable(_ rows: [ADRRow]) -> String {
        (["| # | Decision | Status | Date |", "|---|---|---|---|"]
            + rows.map { "| \(cell($0.number)) | [\(linkText($0.title))](\(linkDestination($0.file))) | \(cell($0.status)) | \(cell($0.date)) |" })
            .joined(separator: "\n")
    }

    /// Counts dividers that are not escaped, so `\\|` inside a cell does not
    /// split it.
    static func columnCount(_ line: String) -> Int {
        var bars = 0, escaped = false
        for ch in line {
            if escaped { escaped = false; continue }
            if ch == "\\" { escaped = true; continue }
            if ch == "|" { bars += 1 }
        }
        return max(0, bars - 1)
    }

    /// Rows whose column count disagrees with the header above them. A stray
    /// divider inside prose silently adds a column and renders the row wrong,
    /// which is how one such row survived at least one prior review.
    public static func malformedRows(in text: String) -> [(line: Int, columns: Int, expected: Int)] {
        var out: [(line: Int, columns: Int, expected: Int)] = []
        var expected: Int? = nil
        var rowsSeen = 0
        for (index, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("|") else { expected = nil; rowsSeen = 0; continue }
            if expected == nil {
                // A prose line such as "| - an item" carries one divider and no
                // columns. Treating it as a header would measure every real row
                // that follows against nothing.
                let n = columnCount(line)
                if n > 0 { expected = n; rowsSeen = 1 }
                continue
            }
            // The row straight after the header is the delimiter, by definition of
            // the format. Recognising it by its punctuation instead meant a genuinely
            // malformed row like "| - |" was mistaken for one and never reported.
            if rowsSeen == 1 { rowsSeen = 2; continue }
            let n = columnCount(line)
            if n != expected! { out.append((line: index + 1, columns: n, expected: expected!)) }
        }
        return out
    }

    /// Swaps the block between the markers. Returns nil when a marker is absent,
    /// which is an error rather than something to paper over.
    public static func replacingIndex(in text: String, with table: String) -> String? {
        guard let b = text.range(of: beginMarker), let e = text.range(of: endMarker), b.upperBound <= e.lowerBound
        else { return nil }
        return text.replacingCharacters(in: b.lowerBound..<e.upperBound,
                                        with: "\(beginMarker)\n\(table)\n\(endMarker)")
    }
}

public struct Indexer {
    let development: URL
    let fm = FileManager.default

    /// Normalised once, here, so every path derived from it shares one form. Mixing
    /// a relative or unresolved base with the absolute, symlink-resolved paths the
    /// directory walker returns produced relative paths that pointed nowhere.
    public init(development: URL) {
        self.development = development.absoluteURL.resolvingSymlinksInPath().standardizedFileURL
    }

    func read(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }
    /// Names the folder that was actually read, so an error never points at a
    /// directory the tool did not open.
    func rel(_ url: URL) -> String {
        // Both sides are resolved first. The directory walker hands back paths with
        // symlinks already followed while the base path is as given, so on a system
        // where /tmp points at /private/tmp the prefix failed to strip and produced a
        // mangled path that pointed nowhere.
        let base = development.path
        let full = url.absoluteURL.resolvingSymlinksInPath().standardizedFileURL.path
        let suffix = full.hasPrefix(base + "/") ? String(full.dropFirst(base.count + 1)) : full
        return development.lastPathComponent + "/" + suffix
    }

    func noteIfLong(_ url: URL, _ text: String, into report: inout Report) {
        let n = text.split(separator: "\n", omittingEmptySubsequences: false).count
        if n > softLineLimit { report.notes.append("\(rel(url)): \(n) lines (over the \(softLineLimit)-line advisory mark)") }
    }

    /// Returns nil when the folder itself could not be listed, which is a different
    /// problem from an empty folder and must not be reported as a missing index file.
    public func collectSpecs(into report: inout Report) -> [SpecRow]? {
        let specs = development.appendingPathComponent("Specs")
        let dirs: [String]
        do { dirs = try fm.contentsOfDirectory(atPath: specs.path).sorted() }
        catch {
            report.errors.append("\(rel(specs)): \((error as NSError).localizedDescription)")
            return nil
        }
        let adrsDir = development.appendingPathComponent("ADRs")
        let adrFiles: [String]?
        // A folder that fails to list is reported, not swallowed: `try?` would
        // turn it into an empty list and every plan's adrs: field would then
        // error "no such record exists" — burying the real fault under spurious
        // ones, exactly the cascade the unreadable-sibling rule exists to stop.
        do { adrFiles = try fm.contentsOfDirectory(atPath: adrsDir.path) }
        catch {
            report.errors.append("\(rel(adrsDir)): \((error as NSError).localizedDescription)")
            adrFiles = nil
        }
        var rows: [SpecRow] = []
        for name in dirs where !name.hasPrefix("_") && !name.hasPrefix(".") {
            let dir = specs.appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let plan = dir.appendingPathComponent("plan.md")
            let text: String
            do { text = try read(plan) }
            catch {
                // "Absent" is claimed only when the file really is absent. Anything
                // else reports the system's own reason, which already separates
                // missing, forbidden and malformed in plain words.
                report.errors.append(fm.fileExists(atPath: plan.path)
                    ? "\(rel(plan)): \((error as NSError).localizedDescription)"
                    : "\(rel(dir)): has no plan.md")
                continue
            }
            let front: PlanFrontmatter
            do { front = try Frontmatter.decode(PlanFrontmatter.self, from: text) }
            catch { report.errors.append("\(rel(plan)): \((error as? Frontmatter.ParseError)?.reason ?? "\(error)")"); continue }

            // The likeliest copy-paste mistake: the file was created from the
            // template and its instruction comment survived the commit.
            if text.contains("Delete this comment") {
                report.errors.append("\(rel(plan)): the template's \"Delete this comment\" marker was not removed")
            }
            let padded = String(repeating: "0", count: max(0, 3 - front.feature.count)) + front.feature
            // The whole leading run of digits, not merely a prefix: "0220-foo" starts
            // with "022", so a prefix test paired feature 022 with folder 0220 and
            // published a row whose number and link disagreed.
            if String(name.prefix(while: \.isNumber)) != padded {
                report.errors.append("\(rel(plan)): feature '\(front.feature)' does not match folder '\(name)'")
            }
            if !specStatuses.contains(front.status) {
                report.errors.append("\(rel(plan)): status '\(front.status)' is not one of \(specStatuses)")
            }
            if let adrFiles {
                for adr in front.adrs ?? [] {
                    let paddedADR = String(repeating: "0", count: max(0, 4 - String(adr).count)) + String(adr)
                    if !adrFiles.contains(where: { $0.hasPrefix("\(paddedADR)-") && $0.hasSuffix(".md") }) {
                        report.errors.append("\(rel(plan)): adrs lists \(paddedADR) but no such record exists")
                    }
                }
            }
            noteIfLong(plan, text, into: &report)
            checkSiblings(in: dir, planText: text, adrs: front.adrs, into: &report)
            rows.append(SpecRow(number: padded, title: front.title,
                                phase: front.phase ?? "—", status: front.status,
                                link: "\(name)/plan.md"))
        }
        // The template folder is exempt from indexing but not from the rules it
        // teaches: a verbatim copy must satisfy the sibling contract.
        let template = specs.appendingPathComponent("_template")
        if let planText = try? read(template.appendingPathComponent("plan.md")) {
            checkSiblings(in: template, planText: planText,
                          adrs: (try? Frontmatter.decode(PlanFrontmatter.self, from: planText))?.adrs,
                          isTemplate: true, into: &report)
        }
        return rows
    }

    /// The siblings share a contract the index table cannot express: they carry
    /// no frontmatter (status lives in plan.md alone), and every ID spec.md
    /// defines is cited where the work or verification lives. A rule that
    /// exists only on review fails silently the first time it matters.
    func checkSiblings(in dir: URL, planText: String, adrs: [Int]? = nil,
                       isTemplate: Bool = false, into report: inout Report) {
        var texts: [String: String] = [:]
        var unreadable = Set<String>()
        for name in specSiblings {
            let url = dir.appendingPathComponent(name)
            guard fm.fileExists(atPath: url.path) else { continue }
            do {
                let text = try read(url)
                // A stray blank line before the block does not make it prose.
                if text.drop(while: \.isWhitespace).hasPrefix("---") {
                    report.errors.append("\(rel(url)): sibling files carry no frontmatter — status lives in plan.md")
                }
                if !isTemplate && text.contains("Delete this comment") {
                    report.errors.append("\(rel(url)): the template's \"Delete this comment\" marker was not removed")
                }
                noteIfLong(url, text, into: &report)
                texts[name] = text
            } catch {
                unreadable.insert(name)
                report.errors.append("\(rel(url)): \((error as NSError).localizedDescription)")
            }
        }
        let (definedFRs, definedSCs) = specIDs(in: texts["spec.md"] ?? "", definitionsOnly: true)
        // Coverage lives where the ordered work does: tasks.md when present and
        // readable, plan.md when a feature has no ordered-work file. A sibling
        // that failed to read does not demote the home — the read error is the
        // report; cascading "never cited" errors would bury it.
        if let tasks = texts["tasks.md"], !unreadable.contains("tasks.md") {
            for id in definedFRs.subtracting(specIDs(in: tasks).frs).sorted() {
                report.errors.append("\(rel(dir))/tasks.md: \(id) is defined in spec.md but never cited")
            }
        } else if !unreadable.contains("tasks.md"), texts["tasks.md"] == nil {
            for id in definedFRs.subtracting(specIDs(in: planText).frs).sorted() {
                report.errors.append("\(rel(dir))/plan.md: \(id) is defined in spec.md but never cited")
            }
        }
        // Dangling cites are wrong in every sibling, research.md included. A
        // cite qualified with another feature's number — `003/FR-004` or
        // `003's FR-004` — points outside this spec and is never dangling here.
        for (file, text) in [("plan.md", planText), ("tasks.md", texts["tasks.md"] ?? ""),
                             ("research.md", texts["research.md"] ?? "")] {
            let own = text.replacingOccurrences(
                of: #"\d{3}(?:'s|/)\s*(?:FR|SC)-\d{3}"#, with: "",
                options: .regularExpression)
            for id in specIDs(in: own).frs.subtracting(definedFRs).sorted() {
                report.errors.append("\(rel(dir))/\(file): \(id) is cited but spec.md defines no such requirement")
            }
            for id in specIDs(in: own).scs.subtracting(definedSCs).sorted() {
                report.errors.append("\(rel(dir))/\(file): \(id) is cited but spec.md defines no such outcome")
            }
        }
        // Coverage for outcomes lives in plan.md's Verification.
        for id in definedSCs.subtracting(specIDs(in: planText).scs).sorted() {
            report.errors.append("\(rel(dir))/plan.md: \(id) is defined in spec.md but never cited")
        }
        // The adrs: check above runs listed→exists; this is the other direction —
        // a record the feature's own text relies on without listing it. A mention
        // is not proof of membership (the field is for records the feature
        // produced, revised, or depends on), so this warns rather than errors.
        // A missing field is an empty list, not a pass: "the feature names the
        // record but declares no relationship" is the same omission.
        let listed = Set(adrs ?? [])
        var mentioners: [Int: Set<String>] = [:]
        for (file, text) in [("plan.md", planText), ("spec.md", texts["spec.md"] ?? ""),
                             ("tasks.md", texts["tasks.md"] ?? ""),
                             ("research.md", texts["research.md"] ?? "")] {
            for n in adrMentions(in: text) where !listed.contains(n) {
                mentioners[n, default: []].insert(file)
            }
        }
        for n in mentioners.keys.sorted() {
            let padded = String(repeating: "0", count: max(0, 4 - String(n).count)) + String(n)
            report.warnings.append("\(rel(dir)): ADR \(padded) is cited in "
                + "\(mentioners[n]!.sorted().joined(separator: ", ")) but absent from plan.md's adrs:")
        }
        // The template folder must satisfy the sibling contract it teaches, but a
        // coverage line for a folder that is not a feature is permanent noise.
        if !isTemplate {
            emitCoverage(for: dir, spec: texts["spec.md"], planText: planText,
                         tasks: unreadable.contains("tasks.md") ? nil : texts["tasks.md"],
                         into: &report)
        }
    }

    /// `ADR 0006`-style mentions — four digits or fewer with the prefix, so
    /// bare numbers in prose never count. A plural carries a list — "ADRs
    /// 0008 and 0009" cites both — so the prefix is followed by a run of
    /// numbers joined by commas, slashes, or a conjunction; each number in
    /// the run is a mention.
    func adrMentions(in text: String) -> [Int] {
        let pattern = try! NSRegularExpression(
            pattern: #"\bADRs?\s+((?:0*\d{1,4}\b[\s,/]*(?:and\s+|or\s+|&\s*)?)+)"#)
        let numbers = try! NSRegularExpression(pattern: #"0*(\d{1,4})"#)
        return pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .flatMap { match -> [Int] in
                guard let tail = Range(match.range(at: 1), in: text) else { return [] }
                return numbers.matches(in: text, range: NSRange(tail, in: text))
                    .compactMap { Range($0.range(at: 1), in: text).flatMap { Int(text[$0]) } }
            }
    }

    /// The citation checks prove every requirement is named somewhere; they
    /// cannot see whether that somewhere tests it, which is how a requirement
    /// ended up cited only by a task that might never be written. This map —
    /// printed, never stored — is what makes that gap visible. "Test-verified"
    /// is claimed only where a task declares it with `verifies FR-NNN`: a cite
    /// says a task serves the requirement, a verifies cite says its tests
    /// exercise it, and conflating the two is how the old map credited an
    /// untested task. A cited requirement with no verifies cite and no
    /// acceptance scenario has no verification path at all — an error; one
    /// covered by a scenario but no test warns, since scenario-only is an
    /// honest state (device-verified) but worth seeing.
    func emitCoverage(for dir: URL, spec: String?, planText: String, tasks: String?,
                      into report: inout Report) {
        guard let spec else { return }
        let (definedFRs, definedSCs) = specIDs(in: spec, definitionsOnly: true)
        guard !definedFRs.isEmpty || !definedSCs.isEmpty else { return }
        let blocks = taskBlocks(in: tasks ?? "")
        let scenarios = scenarioMap(in: spec)
        var cited = 0, tested = 0
        var lines: [String] = []
        for id in definedFRs.sorted() {
            let citing = tasks != nil
                ? blocks.filter { specIDs(in: $0.text).frs.contains(id) }.map(\.id)
                : (specIDs(in: planText).frs.contains(id) ? ["plan.md"] : [])
            let tests = blocks.filter { $0.verifies.frs.contains(id) }.map(\.id)
            if !citing.isEmpty { cited += 1 }
            if !tests.isEmpty { tested += 1 } else if !citing.isEmpty {
                if (scenarios[id] ?? []).isEmpty {
                    report.errors.append("\(rel(dir)): \(id) is cited but has no verification path "
                        + "— no `verifies` cite, no acceptance scenario")
                } else {
                    report.warnings.append("\(rel(dir)): \(id) has no `verifies` cite — "
                        + "verified by scenario \(joinOr((scenarios[id] ?? []).map(String.init))) alone")
                }
            }
            lines.append("  \(id) → \(joinOr(citing)) · tests: \(joinOr(tests)) · scenario: \(joinOr((scenarios[id] ?? []).map(String.init)))")
        }
        var verified = 0
        for id in definedSCs.sorted() {
            let ok = specIDs(in: planText).scs.contains(id)
            if ok { verified += 1 }
            let tests = blocks.filter { $0.verifies.scs.contains(id) }.map(\.id)
            lines.append("  \(id) → \(ok ? "plan.md ✓" : "—")"
                + (tests.isEmpty ? "" : " · tests: \(joinOr(tests))"))
        }
        report.coverage.append("coverage: \(rel(dir)) — \(cited)/\(definedFRs.count) requirements cited, "
            + "\(tested)/\(definedFRs.count) test-verified, \(verified)/\(definedSCs.count) outcomes verified")
        report.coverage.append(contentsOf: lines)
    }

    func joinOr(_ ids: [String]) -> String { ids.isEmpty ? "—" : ids.joined(separator: ", ") }

    /// One task's text is its `- [ ] TNNN` line plus the wrapped continuation
    /// lines that follow, so a cite on either line counts as that task's. Any
    /// checkbox state counts — a ticked (`- [x]`) task still serves its
    /// requirements; dropping it would misread landed work as a gap the moment
    /// the first slice merges. A task's `verifies FR-NNN` cites declare which
    /// requirements its tests exercise — the map counts only those toward test
    /// verification, so a test task sitting beside an implementation cite is
    /// not mistaken for covering it.
    func taskBlocks(in text: String) -> [(id: String, text: String,
                                          verifies: (frs: Set<String>, scs: Set<String>))] {
        var blocks: [(id: String, text: String,
                      verifies: (frs: Set<String>, scs: Set<String>))] = []
        var id: String? = nil, body = ""
        func flush() {
            if let id {
                blocks.append((id, body, verifiesIDs(in: body)))
            }
            body = ""
        }
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.range(of: #"^- \[[ xX]\] T\d{3}\b"#, options: .regularExpression) != nil {
                flush(); id = String(line.dropFirst(6).prefix(4))
                body = line + "\n"
            } else if (line.hasPrefix(" ") || line.hasPrefix("\t")), id != nil {
                body += line + "\n"
            } else {
                flush(); id = nil
            }
        }
        flush()
        return blocks
    }

    /// The IDs a task declares its tests exercise: every `FR-NNN`/`SC-NNN` in
    /// the run following the word `verifies` — `(verifies FR-001, FR-002)` or
    /// `(FR-003; verifies FR-004)`. Any other ID is a cite, not a claim of
    /// verification.
    func verifiesIDs(in text: String) -> (frs: Set<String>, scs: Set<String>) {
        let pattern = try! NSRegularExpression(
            pattern: #"(?i)\bverifies\b((?:[\s,;]*(?:and[\s,;]+)?(?:FR|SC)-\d{3})+)"#)
        var frs = Set<String>(), scs = Set<String>()
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range(at: 1), in: text) else { continue }
            let ids = specIDs(in: String(text[range]))
            frs.formUnion(ids.frs)
            scs.formUnion(ids.scs)
        }
        return (frs, scs)
    }

    /// Numbered items inside the acceptance-scenario section → the requirement
    /// IDs each one exercises (specs tag them "— covers FR-NNN"). A scenario's
    /// text wraps across lines, so IDs accumulate to the current item until the
    /// next number or the section's end.
    func scenarioMap(in spec: String) -> [String: [Int]] {
        var map: [String: [Int]] = [:]
        var inSection = false, current: Int? = nil
        for line in spec.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("#") {
                inSection = line.localizedCaseInsensitiveContains("acceptance scenario")
                current = nil
                continue
            }
            guard inSection else { continue }
            let digits = line.prefix(while: \.isNumber)
            if !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(".") {
                current = Int(digits)
            } else if line.first?.isWhitespace != true && !line.isEmpty {
                // A scenario's wrapped lines are indented; a flush-left line
                // that is not a number is usually new prose — unless it still
                // carries the item's covers-tag, in which case dropping it
                // would silently unmap the scenario.
                if line.range(of: #"covers\s+(?:FR|SC)-\d{3}"#,
                              options: .regularExpression) == nil {
                    current = nil
                }
            }
            guard let n = current else { continue }
            for id in specIDs(in: String(line)).frs where !(map[id] ?? []).contains(n) {
                map[id, default: []].append(n)
            }
        }
        return map
    }

    /// `FR-042`- and `SC-042`-style IDs, split by kind. Three digits keeps the
    /// match off prose like "FR-1" while leaving room to grow. With
    /// `definitionsOnly`, only the bold definition form (`**FR-042**`) counts,
    /// and only inside the Functional-requirements and Measurable-outcomes
    /// sections — a bolded tag in a scenario or edge case is emphasis, not a
    /// definition, and counting it would mint an ID whose errors then point at
    /// the wrong section. A spec with neither heading is scanned whole, so a
    /// minimal spec still parses.
    func specIDs(in text: String, definitionsOnly: Bool = false) -> (frs: Set<String>, scs: Set<String>) {
        // NSRegularExpression rather than `matches(of:)`: this tool builds
        // against macOS 12 and the Regex API requires 13.
        let source = definitionsOnly ? #"\*\*((?:FR|SC)-\d{3})\*\*"# : #"\b((?:FR|SC)-\d{3})\b"#
        let scoped = definitionsOnly ? (definitionSections(in: text) ?? text) : text
        let pattern = try! NSRegularExpression(pattern: source)
        var frs = Set<String>(), scs = Set<String>()
        for match in pattern.matches(in: scoped, range: NSRange(scoped.startIndex..., in: scoped)) {
            guard let range = Range(match.range(at: 1), in: scoped) else { continue }
            let id = String(scoped[range])
            if id.hasPrefix("FR") { frs.insert(id) } else { scs.insert(id) }
        }
        return (frs, scs)
    }

    /// The spec text that can hold definitions: everything under the
    /// Functional-requirements and Measurable-outcomes headings. Returns nil
    /// when the spec uses neither heading — the caller then scans the whole
    /// document rather than silently defining nothing.
    func definitionSections(in text: String) -> String? {
        var out = "", inSection = false, found = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("#") {
                inSection = line.localizedCaseInsensitiveContains("functional requirement")
                    || line.localizedCaseInsensitiveContains("measurable outcome")
                found = found || inSection
                continue
            }
            if inSection { out += line + "\n" }
        }
        return found ? out : nil
    }

    /// Returns nil when the folder itself could not be listed. See `collectSpecs`.
    public func collectADRs(into report: inout Report) -> [ADRRow]? {
        let adrs = development.appendingPathComponent("ADRs")
        let listing: [String]
        do { listing = try fm.contentsOfDirectory(atPath: adrs.path) }
        catch {
            report.errors.append("\(rel(adrs)): \((error as NSError).localizedDescription)")
            return nil
        }
        let files = listing.filter { $0.hasSuffix(".md") && $0.first?.isNumber == true }.sorted()
        var rows: [ADRRow] = []
        for name in files {
            let url = adrs.appendingPathComponent(name)
            let text: String
            do { text = try read(url) }
            catch {
                // Skipping silently would make an unreadable record indistinguishable
                // from one that was never written.
                report.errors.append("\(rel(url)): \((error as NSError).localizedDescription)")
                continue
            }
            let front: ADRFrontmatter
            do { front = try Frontmatter.decode(ADRFrontmatter.self, from: text) }
            catch { report.errors.append("\(rel(url)): \((error as? Frontmatter.ParseError)?.reason ?? "\(error)")"); continue }

            if !adrStatuses.contains(front.status) {
                report.errors.append("\(rel(url)): status '\(front.status)' is not one of \(adrStatuses)")
            }
            let paddedADR = String(repeating: "0", count: max(0, 4 - front.adr.count)) + front.adr
            // Same trap as the feature number: without this a record numbered 0002
            // inside 0001-a.md produced a row whose number and link disagreed.
            if String(name.prefix(while: \.isNumber)) != paddedADR {
                report.errors.append("\(rel(url)): adr '\(front.adr)' does not match file '\(name)'")
            }
            noteIfLong(url, text, into: &report)
            rows.append(ADRRow(number: paddedADR,
                               title: front.title, status: front.status,
                               date: front.date, file: name))
        }
        return rows
    }

    func write(_ table: String, into url: URL, check: Bool, into report: inout Report) {
        let text: String
        do { text = try read(url) }
        catch {
            report.errors.append("\(rel(url)): \((error as NSError).localizedDescription)")
            return
        }
        guard let updated = Tables.replacingIndex(in: text, with: table) else {
            report.errors.append("\(rel(url)): missing the generated-index markers"); return
        }
        guard updated != text else { return }
        if check {
            report.errors.append("\(rel(url)): index is out of date (run: swift run --package-path Development/Tools plans)")
        } else {
            do {
                try updated.write(to: url, atomically: true, encoding: .utf8)
                report.rewritten.append(rel(url))
            } catch {
                // "Could not be written" tells nobody whether the disk is full, the
                // file is read-only, or the folder is not writable.
                report.errors.append("\(rel(url)): \((error as NSError).localizedDescription)")
            }
        }
    }

    /// Every document in the tree, not just the generated ones: a stray divider in
    /// hand-written prose breaks its row exactly the same way.
    func checkTableShapes(into report: inout Report) {
        guard let walker = fm.enumerator(at: development, includingPropertiesForKeys: nil) else { return }
        for case let url as URL in walker {
            guard url.pathExtension == "md", !url.path.contains("/.build/") else { continue }
            let text: String
            do { text = try read(url) }
            catch {
                // Previously skipped with a comment claiming these were reported
                // elsewhere. That was only true for plans, records and the two index
                // files; a corrupt charter or roadmap page vanished without a word.
                report.errors.append("\(rel(url)): \((error as NSError).localizedDescription)")
                continue
            }
            for row in Tables.malformedRows(in: text) {
                report.errors.append(
                    "\(rel(url)):\(row.line): table row has \(row.columns) columns, header has \(row.expected)")
            }
        }
    }

    public func run(check: Bool) -> Report {
        var report = Report()
        let specs = collectSpecs(into: &report)
        let adrs = collectADRs(into: &report)
        report.specCount = specs?.count ?? 0
        report.adrCount = adrs?.count ?? 0
        // A folder that could not be listed has already been reported; writing an
        // index into it would only add a second message about the same problem.
        if let specs {
            write(Tables.specTable(specs), into: development.appendingPathComponent("Specs/README.md"), check: check, into: &report)
        }
        if let adrs {
            write(Tables.adrTable(adrs), into: development.appendingPathComponent("ADRs/README.md"), check: check, into: &report)
        }
        // After the writes, so an index this run has just corrected is not also
        // reported as malformed.
        checkTableShapes(into: &report)
        // One file can be reached by two passes; a reader does not need telling twice.
        var seen = Set<String>()
        report.errors = report.errors.filter { seen.insert($0).inserted }
        var seenWarnings = Set<String>()
        report.warnings = report.warnings.filter { seenWarnings.insert($0).inserted }
        return report
    }
}
