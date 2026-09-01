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

public let specStatuses = ["Planned", "In Progress", "Implemented"]
public let adrStatuses = ["Proposed", "Accepted", "Superseded"]

public struct Report: Sendable {
    public var errors: [String] = []
    public var notes: [String] = []
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
            noteIfLong(plan, text, into: &report)
            rows.append(SpecRow(number: padded, title: front.title,
                                phase: front.phase ?? "—", status: front.status,
                                link: "\(name)/plan.md"))
        }
        return rows
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
        return report
    }
}
