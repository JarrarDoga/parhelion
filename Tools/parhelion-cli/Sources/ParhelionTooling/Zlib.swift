import Foundation

#if canImport(Glibc)
import Glibc
#endif

/// zlib, loaded when first used.
///
/// The web preview compresses frames with zlib, and browsers decompress
/// them with `DecompressionStream`. The library is loaded at run time
/// rather than linked, so building the tool needs no zlib headers; the
/// shared library itself is part of every desktop and server Linux. If it
/// is missing, frames go uncompressed.
enum Zlib {
    private typealias CompressBound = @convention(c) (UInt) -> UInt
    private typealias Compress2 =
        @convention(c) (
            UnsafeMutablePointer<UInt8>?, UnsafeMutablePointer<UInt>?, UnsafePointer<UInt8>?, UInt,
            Int32
        ) -> Int32
    private typealias Uncompress =
        @convention(c) (
            UnsafeMutablePointer<UInt8>?, UnsafeMutablePointer<UInt>?, UnsafePointer<UInt8>?, UInt
        ) -> Int32
    private typealias CRC32 = @convention(c) (UInt, UnsafePointer<UInt8>?, UInt32) -> UInt

    private struct Library: @unchecked Sendable {
        let compressBound: CompressBound
        let compress2: Compress2
        let uncompress: Uncompress
        let crc32: CRC32
    }

    private static let library: Library? = {
        #if canImport(Glibc)
        guard
            let handle = dlopen("libz.so.1", RTLD_NOW | RTLD_LOCAL)
                ?? dlopen("libz.so", RTLD_NOW | RTLD_LOCAL),
            let bound = dlsym(handle, "compressBound"),
            let compress = dlsym(handle, "compress2"),
            let uncompress = dlsym(handle, "uncompress"),
            let crc32 = dlsym(handle, "crc32")
        else { return nil }
        return Library(
            compressBound: unsafeBitCast(bound, to: CompressBound.self),
            compress2: unsafeBitCast(compress, to: Compress2.self),
            uncompress: unsafeBitCast(uncompress, to: Uncompress.self),
            crc32: unsafeBitCast(crc32, to: CRC32.self))
        #else
        return nil
        #endif
    }()

    /// Whether zlib could be loaded.
    static var isAvailable: Bool { library != nil }

    /// The bytes as a zlib stream (RFC 1950) at a compression level from 1,
    /// the fastest, to 9, the smallest, or `nil` without zlib.
    static func compress(_ bytes: UnsafeRawBufferPointer, level: Int32) -> [UInt8]? {
        guard let library else { return nil }
        let source = bytes.bindMemory(to: UInt8.self)
        var capacity = library.compressBound(UInt(bytes.count))
        var output = [UInt8](repeating: 0, count: Int(capacity))
        let status = output.withUnsafeMutableBufferPointer { destination in
            library.compress2(
                destination.baseAddress, &capacity, source.baseAddress, UInt(bytes.count), level)
        }
        guard status == 0 else { return nil }
        output.removeLast(output.count - Int(capacity))
        return output
    }

    /// The CRC-32 of `count` bytes, or `nil` without zlib. zlib computes it
    /// with the processor's carry-less multiply where there is one, which
    /// makes it the fastest way here to tell rows of pixels apart.
    static func crc32(_ bytes: UnsafeRawPointer, count: Int) -> UInt32? {
        guard let library else { return nil }
        let value = library.crc32(
            0, bytes.assumingMemoryBound(to: UInt8.self), UInt32(truncatingIfNeeded: count))
        return UInt32(truncatingIfNeeded: value)
    }

    /// The bytes of a zlib stream that holds exactly `size` bytes, or `nil`
    /// if it does not, or without zlib.
    static func decompress(_ bytes: [UInt8], size: Int) -> [UInt8]? {
        guard let library else { return nil }
        var length = UInt(size)
        var output = [UInt8](repeating: 0, count: size)
        let status = output.withUnsafeMutableBufferPointer { destination in
            bytes.withUnsafeBufferPointer { source in
                library.uncompress(
                    destination.baseAddress, &length, source.baseAddress, UInt(bytes.count))
            }
        }
        guard status == 0, length == UInt(size) else { return nil }
        return output
    }
}
