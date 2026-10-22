import ArgumentParser
import CSDL3
import Foundation
import ParhelionPreview
import ParhelionRender
import ParhelionTooling

/// The preview window: it shows frames and turns mouse events into input
/// messages. SDL runs on the main thread only.
///
/// Showing a frame has two steps, so that ``FrameLoop`` can time them:
/// ``upload(_:)`` copies the pixels into the window's texture, and
/// ``present()`` draws the texture and, with vsync, waits for the display
/// to refresh.
final class WindowHost {
    enum Event {
        /// The user closed the window.
        case close
        /// Input to forward to the app.
        case input(HostMessage)
        /// The window needs drawing again, as after it was uncovered.
        case redraw
    }

    private let window: OpaquePointer
    private let renderer: OpaquePointer
    private var texture: UnsafeMutablePointer<SDL_Texture>?
    private var textureSize = (width: 0, height: 0)
    private let zoom: Double
    /// The phone drawn around the screen, if any, and its texture.
    private let bezel: DeviceBezel?
    private var bezelTexture: UnsafeMutablePointer<SDL_Texture>?
    /// The frame's corners outside the phone, made once for the frame width
    /// they fit, with a buffer each to fade a frame's corner in.
    private var cornerFades: (width: Int, fades: [CornerFade])?
    private let wakeEventType: UInt32

    /// Whether SDL accepted vsync, so that presenting waits for the display.
    let hasVSync: Bool
    /// The refresh period of the display the window is on, in nanoseconds.
    private(set) var refreshPeriod = FramePacer.defaultRefreshPeriod

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
                // With a bezel, the window is transparent outside the phone's
                // rounded corners, where the compositor supports it.
                parhelion_window_high_pixel_density
                    | (bezel == nil ? 0 : parhelion_window_transparent)
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
        // Present in step with the display. Drivers may refuse; then the
        // frame loop waits for each refresh itself.
        hasVSync = SDL_SetRenderVSync(renderer, 1)
        wakeEventType = SDL_RegisterEvents(1)
        // Deliver typed text, after keyboard layouts and input methods.
        _ = SDL_StartTextInput(window)
        if let bezel {
            bezelTexture = try Self.makeTexture(renderer, from: bezel.image(scale: scale))
        }
        readRefreshPeriod()
        let rendererName = SDL_GetRendererName(renderer).map { String(cString: $0) } ?? "unknown"
        debugLog(
            String(
                format: "renderer %@, vsync %@, refresh %.3f Hz", rendererName,
                hasVSync ? "on" : "refused", 1e9 / Double(refreshPeriod)))
    }

    deinit {
        if let texture { SDL_DestroyTexture(texture) }
        if let bezelTexture { SDL_DestroyTexture(bezelTexture) }
        SDL_DestroyRenderer(renderer)
        SDL_DestroyWindow(window)
        SDL_Quit()
    }

    /// A function other threads can call to wake ``events(waitingUpTo:)``.
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

    /// Reads the refresh rate of the display the window is on.
    private func readRefreshPeriod() {
        let display = SDL_GetDisplayForWindow(window)
        guard display != 0, let mode = SDL_GetCurrentDisplayMode(display) else { return }
        let period = FramePacer.refreshPeriod(
            numerator: mode.pointee.refresh_rate_numerator,
            denominator: mode.pointee.refresh_rate_denominator,
            rate: mode.pointee.refresh_rate)
        if period != refreshPeriod {
            refreshPeriod = period
            debugLog(String(format: "display refresh %.3f Hz", 1e9 / Double(period)))
        }
    }

    /// The events that matter to the preview: waits up to `timeout` seconds
    /// for the first event, or until woken, then takes every event already
    /// queued without waiting. A timeout of 0 does not wait.
    func events(waitingUpTo timeout: Double) -> [Event] {
        var result: [Event] = []
        var event = SDL_Event()
        let milliseconds = Int32(min(max(timeout, 0) * 1000, Double(Int32.max)).rounded(.up))
        var available =
            milliseconds > 0 ? SDL_WaitEventTimeout(&event, milliseconds) : SDL_PollEvent(&event)
        while available {
            if let translated = translate(event) { result.append(translated) }
            available = SDL_PollEvent(&event)
        }
        return result
    }

    /// The preview's meaning of an SDL event, if it has one.
    private func translate(_ event: SDL_Event) -> Event? {
        func point(_ x: Float, _ y: Float) -> (x: Double, y: Double) {
            screenPoint(windowX: Double(x), windowY: Double(y), zoom: zoom, bezel: bezel)
        }
        switch event.type {
        case SDL_EVENT_QUIT.rawValue, SDL_EVENT_WINDOW_CLOSE_REQUESTED.rawValue:
            return .close
        case SDL_EVENT_WINDOW_EXPOSED.rawValue:
            return .redraw
        case SDL_EVENT_WINDOW_DISPLAY_CHANGED.rawValue,
            SDL_EVENT_DISPLAY_CURRENT_MODE_CHANGED.rawValue:
            readRefreshPeriod()
            return .redraw
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

    /// Copies a frame's pixels into the window's texture, from the frame's
    /// own array or straight from its shared-memory slot. Only the frame's
    /// damaged rectangle is copied. Returns `false` for a frame without
    /// pixels.
    @discardableResult
    func upload(_ frame: ReceivedFrame) throws -> Bool {
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
            _ = SDL_SetTextureBlendMode(texture, SDL_BLENDMODE_BLEND)
            textureSize = (frame.width, frame.height)
        }
        let damage = frame.clampedDamage
        prepareCornerFades(frameWidth: frame.width)
        return frame.withPixels { pixels in
            var rect = SDL_Rect(
                x: Int32(damage.x), y: Int32(damage.y), w: Int32(damage.width),
                h: Int32(damage.height))
            let start = pixels.baseAddress! + (damage.y * frame.width + damage.x) * 4
            // SDL_UpdateTexture straight from the slot measured faster than
            // SDL_LockTexture with the OpenGL renderer, which stages locked
            // pixels in a buffer of its own and copies them again on unlock.
            _ = SDL_UpdateTexture(texture, &rect, start, Int32(frame.width * 4))
            // The screen's square corners reach past the phone's rounded
            // body, where the window is transparent: fade them out.
            guard cornerFades != nil else { return }
            for index in cornerFades!.fades.indices
            where cornerFades!.fades[index].intersects(damage) {
                cornerFades!.fades[index].fade(from: pixels, frameWidth: frame.width)
                cornerFades!.fades[index].upload(to: texture)
            }
        }
    }

    /// Makes the corner fades for frames `frameWidth` pixels wide, the first
    /// time a frame of that width arrives.
    private func prepareCornerFades(frameWidth: Int) {
        guard let bezel, cornerFades?.width != frameWidth else { return }
        let scale = Double(frameWidth) / bezel.screenWidth
        cornerFades = (frameWidth, bezel.frameMasks(scale: scale).map(CornerFade.init))
    }

    /// Draws the texture, scaled to fill the window or, with a bezel, the
    /// screen inside it, and shows it. With vsync, this waits until the
    /// display refreshes.
    func present() {
        _ = SDL_SetRenderDrawColor(renderer, 0, 0, 0, 0)
        _ = SDL_RenderClear(renderer)
        if let texture {
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
        }
        _ = SDL_RenderPresent(renderer)
    }
}

/// One corner of the frame that reaches past the phone's rounded body, and
/// a buffer it is faded in. The buffer is made once and reused for every
/// frame.
struct CornerFade {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
    /// The pixels that are not fully opaque, by their index in the corner,
    /// and their opacity.
    let faded: [(index: Int, alpha: UInt8)]
    private var buffer: [UInt8]

    init(_ mask: DeviceBezel.FrameMask) {
        x = mask.x
        y = mask.y
        width = mask.width
        height = mask.height
        faded = mask.faded
        buffer = [UInt8](repeating: 0, count: mask.width * mask.height * 4)
    }

    /// Whether the corner overlaps a rectangle of the frame.
    func intersects(_ rect: PixelRect) -> Bool {
        x < rect.x + rect.width && rect.x < x + width && y < rect.y + rect.height
            && rect.y < y + height
    }

    /// Copies the corner out of a frame and fades its pixels.
    mutating func fade(from pixels: UnsafeRawBufferPointer, frameWidth: Int) {
        let rowBytes = width * 4
        let (x, y, height, faded) = (x, y, height, faded)
        buffer.withUnsafeMutableBytes { corner in
            for row in 0..<height {
                let source = pixels.baseAddress! + ((y + row) * frameWidth + x) * 4
                (corner.baseAddress! + row * rowBytes).copyMemory(from: source, byteCount: rowBytes)
            }
            for pixel in faded {
                let alpha = pixel.index * 4 + 3
                corner[alpha] = UInt8(UInt16(corner[alpha]) * UInt16(pixel.alpha) / 255)
            }
        }
    }

    /// Copies the faded corner into the texture.
    func upload(to texture: UnsafeMutablePointer<SDL_Texture>?) {
        var rect = SDL_Rect(x: Int32(x), y: Int32(y), w: Int32(width), h: Int32(height))
        buffer.withUnsafeBytes { bytes in
            _ = SDL_UpdateTexture(texture, &rect, bytes.baseAddress, Int32(width * 4))
        }
    }
}

/// Prints a trace line to standard error when `PARHELION_DEBUG` is set.
func debugLog(_ message: @autoclosure () -> String) {
    guard isDebugLogging else { return }
    FileHandle.standardError.write(Data("parhelion: \(message())\n".utf8))
}

/// Whether `PARHELION_DEBUG` is set, read once: the frame loop logs every
/// present.
let isDebugLogging = ProcessInfo.processInfo.environment["PARHELION_DEBUG"] != nil

struct SDLError: Error, CustomStringConvertible {
    let description: String

    static func current(_ action: String) -> SDLError {
        SDLError(description: "Could not \(action): \(String(cString: SDL_GetError()))")
    }
}
