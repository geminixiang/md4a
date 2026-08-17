import Foundation

/// A half-open range measured in UTF-16 code units.
struct AppleTextRange: Equatable, Sendable {
    let start: Int
    let end: Int

    init(_ start: Int, _ end: Int) {
        precondition(start >= 0 && end >= start, "Invalid range [\(start), \(end))")
        self.start = start
        self.end = end
    }

    var length: Int { end - start }
}

/// Anchor and caret are UTF-16 offsets and retain selection direction.
struct AppleEditorSelection: Equatable, Sendable {
    let anchor: Int
    let caret: Int

    static let zero = AppleEditorSelection(anchor: 0, caret: 0)
    var range: AppleTextRange { AppleTextRange(min(anchor, caret), max(anchor, caret)) }
    var isCollapsed: Bool { anchor == caret }
}

struct AppleEditMetrics: Equatable, Sendable {
    let previousLength: Int
    let newLength: Int
    /// Persistent edits retain old pieces rather than copying their characters.
    let existingCodeUnitsCopied: Int
    let insertedCodeUnits: Int
}

/// Immutable, O(1) view of one document revision.
///
/// Snapshots retain the persistent tree and its immutable NSString backing stores.
/// They remain valid while the owning buffer continues to change.
struct AppleDocumentSnapshot: @unchecked Sendable {
    fileprivate let root: ApplePieceNode?

    var length: Int { root?.length ?? 0 }
    var lineCount: Int { (root?.summary.breaks ?? 0) + 1 }

    subscript(offset: Int) -> unichar {
        precondition(offset >= 0 && offset < length, "Offset outside document")
        return character(in: root!, at: offset)
    }

    func text(in range: AppleTextRange? = nil) -> String {
        let requested = range ?? AppleTextRange(0, length)
        validate(requested)
        var result = ""
        result.reserveCapacity(requested.length)
        appendRange(root, nodeStart: 0, requested: requested, into: &result)
        return result
    }

    func line(forOffset offset: Int) -> Int {
        precondition(offset >= 0 && offset <= length, "Offset outside document")
        let count = breakCount(before: offset, in: root)
        if offset > 0, offset < length, self[offset - 1] == 13, self[offset] == 10 {
            return count - 1
        }
        return count
    }

    func lineStart(_ line: Int) -> Int {
        precondition(line >= 0 && line < lineCount, "Line outside document")
        return line == 0 ? 0 : offsetAfterBreak(line, in: root!)
    }

    /// Returns the UTF-16 range of a line without its CR, LF, or CRLF terminator.
    func lineRange(_ line: Int) -> AppleTextRange {
        let start = lineStart(line)
        guard line < lineCount - 1 else { return AppleTextRange(start, length) }
        var end = lineStart(line + 1)
        if end > start, self[end - 1] == 10 { end -= 1 }
        if end > start, self[end - 1] == 13 { end -= 1 }
        return AppleTextRange(start, end)
    }

    func lineText(_ line: Int) -> String { text(in: lineRange(line)) }

    /// Streams UTF-8 piece by piece. No flattened document String is created.
    /// A trailing high surrogate is carried into the next piece so persistent
    /// edits can never turn a valid scalar spanning a piece boundary into U+FFFD.
    func writeUTF8(to output: OutputStream) throws {
        output.open()
        defer { output.close() }
        var streamError: Error?
        var pendingHighSurrogate: unichar?
        enumeratePieces(root) { piece in
            guard streamError == nil else { return }
            var units: [unichar] = []
            units.reserveCapacity(piece.length + (pendingHighSurrogate == nil ? 0 : 1))
            if let carried = pendingHighSurrogate {
                units.append(carried)
                pendingHighSurrogate = nil
            }
            for offset in 0..<piece.length {
                units.append(piece.source.character(at: piece.start + offset))
            }
            if let last = units.last, isHighSurrogate(last) {
                pendingHighSurrogate = units.removeLast()
            }
            guard !units.isEmpty else { return }
            let string = units.withUnsafeBufferPointer {
                String(utf16CodeUnits: $0.baseAddress!, count: $0.count)
            }
            writeUTF8Bytes(string, to: output, error: &streamError)
        }
        if let pendingHighSurrogate, streamError == nil {
            let units = [pendingHighSurrogate]
            let string = units.withUnsafeBufferPointer {
                String(utf16CodeUnits: $0.baseAddress!, count: $0.count)
            }
            writeUTF8Bytes(string, to: output, error: &streamError)
        }
        if let streamError { throw streamError }
    }

    func writeUTF8(to url: URL) throws {
        guard let stream = OutputStream(url: url, append: false) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try writeUTF8(to: stream)
    }

    private func validate(_ range: AppleTextRange) {
        precondition(range.end <= length, "Range outside document")
    }
}

/// Persistent balanced piece tree used by the Apple large-document editor.
///
/// Every replacement path-copies O(log pieces) tree nodes. Existing text remains
/// in immutable backing stores, so a keystroke never copies the whole document.
final class ApplePieceTreeBuffer {
    private struct State {
        let root: ApplePieceNode?
        let selection: AppleEditorSelection
        let revision: UInt64
    }

    private(set) var selection: AppleEditorSelection = .zero
    private(set) var revision: UInt64 = 0
    private(set) var lastEditMetrics: AppleEditMetrics
    private var savedRevision: UInt64
    private var root: ApplePieceNode?
    private var nextPieceID: UInt64 = 1
    private var nextRevision: UInt64 = 1
    private let historyLimit: Int
    private var undoStates: [State] = []
    private var redoStates: [State] = []

    var length: Int { root?.length ?? 0 }
    var lineCount: Int { (root?.summary.breaks ?? 0) + 1 }
    var isDirty: Bool { revision != savedRevision }
    var canUndo: Bool { !undoStates.isEmpty }
    var canRedo: Bool { !redoStates.isEmpty }

    convenience init(data: Data, historyLimit: Int = 100, initiallyDirty: Bool = false) throws {
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        self.init(text: text, historyLimit: historyLimit, initiallyDirty: initiallyDirty)
    }

    init(text: String = "", historyLimit: Int = 100, initiallyDirty: Bool = false) {
        precondition(historyLimit >= 0, "historyLimit must not be negative")
        self.historyLimit = historyLimit
        self.root = nil
        self.savedRevision = initiallyDirty ? UInt64.max : 0
        self.lastEditMetrics = AppleEditMetrics(
            previousLength: text.utf16.count,
            newLength: text.utf16.count,
            existingCodeUnitsCopied: 0,
            insertedCodeUnits: 0
        )
        let source = text as NSString
        root = makePieceTree(source: source)
    }

    func snapshot() -> AppleDocumentSnapshot { AppleDocumentSnapshot(root: root) }

    func setSelection(_ value: AppleEditorSelection) {
        precondition(value.anchor >= 0 && value.anchor <= length && value.caret >= 0 && value.caret <= length)
        selection = value
    }

    func markSaved() { savedRevision = revision }

    func insert(at offset: Int, text: String, selectionAfter: AppleEditorSelection? = nil) {
        replace(AppleTextRange(offset, offset), with: text, selectionAfter: selectionAfter)
    }

    func delete(_ range: AppleTextRange, selectionAfter: AppleEditorSelection? = nil) {
        replace(range, with: "", selectionAfter: selectionAfter)
    }

    func replace(
        _ range: AppleTextRange,
        with replacement: String,
        selectionAfter: AppleEditorSelection? = nil
    ) {
        precondition(range.end <= length, "Range outside document")
        let normalized = scalarAligned(range)
        let insertedLength = replacement.utf16.count
        let resultingLength = length - normalized.length + insertedLength
        let resultingSelection = selectionAfter ?? AppleEditorSelection(
            anchor: normalized.start + insertedLength,
            caret: normalized.start + insertedLength
        )
        precondition(
            resultingSelection.anchor >= 0 && resultingSelection.anchor <= resultingLength &&
            resultingSelection.caret >= 0 && resultingSelection.caret <= resultingLength,
            "Selection outside resulting document"
        )

        let oldLength = length
        push(State(root: root, selection: selection, revision: revision), onto: &undoStates)
        redoStates.removeAll(keepingCapacity: true)
        let (before, remainder) = split(root, at: normalized.start)
        let (_, after) = split(remainder, at: normalized.length)
        let middle = makePieceTree(source: replacement as NSString)
        root = merge(merge(before, middle), after)
        revision = nextRevision
        nextRevision &+= 1
        selection = resultingSelection
        lastEditMetrics = AppleEditMetrics(
            previousLength: oldLength,
            newLength: resultingLength,
            existingCodeUnitsCopied: 0,
            insertedCodeUnits: insertedLength
        )
    }

    @discardableResult
    func undo() -> Bool {
        guard let state = undoStates.popLast() else { return false }
        push(State(root: root, selection: selection, revision: revision), onto: &redoStates)
        restore(state)
        return true
    }

    @discardableResult
    func redo() -> Bool {
        guard let state = redoStates.popLast() else { return false }
        push(State(root: root, selection: selection, revision: revision), onto: &undoStates)
        restore(state)
        return true
    }

    private func restore(_ state: State) {
        root = state.root
        selection = state.selection
        revision = state.revision
        lastEditMetrics = AppleEditMetrics(
            previousLength: length,
            newLength: length,
            existingCodeUnitsCopied: 0,
            insertedCodeUnits: 0
        )
    }

    private func push(_ state: State, onto stack: inout [State]) {
        guard historyLimit > 0 else { return }
        if stack.count == historyLimit { stack.removeFirst() }
        stack.append(state)
    }

    private func makePieceTree(source: NSString) -> ApplePieceNode? {
        var tree: ApplePieceNode?
        var start = 0
        while start < source.length {
            var end = min(start + 16 * 1024, source.length)
            if end < source.length,
               isHighSurrogate(source.character(at: end - 1)),
               isLowSurrogate(source.character(at: end)) {
                end -= 1
            }
            tree = merge(tree, ApplePieceNode(
                piece: ApplePiece(source: source, start: start, length: end - start, id: takePieceID())
            ))
            start = end
        }
        return tree
    }

    private func scalarAligned(_ range: AppleTextRange) -> AppleTextRange {
        let snapshot = snapshot()
        var start = range.start
        var end = range.end
        let startSplitsPair = start > 0 && start < length &&
            isHighSurrogate(snapshot[start - 1]) && isLowSurrogate(snapshot[start])
        if range.length == 0, startSplitsPair {
            start -= 1
            end = start
        } else {
            if startSplitsPair { start -= 1 }
            if end > 0, end < length,
               isHighSurrogate(snapshot[end - 1]), isLowSurrogate(snapshot[end]) { end += 1 }
        }
        return AppleTextRange(start, end)
    }

    private func takePieceID() -> UInt64 {
        defer { nextPieceID &+= 1 }
        return nextPieceID
    }

    private func split(_ node: ApplePieceNode?, at offset: Int) -> (ApplePieceNode?, ApplePieceNode?) {
        guard let node else { return (nil, nil) }
        let leftLength = node.left?.length ?? 0
        if offset < leftLength {
            let (first, second) = split(node.left, at: offset)
            return (first, merge(second, merge(ApplePieceNode(piece: node.piece), node.right)))
        }
        if offset > leftLength + node.piece.length {
            let (first, second) = split(node.right, at: offset - leftLength - node.piece.length)
            return (merge(merge(node.left, ApplePieceNode(piece: node.piece)), first), second)
        }
        let local = offset - leftLength
        let leftPiece = local == 0 ? nil : ApplePieceNode(piece: node.piece.slice(0, local, id: takePieceID()))
        let rightPiece = local == node.piece.length ? nil : ApplePieceNode(
            piece: node.piece.slice(local, node.piece.length, id: takePieceID())
        )
        return (merge(node.left, leftPiece), merge(rightPiece, node.right))
    }
}

private final class ApplePieceNode: @unchecked Sendable {
    let piece: ApplePiece
    let left: ApplePieceNode?
    let right: ApplePieceNode?
    let priority: UInt64
    let length: Int
    let summary: AppleNewlineSummary

    init(piece: ApplePiece, left: ApplePieceNode? = nil, right: ApplePieceNode? = nil) {
        self.piece = piece
        self.left = left
        self.right = right
        self.priority = mixed(piece.id)
        self.length = (left?.length ?? 0) + piece.length + (right?.length ?? 0)
        self.summary = (left?.summary ?? .empty) + piece.summary + (right?.summary ?? .empty)
    }
}

private struct ApplePiece: @unchecked Sendable {
    let source: NSString
    let start: Int
    let length: Int
    let id: UInt64
    let breakOffsets: [Int]
    let summary: AppleNewlineSummary

    init(source: NSString, start: Int, length: Int, id: UInt64, breakOffsets supplied: [Int]? = nil) {
        self.source = source
        self.start = start
        self.length = length
        self.id = id
        if let supplied {
            breakOffsets = supplied
        } else {
            var offsets: [Int] = []
            offsets.reserveCapacity(max(1, length / 40))
            for local in 0..<length {
                let value = source.character(at: start + local)
                if value == 13 || (value == 10 && (local == 0 || source.character(at: start + local - 1) != 13)) {
                    offsets.append(local)
                }
            }
            breakOffsets = offsets
        }
        summary = AppleNewlineSummary(
            length: length,
            breaks: breakOffsets.count,
            startsWithLF: length > 0 && source.character(at: start) == 10,
            endsWithCR: length > 0 && source.character(at: start + length - 1) == 13
        )
    }

    func slice(_ from: Int, _ to: Int, id: UInt64) -> ApplePiece {
        let first = breakOffsets.lowerBound(from)
        let last = breakOffsets.lowerBound(to)
        var offsets = breakOffsets[first..<last].map { $0 - from }
        let sliceStart = start + from
        if from < to, source.character(at: sliceStart) == 10, offsets.first != 0 {
            offsets.insert(0, at: 0)
        }
        return ApplePiece(source: source, start: sliceStart, length: to - from, id: id, breakOffsets: offsets)
    }
}

private struct AppleNewlineSummary: Sendable {
    let length: Int
    let breaks: Int
    let startsWithLF: Bool
    let endsWithCR: Bool

    static let empty = AppleNewlineSummary(length: 0, breaks: 0, startsWithLF: false, endsWithCR: false)

    static func + (lhs: AppleNewlineSummary, rhs: AppleNewlineSummary) -> AppleNewlineSummary {
        if lhs.length == 0 { return rhs }
        if rhs.length == 0 { return lhs }
        return AppleNewlineSummary(
            length: lhs.length + rhs.length,
            breaks: lhs.breaks + rhs.breaks - (lhs.endsWithCR && rhs.startsWithLF ? 1 : 0),
            startsWithLF: lhs.startsWithLF,
            endsWithCR: rhs.endsWithCR
        )
    }
}

private func merge(_ left: ApplePieceNode?, _ right: ApplePieceNode?) -> ApplePieceNode? {
    guard let left else { return right }
    guard let right else { return left }
    if left.priority <= right.priority {
        return ApplePieceNode(piece: left.piece, left: left.left, right: merge(left.right, right))
    }
    return ApplePieceNode(piece: right.piece, left: merge(left, right.left), right: right.right)
}

private func character(in node: ApplePieceNode, at offset: Int) -> unichar {
    let leftLength = node.left?.length ?? 0
    if offset < leftLength { return character(in: node.left!, at: offset) }
    if offset < leftLength + node.piece.length {
        return node.piece.source.character(at: node.piece.start + offset - leftLength)
    }
    return character(in: node.right!, at: offset - leftLength - node.piece.length)
}

private func appendRange(
    _ node: ApplePieceNode?,
    nodeStart: Int,
    requested: AppleTextRange,
    into output: inout String
) {
    guard let node, requested.start < requested.end,
          nodeStart < requested.end, nodeStart + node.length > requested.start else { return }
    appendRange(node.left, nodeStart: nodeStart, requested: requested, into: &output)
    let pieceStart = nodeStart + (node.left?.length ?? 0)
    let from = max(requested.start, pieceStart) - pieceStart
    let to = min(requested.end, pieceStart + node.piece.length) - pieceStart
    if from < to {
        output.append(node.piece.source.substring(with: NSRange(location: node.piece.start + from, length: to - from)))
    }
    appendRange(node.right, nodeStart: pieceStart + node.piece.length, requested: requested, into: &output)
}

private func enumeratePieces(_ node: ApplePieceNode?, _ body: (ApplePiece) -> Void) {
    guard let node else { return }
    enumeratePieces(node.left, body)
    body(node.piece)
    enumeratePieces(node.right, body)
}

private func effectiveBreaks(_ summary: AppleNewlineSummary, precedingCR: Bool) -> Int {
    summary.breaks - (precedingCR && summary.startsWithLF && summary.length > 0 ? 1 : 0)
}

private func breakCount(before length: Int, in root: ApplePieceNode?) -> Int {
    var node = root
    var remaining = length
    var breaks = 0
    var precedingCR = false
    while let current = node, remaining > 0 {
        let leftLength = current.left?.length ?? 0
        if remaining <= leftLength {
            node = current.left
            continue
        }
        let leftSummary = current.left?.summary ?? .empty
        breaks += effectiveBreaks(leftSummary, precedingCR: precedingCR)
        if leftSummary.length > 0 { precedingCR = leftSummary.endsWithCR }
        remaining -= leftLength

        let pieceLength = min(remaining, current.piece.length)
        if pieceLength > 0 {
            breaks += current.piece.breakOffsets.lowerBound(pieceLength) -
                (precedingCR && current.piece.summary.startsWithLF ? 1 : 0)
            precedingCR = current.piece.source.character(at: current.piece.start + pieceLength - 1) == 13
            remaining -= pieceLength
        }
        if remaining == 0 { break }
        node = current.right
    }
    return breaks
}

private func offsetAfterBreak(_ number: Int, in root: ApplePieceNode) -> Int {
    var node: ApplePieceNode? = root
    var wanted = number
    var precedingCR = false
    var nodeStart = 0
    while let current = node {
        let leftSummary = current.left?.summary ?? .empty
        let leftBreaks = effectiveBreaks(leftSummary, precedingCR: precedingCR)
        if wanted <= leftBreaks {
            node = current.left
            continue
        }
        wanted -= leftBreaks
        if leftSummary.length > 0 { precedingCR = leftSummary.endsWithCR }
        let pieceStart = nodeStart + (current.left?.length ?? 0)
        let skipLeadingLF = precedingCR && current.piece.summary.startsWithLF
        let pieceBreaks = current.piece.breakOffsets.count - (skipLeadingLF ? 1 : 0)
        if wanted <= pieceBreaks {
            let index = wanted - 1 + (skipLeadingLF ? 1 : 0)
            let offset = pieceStart + current.piece.breakOffsets[index]
            if character(in: root, at: offset) == 13,
               offset + 1 < root.length, character(in: root, at: offset + 1) == 10 {
                return offset + 2
            }
            return offset + 1
        }
        wanted -= pieceBreaks
        if current.piece.length > 0 { precedingCR = current.piece.summary.endsWithCR }
        nodeStart = pieceStart + current.piece.length
        node = current.right
    }
    preconditionFailure("Break outside document")
}

private extension Array where Element == Int {
    func lowerBound(_ value: Int) -> Int {
        var low = 0
        var high = count
        while low < high {
            let middle = (low + high) >> 1
            if self[middle] < value { low = middle + 1 } else { high = middle }
        }
        return low
    }
}

private func writeUTF8Bytes(_ string: String, to output: OutputStream, error: inout Error?) {
    let bytes = Array(string.utf8)
    var written = 0
    while written < bytes.count {
        let result = bytes.withUnsafeBufferPointer { buffer in
            output.write(buffer.baseAddress! + written, maxLength: bytes.count - written)
        }
        if result <= 0 {
            error = output.streamError ?? CocoaError(.fileWriteUnknown)
            return
        }
        written += result
    }
}

private func isHighSurrogate(_ value: unichar) -> Bool { (0xD800...0xDBFF).contains(value) }
private func isLowSurrogate(_ value: unichar) -> Bool { (0xDC00...0xDFFF).contains(value) }

private func mixed(_ value: UInt64) -> UInt64 {
    var result = value &+ 0x9E3779B97F4A7C15
    result = (result ^ (result >> 30)) &* 0xBF58476D1CE4E5B9
    result = (result ^ (result >> 27)) &* 0x94D049BB133111EB
    return result ^ (result >> 31)
}
