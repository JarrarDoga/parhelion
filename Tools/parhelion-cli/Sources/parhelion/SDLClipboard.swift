import CSDL3
import Foundation
import ParhelionTooling

/// The system clipboard through SDL3. Call it on the thread that runs the
/// window, which is where ``ClipboardHook`` runs.
struct SDLClipboard: SystemClipboard {
    func text() -> String? {
        guard SDL_HasClipboardText(), let pointer = SDL_GetClipboardText() else { return nil }
        defer { SDL_free(pointer) }
        let text = String(cString: pointer)
        return text.isEmpty ? nil : text
    }

    func setText(_ text: String) {
        _ = SDL_SetClipboardText(text)
    }
}
