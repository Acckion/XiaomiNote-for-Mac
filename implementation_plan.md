# Implementation Plan - Customizable Toolbar (NetNewsWire Style)

[Overview]
Implement a fully customizable, native macOS toolbar for MiNote by strictly following the architectural patterns of NetNewsWire (NNW). This involves adhering to `NSToolbarDelegate` directly within `MainWindowController`, using a robust identifier system, and leveraging a custom `NSToolbarItem` subclass (`MiNoteToolbarItem`) that mirrors NNW's `RSToolbarItem` to handle responder-chain validation correctly. This change will replace any placeholder `ToolbarManager` logic with a production-ready, AppKit-native implementation that supports user customization, persistence, and multifaceted validation (e.g., enabling "Bold" only when editing).

[Types]
- `MiNoteToolbarItem`: A new class inheriting from `NSToolbarItem` that mirrors `RSToolbarItem` logic for validating against the responder chain.
- `NSToolbarItem.Identifier` extension: Comprehensive static constants for all toolbar items (e.g., `.newNote`, `.bold`, `.search`, `.onlineStatus`), matching the granularity of NNW.

[Files]
- `Sources/MiNoteLibrary/Window/MiNoteToolbarItem.swift`: New file. Contains the `MiNoteToolbarItem` class implementation.
- `Sources/MiNoteLibrary/Window/MainWindowController+Toolbar.swift`: New file. Contains the `NSToolbarDelegate` extension for `MainWindowController` to keep the main file clean (similar to how NNW separates functionality, though NNW puts it in main file, separating it is cleaner for MiNote's structure but I will stick to extending `MainWindowController`).
- `Sources/MiNoteLibrary/Window/MainWindowController.swift`: Modified. Will adopt `NSToolbarDelegate` conformance (via extension), initialize the toolbar with `allowsUserCustomization = true`, and remove any legacy `ToolbarContext` usage if it conflicts with the native delegation model (or bridge them).
- `Sources/MiNoteLibrary/Window/ToolbarContext.swift`: Modified/Deprecated. If `ToolbarContext` was a placeholder for state, its logic might need to be shifted to the `ViewModel` or `MainWindowController` to drive the *validation* of toolbar items, rather than determining *what* items are in the array. Native toolbars work by having *all* allowed items and enabling/disabling them.

[Functions]
- `MiNoteToolbarItem.validate()`: Overrides standard validation to check the responder chain for `NSUserInterfaceValidations` conformance.
- `MainWindowController.validateUserInterfaceItem(_:)`: Implements `NSUserInterfaceValidations` to determine enable/disable state for specific actions (replacing `ToolbarContext`'s boolean flags for enablement).
- `MainWindowController.toolbar(_:itemForItemIdentifier:willBeInsertedIntoToolbar:)`: The factory method for creating toolbar items.
- `MainWindowController.toolbarDefaultItemIdentifiers(_:)`: Returns the default set.
- `MainWindowController.toolbarAllowedItemIdentifiers(_:)`: Returns the complete set of customizable items.
- `MainWindowController.setupToolbar()`: Initializes and attaches the toolbar.

[Classes]
- `MiNoteToolbarItem`: Subclass of `NSToolbarItem`. Key method: `validate()`.
- `MainWindowController`: Will now act as the central hub for toolbar delegation and action handling (or dispatching actions to the `HostingController`'s root view).

[Dependencies]
- No external dependencies. Uses standard `AppKit`.

[Testing]
- Manual testing of toolbar customization (drag and drop).
- Verification that toolbar configuration persists after app restart (`autosavesConfiguration`).
- Verification that items enable/disable correctly when switching between viewing and editing modes (responder chain validation).

[Implementation Order]
1. Create `MiNoteToolbarItem.swift` to handle validation logic.
2. Define `NSToolbarItem.Identifier` constants for all desired tools (New Note, Formats, Search, etc.).
3. modify `MainWindowController` to implement `NSToolbarDelegate` methods (`defaultItemIdentifiers`, `allowedItemIdentifiers`, `itemForItemIdentifier`).
4. Implement `NSUserInterfaceValidations` in `MainWindowController` (or ensure it delegates to the active SwiftUI view via specific actions) to handle item state (e.g., Bold is only enabled when editor is focused).
5. Hook up the toolbar in `MainWindowController.windowDidLoad`.
6. Remove old/placeholder toolbar code.
