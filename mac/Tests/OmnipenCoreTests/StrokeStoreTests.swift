import CoreGraphics
import Testing

@testable import OmnipenCore

private func makeStroke(_ points: [CGPoint], width: Double = 4) -> Stroke {
    Stroke(
        tool: .pen,
        color: InkColor(red: 1, green: 0, blue: 0),
        width: width,
        points: points
    )
}

@Suite("StrokeStore")
struct StrokeStoreTests {

    @Test("commit appends and enables undo")
    func commitAppends() {
        let store = StrokeStore()
        #expect(store.isEmpty)
        #expect(!store.canUndo)

        store.commit(makeStroke([CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)]))

        #expect(store.strokes.count == 1)
        #expect(store.canUndo)
        #expect(!store.canRedo)
    }

    @Test("undo and redo round-trip a commit")
    func undoRedoRoundTrip() {
        let store = StrokeStore()
        let stroke = makeStroke([CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)])
        store.commit(stroke)

        #expect(store.undo())
        #expect(store.isEmpty)
        #expect(store.canRedo)

        #expect(store.redo())
        #expect(store.strokes.map(\.id) == [stroke.id])
    }

    @Test("a new commit discards the redo branch")
    func commitClearsRedo() {
        let store = StrokeStore()
        store.commit(makeStroke([CGPoint(x: 0, y: 0)]))
        store.undo()
        #expect(store.canRedo)

        store.commit(makeStroke([CGPoint(x: 5, y: 5)]))
        #expect(!store.canRedo)
    }

    @Test("erase removes only strokes within the radius")
    func eraseHitsNearbyStrokes() {
        let store = StrokeStore()
        let near = makeStroke([CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 0)])
        let far = makeStroke([CGPoint(x: 500, y: 500), CGPoint(x: 520, y: 500)])
        store.commit(near)
        store.commit(far)

        let removed = store.erase(at: CGPoint(x: 10, y: 4), radius: 10)

        #expect(removed == [near.id])
        #expect(store.strokes.map(\.id) == [far.id])
    }

    @Test("erase that hits nothing does not enter the history")
    func emptyEraseIsNotAnEdit() {
        let store = StrokeStore()
        store.commit(makeStroke([CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 0)]))
        store.undo()
        #expect(store.canRedo)

        let removed = store.erase(at: CGPoint(x: 9_000, y: 9_000), radius: 10)

        #expect(removed.isEmpty)
        // The redo branch survives, proving no edit was recorded.
        #expect(store.canRedo)
    }

    @Test("undoing an erase restores strokes at their original depth")
    func undoEraseRestoresZOrder() {
        let store = StrokeStore()
        let bottom = makeStroke([CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 0)])
        let middle = makeStroke([CGPoint(x: 0, y: 2), CGPoint(x: 20, y: 2)])
        let top = makeStroke([CGPoint(x: 400, y: 400), CGPoint(x: 420, y: 400)])
        store.commit(bottom)
        store.commit(middle)
        store.commit(top)

        // Wipes the two overlapping strokes, leaving only `top`.
        store.erase(at: CGPoint(x: 10, y: 1), radius: 6)
        #expect(store.strokes.map(\.id) == [top.id])

        #expect(store.undo())
        #expect(store.strokes.map(\.id) == [bottom.id, middle.id, top.id])
    }

    @Test("undoing a clear restores everything in order")
    func undoClearRestoresAll() {
        let store = StrokeStore()
        let ids = (0..<5).map { index -> Stroke in
            makeStroke([CGPoint(x: Double(index) * 50, y: 0)])
        }
        ids.forEach(store.commit)

        #expect(store.clear())
        #expect(store.isEmpty)

        #expect(store.undo())
        #expect(store.strokes.map(\.id) == ids.map(\.id))
    }

    @Test("clearing an empty store is not an edit")
    func clearEmptyIsNoop() {
        let store = StrokeStore()
        #expect(!store.clear())
        #expect(!store.canUndo)
    }

    @Test("undo and redo bottom out instead of misbehaving")
    func historyBoundaries() {
        let store = StrokeStore()
        #expect(!store.undo())
        #expect(!store.redo())

        store.commit(makeStroke([CGPoint(x: 1, y: 1)]))
        #expect(store.undo())
        #expect(!store.undo())
        #expect(store.redo())
        #expect(!store.redo())
    }

    @Test("reset drops ink and history together")
    func resetClearsHistory() {
        let store = StrokeStore()
        store.commit(makeStroke([CGPoint(x: 0, y: 0)]))
        store.reset()

        #expect(store.isEmpty)
        #expect(!store.canUndo)
        #expect(!store.canRedo)
    }
}
