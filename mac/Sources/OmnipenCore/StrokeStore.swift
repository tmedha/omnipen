import CoreGraphics
import Foundation

/// The ink on one canvas, plus its undo history.
///
/// History is an edit log rather than a stack of stroke arrays, because an eraser
/// swipe can remove several strokes at once. Undo has to restore a set of strokes
/// at their original depth, or an undone erase would bring ink back on top of
/// marks drawn after it.
public final class StrokeStore {

    /// A stroke plus the index it occupied, so undo can reinsert it in z-order.
    public struct Removal: Equatable, Sendable {
        public let index: Int
        public let stroke: Stroke
    }

    enum Edit: Equatable {
        case add(Stroke)
        case remove([Removal])
    }

    public private(set) var strokes: [Stroke] = []
    private var undoStack: [Edit] = []
    private var redoStack: [Edit] = []

    public init() {}

    public var isEmpty: Bool { strokes.isEmpty }
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public func commit(_ stroke: Stroke) {
        strokes.append(stroke)
        undoStack.append(.add(stroke))
        redoStack.removeAll()
    }

    /// Removes every stroke within `radius` of `point`, returning the ids removed
    /// so the caller can skip a repaint when the swipe hit nothing.
    @discardableResult
    public func erase(at point: CGPoint, radius: Double) -> [Stroke.ID] {
        var removals: [Removal] = []
        for (index, stroke) in strokes.enumerated() where stroke.hitTest(point, radius: radius) {
            removals.append(Removal(index: index, stroke: stroke))
        }
        guard !removals.isEmpty else { return [] }

        // Back to front, so earlier indices stay valid.
        for removal in removals.reversed() {
            strokes.remove(at: removal.index)
        }
        undoStack.append(.remove(removals))
        redoStack.removeAll()
        return removals.map(\.stroke.id)
    }

    @discardableResult
    public func clear() -> Bool {
        guard !strokes.isEmpty else { return false }
        let removals = strokes.enumerated().map { Removal(index: $0.offset, stroke: $0.element) }
        strokes.removeAll()
        undoStack.append(.remove(removals))
        redoStack.removeAll()
        return true
    }

    @discardableResult
    public func undo() -> Bool {
        guard let edit = undoStack.popLast() else { return false }
        apply(inverseOf: edit)
        redoStack.append(edit)
        return true
    }

    @discardableResult
    public func redo() -> Bool {
        guard let edit = redoStack.popLast() else { return false }
        apply(edit)
        undoStack.append(edit)
        return true
    }

    /// Forgets the ink and the history both.
    public func reset() {
        strokes.removeAll()
        undoStack.removeAll()
        redoStack.removeAll()
    }

    private func apply(_ edit: Edit) {
        switch edit {
        case .add(let stroke):
            strokes.append(stroke)
        case .remove(let removals):
            for removal in removals.reversed() where removal.index < strokes.count {
                strokes.remove(at: removal.index)
            }
        }
    }

    private func apply(inverseOf edit: Edit) {
        switch edit {
        case .add(let stroke):
            if let index = strokes.lastIndex(where: { $0.id == stroke.id }) {
                strokes.remove(at: index)
            }
        case .remove(let removals):
            // Ascending, so each insertion lands at the index it originally held.
            for removal in removals.sorted(by: { $0.index < $1.index }) {
                strokes.insert(removal.stroke, at: min(removal.index, strokes.count))
            }
        }
    }
}
