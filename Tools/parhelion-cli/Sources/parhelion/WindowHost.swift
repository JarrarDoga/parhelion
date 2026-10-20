import ArgumentParser
import CSDL3
import Foundation
import ParhelionPreview

/// A window that shows the frames an app sends and sends input back.
///
/// SDL runs on the main thread. A reader thread receives frames from the app
/// and wakes the main thread with an SDL user event; the main thread sends
/// input to the app. The channel is safe to use this way because each
/// direction is used by one thread only.
final class WindowHost {
    private let window: OpaquePointer
    private let renderer: OpaquePointer
    private var texture: UnsafeMutablePointer<SDL_Texture>?
    private var textureSize = (width: 0, height: 0)
    private let wakeEvent: UInt32

    init(title: String, width: Int, height: Int) throws {
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
        wakeEvent = SDL_RegisterEvents(1)
    }

    deinit {
        if let texture { SDL_DestroyTexture(texture) }
        SDL_DestroyRenderer(renderer)
        SDL_DestroyWindow(window)
        SDL_Quit()
    }

    /// Shows frames and forwards input until the window closes or the app
    /// disconnects.
    func run(channel: PreviewChannel, zoom: Double, exitAfterFirstFrame: Bool) throws {
        let connection = Connection(channel: channel)
        let mailbox = FrameMailbox()
        let wakeEvent = wakeEvent
        let reader = Thread {
            while true {
                do {
                    guard let message = try connection.channel.receiveAppMessage() else { continue }
                    if case .frame(let frame) = message { mailbox.put(frame) }
                } catch {
                    mailbox.disconnect()
                }
                var event = SDL_Event()
                event.type = wakeEvent
                _ = SDL_PushEvent(&event)
                if mailbox.isDisconnected { return }
            }
        }
        reader.start()

        var event = SDL_Event()
        while true {
            if SDL_WaitEventTimeout(&event, 250) {
                if try handle(event, connection: connection, zoom: zoom) == false { break }
            }
            if let frame = mailbox.take() {
                debugLog("presenting a \(frame.width) × \(frame.height) frame")
                try present(frame)
                if exitAfterFirstFrame { break }
            }
            if mailbox.isDisconnected {
                print("The app disconnected.")
                return
            }
        }
        try? connection.channel.send(.close)
    }

    /// Handles one SDL event. Returns `false` when the window should close.
    private func handle(_ event: SDL_Event, connection: Connection, zoom: Double) throws -> Bool {
        switch event.type {
        case SDL_EVENT_MOUSE_BUTTON_DOWN.rawValue, SDL_EVENT_MOUSE_BUTTON_UP.rawValue:
            debugLog(
                "mouse button \(event.type) at \(event.button.x), \(event.button.y) which=\(event.button.which) time=\(event.button.timestamp)"
            )
        default:
            break
        }
        func point(_ x: Float, _ y: Float) -> (x: Double, y: Double) {
            (Double(x) / zoom, Double(y) / zoom)
        }
        switch event.type {
        case SDL_EVENT_QUIT.rawValue, SDL_EVENT_WINDOW_CLOSE_REQUESTED.rawValue:
            return false
        case SDL_EVENT_MOUSE_BUTTON_DOWN.rawValue where event.button.button == parhelion_button_left:
            let position = point(event.button.x, event.button.y)
            try connection.channel.send(.pointerDown(x: position.x, y: position.y))
        case SDL_EVENT_MOUSE_BUTTON_UP.rawValue where event.button.button == parhelion_button_left:
            let position = point(event.button.x, event.button.y)
            try connection.channel.send(.pointerUp(x: position.x, y: position.y))
        case SDL_EVENT_MOUSE_MOTION.rawValue
        where event.motion.state & parhelion_button_left_mask != 0:
            let position = point(event.motion.x, event.motion.y)
            try connection.channel.send(.pointerMoved(x: position.x, y: position.y))
        default:
            break
        }
        return true
    }

    private func present(_ frame: PreviewFrame) throws {
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
        _ = SDL_RenderTexture(renderer, texture, nil, nil)
        _ = SDL_RenderPresent(renderer)
    }
}

/// The channel to the app, shared by the main thread, which sends, and the
/// reader thread, which receives.
private final class Connection: @unchecked Sendable {
    let channel: PreviewChannel

    init(channel: PreviewChannel) {
        self.channel = channel
    }
}

/// The latest frame from the reader thread. Older frames that the main thread
/// has not shown yet are dropped.
private final class FrameMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var frame: PreviewFrame?
    private var disconnected = false

    func put(_ frame: PreviewFrame) {
        lock.withLock { self.frame = frame }
    }

    func take() -> PreviewFrame? {
        lock.withLock {
            defer { frame = nil }
            return frame
        }
    }

    func disconnect() {
        lock.withLock { disconnected = true }
    }

    var isDisconnected: Bool {
        lock.withLock { disconnected }
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
