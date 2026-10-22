#if canImport(Glibc)
import Dispatch
import Glibc

/// Memory shared between an app and its window host, divided into equal
/// slots that each hold one frame.
///
/// The app creates the memory in an anonymous file, draws frames into free
/// slots, and passes the file's descriptor to the host once, with
/// ``AppMessage/sharedMemory(_:)``. The host maps the same file and reads
/// each slot that a ``AppMessage/frameUpdate(_:)`` names, so a frame crosses
/// between the processes without going through the socket.
public final class SharedFrameBuffer: @unchecked Sendable {
    public enum SharedMemoryError: Error, Equatable {
        /// Creating, sizing, or mapping the file failed.
        case failed(errno: Int32)
        /// The file is smaller than the slots it is said to hold.
        case tooSmall
    }

    /// The descriptor of the shared file. The buffer closes it.
    public let descriptor: Int32
    public let slotCount: Int
    public let slotSize: Int
    private let base: UnsafeMutableRawPointer
    private let length: Int

    /// The message that tells the other process about this memory.
    public var announcement: PreviewSharedMemory {
        PreviewSharedMemory(descriptor: descriptor, slotCount: slotCount, slotSize: slotSize)
    }

    /// Creates writable memory in a new anonymous file, for the app.
    public static func create(slotCount: Int, slotSize: Int) throws -> SharedFrameBuffer {
        let length = slotCount * slotSize
        guard length > 0 else { throw SharedMemoryError.tooSmall }
        let file = try makeAnonymousFile()
        guard ftruncate(file, off_t(length)) == 0 else {
            let error = errno
            _ = Glibc.close(file)
            throw SharedMemoryError.failed(errno: error)
        }
        return try SharedFrameBuffer(
            descriptor: file, slotCount: slotCount, slotSize: slotSize,
            protection: PROT_READ | PROT_WRITE)
    }

    /// Maps memory that the other process announced, read-only, for the
    /// host. The buffer takes ownership of the descriptor, and closes it
    /// even if mapping fails.
    public convenience init(mapping memory: PreviewSharedMemory) throws {
        var status = stat()
        guard fstat(memory.descriptor, &status) == 0 else {
            let error = errno
            _ = Glibc.close(memory.descriptor)
            throw SharedMemoryError.failed(errno: error)
        }
        guard memory.slotCount > 0, memory.slotSize > 0,
            Int(status.st_size) >= memory.slotCount * memory.slotSize
        else {
            _ = Glibc.close(memory.descriptor)
            throw SharedMemoryError.tooSmall
        }
        try self.init(
            descriptor: memory.descriptor, slotCount: memory.slotCount,
            slotSize: memory.slotSize, protection: PROT_READ)
    }

    private init(descriptor: Int32, slotCount: Int, slotSize: Int, protection: Int32) throws {
        length = slotCount * slotSize
        guard let mapped = mmap(nil, length, protection, MAP_SHARED, descriptor, 0),
            mapped != UnsafeMutableRawPointer(bitPattern: -1)
        else {
            let error = errno
            _ = Glibc.close(descriptor)
            throw SharedMemoryError.failed(errno: error)
        }
        self.descriptor = descriptor
        self.slotCount = slotCount
        self.slotSize = slotSize
        base = mapped
    }

    deinit {
        _ = munmap(base, length)
        _ = Glibc.close(descriptor)
    }

    /// The bytes of a slot. Only the app writes, and only to slots it has
    /// not handed to the host.
    public func slot(_ index: Int) -> UnsafeMutableRawBufferPointer {
        precondition(index >= 0 && index < slotCount, "No slot \(index)")
        return UnsafeMutableRawBufferPointer(start: base + index * slotSize, count: slotSize)
    }

    /// Copies a frame's pixels into a slot.
    ///
    /// One core copies a 5.4 MB frame in about 0.3 ms, limited by its own
    /// memory bandwidth, so a large frame is copied in eight parts at once,
    /// which takes about half as long.
    public func write(_ pixels: [UInt8], toSlot index: Int) {
        precondition(pixels.count <= slotSize, "A frame does not fit in a slot")
        let destination = Int(bitPattern: slot(index).baseAddress!)
        pixels.withUnsafeBytes { buffer in
            let source = Int(bitPattern: buffer.baseAddress!)
            let count = buffer.count
            let parts = count >= Self.parallelCopyThreshold ? 8 : 1
            // Parts end on cache-line boundaries.
            let partSize = (count / parts + 63) & ~63
            DispatchQueue.concurrentPerform(iterations: parts) { part in
                let start = part * partSize
                let length = min(partSize, count - start)
                guard length > 0 else { return }
                UnsafeMutableRawPointer(bitPattern: destination + start)!.copyMemory(
                    from: UnsafeRawPointer(bitPattern: source + start)!, byteCount: length)
            }
        }
    }

    /// The frame size from which ``write(_:toSlot:)`` copies in parallel.
    static let parallelCopyThreshold = 1 << 20

    /// An anonymous file in memory: `memfd_create` where the C library has
    /// it, or else a POSIX shared memory object that is unlinked at once.
    private static func makeAnonymousFile() throws -> Int32 {
        // Swift's Glibc module does not import memfd_create, a GNU
        // extension, so it is looked up at run time.
        typealias MemfdCreate = @convention(c) (UnsafePointer<CChar>, UInt32) -> Int32
        if let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: 0), "memfd_create") {
            let memfdCreate = unsafeBitCast(symbol, to: MemfdCreate.self)
            let closeOnExec: UInt32 = 1  // MFD_CLOEXEC
            let file = memfdCreate("parhelion-frames", closeOnExec)
            if file >= 0 { return file }
        }
        let name = "/parhelion-frames-\(getpid())-\(UInt32.random(in: 0...UInt32.max))"
        let file = shm_open(name, O_RDWR | O_CREAT | O_EXCL, 0o600)
        guard file >= 0 else { throw SharedMemoryError.failed(errno: errno) }
        _ = shm_unlink(name)
        return file
    }
}
#endif

/// The slots of a ``SharedFrameBuffer`` that the app may draw into. The app
/// acquires a slot for each frame, and the host releases it after copying.
public struct SlotPool: Equatable, Sendable {
    private var free: [Int]
    private var inUse: Set<Int> = []

    public init(count: Int) {
        free = Array(0..<count)
    }

    /// Takes the free slot that was released longest ago, or returns `nil`
    /// if the host holds every slot.
    public mutating func acquire() -> Int? {
        guard !free.isEmpty else { return nil }
        let slot = free.removeFirst()
        inUse.insert(slot)
        return slot
    }

    /// Returns a slot to the pool. Returns `false` if the slot was not in
    /// use, which means the host sent a stray release.
    @discardableResult
    public mutating func release(_ slot: Int) -> Bool {
        guard inUse.remove(slot) != nil else { return false }
        free.append(slot)
        return true
    }

    /// How many slots are free.
    public var freeCount: Int { free.count }
}
