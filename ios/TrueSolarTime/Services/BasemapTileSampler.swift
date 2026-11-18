import Foundation
import UIKit

/// 瓦片解码 + 32×32 采样（步长 8、最近邻），交给 Core 的 `BlankTileAnalysis` 判定。
///
/// 探测（找「哪一档有内容」）和正式加载（高德空白瓦片判定）都用它，所以放在 Services 里共用。
enum BasemapTileSampler {

    static let side = BlankTileAnalysis.sampleSide

    static func blankAnalysis(data: Data) -> BlankTileAnalysis? {
        guard let image = UIImage(data: data)?.cgImage else { return nil }
        return analyze(image: image)
    }

    private static func analyze(image: CGImage) -> BlankTileAnalysis? {
        let dimension = side
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              // 让 CoreGraphics 自己分配缓冲区（`data: nil`）：指针归 context 所有，
              // 比把 Swift 数组的指针借出去再在外面用要安全。
              let context = CGContext(
                data: nil,
                width: dimension,
                height: dimension,
                bitsPerComponent: 8,
                bytesPerRow: dimension * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        // 最近邻：不要插值 —— 与 Android 的「256×256 步长 8 取点」等价。
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: dimension, height: dimension))

        guard let base = context.data else { return nil }
        let buffer = base.bindMemory(to: UInt8.self, capacity: dimension * dimension * 4)

        let count = dimension * dimension
        var reds = [UInt8](repeating: 0, count: count)
        var greens = [UInt8](repeating: 0, count: count)
        var blues = [UInt8](repeating: 0, count: count)
        for index in 0..<count {
            reds[index] = buffer[index * 4]
            greens[index] = buffer[index * 4 + 1]
            blues[index] = buffer[index * 4 + 2]
        }
        return BlankTileAnalysis.analyze(reds: reds, greens: greens, blues: blues)
    }
}
