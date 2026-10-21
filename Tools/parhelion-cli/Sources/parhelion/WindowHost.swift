import ArgumentParser
import CSDL3
import Foundation
import ParhelionPreview
import ParhelionRender
import ParhelionTooling

/// The preview window: it shows frames and turns mouse events into input
/// messages. SDL runs on the main thread only.
final class WindowHost {
    enum Event {
        /// The user closed the window.
        case close
        /// Input to forward to the app.
        case input(HostMessage)
    }

    private let window: OpaquePointer
    private let renderer: OpaquePointer
    private var texture: UnsafeMutablePointer<SDL_Texture>?
    private var textureSize = (width: 0, height: 0)
    private let zoom: Double
    /// The phone drawn around the screen, if any, and its texture.
    private let bezel: DeviceBezel?
    private var bezelTexture: UnsafeMutablePointer<SDL_Texture>?
    private let wakeEventType: UInt32

    /// How far one mouse wheel step scrolls, in points.
    static let pointsPerWheelStep = 40.0

    /// Opens a window `zoom` times the size of the screen, or of the screen
    /// and the bezel around it. The bezel is drawn at `scale` pixels per
    /// point, like the app's frames.
    init(
        title: String, screenWidth: Double, screenHeight: Double, zoom: Double,
        bezel: DeviceBezel?, scale: Double
    ) throws {
        let width = Int(((bezel?.width ?? screenWidth) * zoom).rounded())
        let height = Int(((bezel?.height ?? screenHeight) * zoom).rounded())
        // Deliver the click that focuses the window, so the first click on
        // an unfocused preview presses a button like every later click.
        _ = SDL_SetHint(SDL_HINT_MOUSE_FOCUS_CLICKTHROUGH, "1")
        guard SDL_Init(parhelion_init_video) else { throw SDLError.current("initialize video") }
        guard
            let window = SDL_CreateWindow(
                title,
                Int32(width),
                Int32(height),
                parhelion_window_high_pixel_density
            )
        else {
            SDL_Quit()
            throw SDLError.current("create the window")
        }
        guard let renderer = SDL_CreateRenderer(window, nil) else {
            SDL_DestroyWindow(window)
            SDL_Quit()
            throw SDLError.current("create a renderer")
        }
        self.window = window
        self.renderer = renderer
        self.zoom = zoom
        self.bezel = bezel
        wakeEventType = SDL_RegisterEvents(1)
        // Deliver typed text, after keyboard layouts and input methods.
        _ = SDL_StartTextInput(window)
        if let bezel {
            bezelTexture = try Self.makeTexture(renderer, from: bezel.image(scale: scale))
        }
    }

    deinit {
        if let texture { SDL_DestroyTexture(texture) }
        if let bezelTexture { SDL_DestroyTexture(bezelTexture) }
        SDL_DestroyRenderer(renderer)
        SDL_DestroyWindow(window)
        SDL_Quit()
    }

    /// A function other threads can call to wake ``nextEvent(timeout:)``.
    var waker: @Sendable () -> Void {
        let type = wakeEventType
        return {
            var event = SDL_Event()
            event.type = type
            _ = SDL_PushEvent(&event)
        }
    }

    func setTitle(_ title: String) {
        _ = SDL_SetWindowTitle(window, title)
    }

    /// Waits up to `timeout` seconds for an event that matters to the
    /// preview. Returns `nil` on timeout or when woken.
    func nextEvent(timeout: Double) -> Event? {
        var event = SDL_Event()
        guard SDL_WaitEventTimeout(&event, Int32(timeout * 1000)) else { return nil }
        func point(_ x: Float, _ y: Float) -> (x: Double, y: Double) {
            let x = Double(x) / zoom
            let y = Double(y) / zoom
            return bezel?.screenPoint(x: x, y: y) ?? (x, y)
        }
        switch event.type {
        case SDL_EVENT_QUIT.rawValue, SDL_EVENT_WINDOW_CLOSE_REQUESTED.rawValue:
            return .close
        case SDL_EVENT_MOUSE_BUTTON_DOWN.rawValue where event.button.button == parhelion_button_left:
            let position = point(event.button.x, event.button.y)
            debugLog("mouse down at \(position)")
            return .input(.pointerDown(x: position.x, y: position.y))
        case SDL_EVENT_MOUSE_BUTTON_UP.rawValue where event.button.button == parhelion_button_left:
            let position = point(event.button.x, event.button.y)
            debugLog("mouse up at \(position)")
            return .input(.pointerUp(x: position.x, y: position.y))
        case SDL_EVENT_MOUSE_MOTION.rawValue
        where event.motion.state & parhelion_button_left_mask != 0:
            let position = point(event.motion.x, event.motion.y)
            return .input(.pointerMoved(x: position.x, y: position.y))
        case SDL_EVENT_TEXT_INPUT.rawValue:
            guard let text = event.text.text else { return nil }
            return .input(.text(String(cString: text)))
        case SDL_EVENT_KEY_DOWN.rawValue:
            return Self.keyName(event.key.key, shift: event.key.mod & parhelion_keymod_shift != 0)
                .map { .input(.key($0)) }
        case SDL_EVENT_MOUSE_WHEEL.rawValue:
            var dx = Double(event.wheel.x)
            var dy = Double(event.wheel.y)
            if event.wheel.direction == SDL_MOUSEWHEEL_FLIPPED {
                dx = -dx
                dy = -dy
            }
            let position = point(event.wheel.mouse_x, event.wheel.mouse_y)
            // SDL's y points away from the user, and scrolling away moves
            // toward the start of the content. Trackpads report fractions of
            // a step, which keeps their scrolling smooth.
            return .input(
                .scroll(
                    dx: dx * Self.pointsPerWheelStep,
                    dy: -dy * Self.pointsPerWheelStep,
                    x: position.x,
                    y: position.y
                )
            )
        default:
            return nil
        }
    }

    /// The name of an editing key, as `ViewHost.Key` spells it, or `nil` for
    /// keys that only type text.
    static func keyName(_ key: SDL_Keycode, shift: Bool) -> String? {
        switch key {
        case SDLK_BACKSPACE: "backspace"
        case SDLK_DELETE: "delete"
        case SDLK_LEFT: "left"
        case SDLK_RIGHT: "right"
        case SDLK_HOME: "home"
        case SDLK_END: "end"
        case SDLK_TAB: shift ? "backTab" : "tab"
        case SDLK_RETURN, SDLK_KP_ENTER: "return"
        case SDLK_ESCAPE: "escape"
        default: nil
        }
    }

    /// Creates a static texture holding a canvas's pixels.
    private static func makeTexture(
        _ renderer: OpaquePointer, from canvas: Canvas
    ) throws -> UnsafeMutablePointer<SDL_Texture> {
        guard
            let texture = SDL_CreateTexture(
                renderer, SDL_PIXELFORMAT_ABGR8888, SDL_TEXTUREACCESS_STATIC,
                Int32(canvas.width), Int32(canvas.height))
        else { throw SDLError.current("create a texture") }
        _ = SDL_SetTextureScaleMode(texture, SDL_SCALEMODE_LINEAR)
        _ = SDL_SetTextureBlendMode(texture, SDL_BLENDMODE_BLEND)
        canvas.pixels.withUnsafeBytes { bytes in
            _ = SDL_UpdateTexture(texture, nil, bytes.baseAddress, Int32(canvas.width * 4))
        }
        return texture
    }

    /// Shows a frame, scaled to fill the window or, with a bezel, the
    /// screen inside it.
    func present(_ frame: PreviewFrame) throws {
        let clock = ContinuousClock()
        let start = clock.now
        defer {
            debugLog("presented a \(frame.width) × \(frame.height) frame in \(clock.now - start)")
        }
        if texture == nil || textureSize != (frame.width, frame.height) {
            if let texture { SDL_DestroyTexture(texture) }
            // ABGR8888 is a packed 32-bit format; on little-endian machines its
            // bytes are in R, G, B, A order, the order Parhelion's frames use.
            texture = SDL_CreateTexture(
                renderer,
                SDL_PIXELFORMAT_ABGR8888,
                SDL_TEXTUREACCESS_STREAMING,
                Int32(frame.width),
                Int32(frame.height)
            )
            guard let texture else { throw SDLError.current("create a texture") }
            _ = SDL_SetTextureScaleMode(texture, SDL_SCALEMODE_LINEAR)
            textureSize = (frame.width, frame.height)
        }
        frame.pixels.withUnsafeBytes { bytes in
            _ = SDL_UpdateTexture(texture, nil, bytes.baseAddress, Int32(frame.width * 4))
        }
        _ = SDL_RenderClear(renderer)
        if let bezel, let bezelTexture {
            var outputWidth: Int32 = 0
            var outputHeight: Int32 = 0
            _ = SDL_GetCurrentRenderOutputSize(renderer, &outputWidth, &outputHeight)
            let scaleX = Double(outputWidth) / bezel.width
            let scaleY = Double(outputHeight) / bezel.height
            var screen = SDL_FRect(
                x: Float(DeviceBezel.margin * scaleX),
                y: Float(DeviceBezel.margin * scaleY),
                w: Float(bezel.screenWidth * scaleX),
                h: Float(bezel.screenHeight * scaleY)
            )
            _ = SDL_RenderTexture(renderer, texture, nil, &screen)
            _ = SDL_RenderTexture(renderer, bezelTexture, nil, nil)
        } else {
            _ = SDL_RenderTexture(renderer, texture, nil, nil)
        }
        _ = SDL_RenderPresent(renderer)
    }
}

/// Prints a trace line to standard error when `PARHELION_DEBUG` is set.
func debugLog(_ message: @autoclosure () -> String) {
    guard ProcessInfo.processInfo.environment["PARHELION_DEBUG"] != nil else { return }
    FileHandle.standardError.write(Data("parhelion: \(message())\n".utf8))
}

struct SDLError: Error, CustomStringConvertible {
    let description: String

    static func current(_ action: String) -> SDLError {
        SDLError(description: "Could not \(action): \(String(cString: SDL_GetError()))")
    }
}
