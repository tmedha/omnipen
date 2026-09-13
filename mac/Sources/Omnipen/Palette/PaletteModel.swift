import Combine
import Foundation

/// View state belonging to the palette alone, kept out of `AppState` because
/// nothing else in the app cares whether the colour row happens to be open.
@MainActor
final class PaletteModel: ObservableObject {
    @Published var isColorRowOpen = false
    @Published var isCollapsed = false
}

/// Commands the palette issues, passed in so the view needs no reference to the
/// overlay coordinator.
struct PaletteActions {
    let undo: () -> Void
    let clearAll: () -> Void
}
