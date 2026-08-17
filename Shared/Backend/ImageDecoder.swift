import ImageIO

#if canImport(libwebp)
    import CoreGraphics
    import libwebp
    import UIKit

    public enum WebPError: Swift.Error, LocalizedError {
        case unexpectedPointerError // Something related pointer operation's error
        case unexpectedError(withMessage: String) // Something happened
        case unknownDecodingError
        case decodingError
        case decoderConfigError
    }

    private func inspect(_ webPData: Data) throws -> WebPBitstreamFeatures {
        let cFeature = UnsafeMutablePointer<WebPBitstreamFeatures>.allocate(capacity: 1)
        defer { cFeature.deallocate() }

        let status = try webPData.withUnsafeBytes { rawPtr -> VP8StatusCode in
            guard let bindedBasePtr = rawPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                throw WebPError.unexpectedPointerError
            }

            return WebPGetFeatures(bindedBasePtr, webPData.count, &cFeature.pointee)
        }

        guard status == VP8_STATUS_OK else {
            throw WebPError.unexpectedError(withMessage: "Error VP8StatusCode=\(status.rawValue)")
        }

        return cFeature.pointee
    }

    private func decode(_ webPData: Data, config: inout WebPDecoderConfig) throws {
        var mutableWebPData = webPData

        try mutableWebPData.withUnsafeMutableBytes { rawPtr in

            guard let bindedBasePtr = rawPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                throw WebPError.unknownDecodingError
            }

            let status = WebPDecode(bindedBasePtr, webPData.count, &config)
            if status != VP8_STATUS_OK {
                throw WebPError.decodingError
            }
        }
    }

    private func decode(_ webPData: Data) throws -> CGImage {
        let feature = try inspect(webPData)
        let height = Int(feature.height)
        let width = Int(feature.width)
        var config = WebPDecoderConfig()
        if WebPInitDecoderConfig(&config) == 0 {
            throw WebPError.decoderConfigError
        }
        config.options = WebPDecoderOptions()
        config.output.colorspace = MODE_RGBA

        try decode(webPData, config: &config)

        let decodedData: CFData = Data(bytesNoCopy: config.output.u.RGBA.rgba,
                                       count: config.output.u.RGBA.size,
                                       deallocator: .free) as CFData

        guard let provider = CGDataProvider(data: decodedData) else {
            throw WebPError.unexpectedError(withMessage: "Couldn't initialize CGDataProvider")
        }

        let bitmapInfo = CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo
            .premultipliedLast.rawValue)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let renderingIntent = CGColorRenderingIntent.defaultIntent
        let bytesPerPixel = 4

        if let cgImage = CGImage(width: width,
                                 height: height,
                                 bitsPerComponent: 8,
                                 bitsPerPixel: 8 * bytesPerPixel,
                                 bytesPerRow: bytesPerPixel * width,
                                 space: colorSpace,
                                 bitmapInfo: bitmapInfo,
                                 provider: provider,
                                 decode: nil,
                                 shouldInterpolate: false,
                                 intent: renderingIntent)
        {
            return cgImage
        }

        throw WebPError.unexpectedError(withMessage: "Couldn't initialize CGImage")
    }

    func decodeImage(data: Data, mimeType: String) async throws -> Data {
        let isWebP = mimeType == "image/webp"

        if isWebP {
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.computation.async {
                    do {
                        let cgImage = try decode(data)
                        let webpImage = UIImage(cgImage: cgImage)
                        if let pngData = webpImage.pngData() {
                            continuation.resume(returning: pngData)
                        } else {
                            continuation.resume(throwing: NSError(domain: "AppIconError", code: 1, userInfo: nil))
                        }
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }

        return try validatedImageData(data, mimeType: mimeType)
    }
#else
    import Foundation
    func decodeImage(data: Data, mimeType: String) async throws -> Data {
        return try validatedImageData(data, mimeType: mimeType)
    }
#endif

public enum ImageDataError: Swift.Error, LocalizedError {
    case empty(mimeType: String)
    case undecodable(mimeType: String, byteCount: Int)

    public var errorDescription: String? {
        switch self {
        case .empty(let mimeType):
            return "Image payload was empty (Content-Type: \(mimeType))"
        case .undecodable(let mimeType, let byteCount):
            return
                "Image payload of \(byteCount) bytes could not be decoded (Content-Type: \(mimeType))"
        }
    }
}

/// Rejects payloads that are not decodable images, so they never reach disk.
///
/// A Roku answers `query/icon/<id>` with an `image/*` `Content-Type` even when
/// the body is not a usable image -- a truncated response on a busy network, or
/// an error page. Nothing checked, so `storeIconToDisk` wrote it verbatim and
/// the failure became permanent: every appearance of that app re-read the bad
/// bytes, failed to decode, and rewrote the empty thumbnail markers. Six of one
/// iPad's 26 icons were in that state (roam 1.50).
///
/// This decodes rather than only sniffing the header, because a truncated file
/// with an intact header is exactly the case worth catching. Icons are a few KB
/// and this runs off the main thread at fetch time, once per icon.
func validatedImageData(_ data: Data, mimeType: String) throws -> Data {
    guard !data.isEmpty else {
        throw ImageDataError.empty(mimeType: mimeType)
    }
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
        CGImageSourceGetCount(source) > 0,
        CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
    else {
        throw ImageDataError.undecodable(mimeType: mimeType, byteCount: data.count)
    }
    return data
}
