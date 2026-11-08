import AppKit

/// A saved signature: a transparent PNG kept in Application Support.
struct SavedSignature: Equatable {
    let id: String
    let url: URL
    let image: NSImage
}

/// Keeps up to five signatures in ~/Library/Application Support/PDFReader/Signatures,
/// in the order they were added (order.json), so they can be reused across documents.
final class SignatureStore {
    static let shared = SignatureStore()
    static let maxCount = 5
    static let didChange = Notification.Name("SignatureStoreDidChange")

    private let folder: URL
    private var orderURL: URL { folder.appendingPathComponent("order.json") }
    private(set) var signatures: [SavedSignature] = []

    var isFull: Bool { signatures.count >= Self.maxCount }

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        folder = base.appendingPathComponent("PDFReader/Signatures", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        reload()
    }

    private func reload() {
        var ids = (try? JSONDecoder().decode([String].self, from: Data(contentsOf: orderURL))) ?? []
        // Pick up PNGs missing from order.json (e.g. if it was deleted) and drop entries whose file is gone.
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "png" {
            let id = file.deletingPathExtension().lastPathComponent
            if !ids.contains(id) { ids.append(id) }
        }
        signatures = ids.compactMap { id in
            let url = folder.appendingPathComponent(id).appendingPathExtension("png")
            guard let image = NSImage(contentsOf: url) else { return nil }
            return SavedSignature(id: id, url: url, image: image)
        }
    }

    private func persistOrder() {
        let data = try? JSONEncoder().encode(signatures.map(\.id))
        try? data?.write(to: orderURL, options: .atomic)
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    /// Saves PNG data as a new signature. Throws if five are already saved.
    @discardableResult
    func add(pngData: Data) throws -> SavedSignature {
        guard !isFull else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError, userInfo: [
                NSLocalizedDescriptionKey: "You already have \(Self.maxCount) saved signatures.",
                NSLocalizedRecoverySuggestionErrorKey: "Delete one before adding another.",
            ])
        }
        let id = UUID().uuidString
        let url = folder.appendingPathComponent(id).appendingPathExtension("png")
        try pngData.write(to: url, options: .atomic)
        guard let image = NSImage(contentsOf: url) else {
            try? FileManager.default.removeItem(at: url)
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError)
        }
        let signature = SavedSignature(id: id, url: url, image: image)
        signatures.append(signature)
        persistOrder()
        return signature
    }

    func remove(_ signature: SavedSignature) {
        try? FileManager.default.removeItem(at: signature.url)
        signatures.removeAll { $0.id == signature.id }
        persistOrder()
    }
}

// MARK: - Image processing

enum SignatureImage {
    /// Turns a photo or scan of a signature into a transparent PNG: light background pixels become
    /// transparent, the ink keeps its colour, and the result is cropped to the ink.
    static func cleanedPNG(from image: NSImage, threshold: CGFloat = 0.80) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        // Keep big photos manageable.
        let scale = min(1, 2000 / CGFloat(max(cg.width, cg.height)))
        let width = max(1, Int(CGFloat(cg.width) * scale))
        let height = max(1, Int(CGFloat(cg.height) * scale))
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let buffer = ctx.data else { return nil }
        ctx.interpolationQuality = .high
        // Flatten onto white first so already-transparent images are handled the same way.
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        let pixels = buffer.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var minX = width, minY = height, maxX = -1, maxY = -1
        let low = threshold * 0.7 // fully opaque below this luminance, fade out between low and threshold
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let r = CGFloat(pixels[i]) / 255, g = CGFloat(pixels[i + 1]) / 255, b = CGFloat(pixels[i + 2]) / 255
                let luminance = 0.299 * r + 0.587 * g + 0.114 * b
                let alpha: CGFloat = luminance >= threshold ? 0 : (luminance <= low ? 1 : (threshold - luminance) / (threshold - low))
                if alpha == 0 {
                    pixels[i] = 0; pixels[i + 1] = 0; pixels[i + 2] = 0; pixels[i + 3] = 0
                    continue
                }
                // Darken the ink slightly and premultiply.
                pixels[i] = UInt8(r * 0.85 * alpha * 255)
                pixels[i + 1] = UInt8(g * 0.85 * alpha * 255)
                pixels[i + 2] = UInt8(b * 0.85 * alpha * 255)
                pixels[i + 3] = UInt8(alpha * 255)
                if alpha > 0.3 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= minX, maxY >= minY, let full = ctx.makeImage() else { return nil }
        let pad = 6
        // CGContext rows start at the top of the buffer, which matches CGImage cropping coordinates.
        let crop = CGRect(x: max(0, minX - pad), y: max(0, minY - pad),
                          width: min(width, maxX + pad + 1) - max(0, minX - pad),
                          height: min(height, maxY + pad + 1) - max(0, minY - pad))
        guard let cropped = full.cropping(to: crop) else { return nil }
        return NSBitmapImageRep(cgImage: cropped).representation(using: .png, properties: [:])
    }
}
