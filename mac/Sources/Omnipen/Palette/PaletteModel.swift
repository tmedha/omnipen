import Combine
import Foundation

/// Kept out of `AppState` because nothing else cares whether the colour row is
/// open.
@MainActor
final class PaletteModel: ObservableObject {
    @Published var isColorRowOpen = false
    @Published var isShapeRowOpen = false
    @Published var isCollapsed = false
}

struct PaletteActions {
    let undo: () -> Void
    let clearAll: () -> Void
}
