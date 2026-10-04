import SwiftUI
import MetalKit
import CoreImage

/// MTKView + CIContext(Metal) でフィルタ済みのライブプレビューを描画する。
struct MetalPreviewView: UIViewRepresentable {
    @ObservedObject var camera: CameraManager
    var intensity: Double
    var coolness: Double
    var sim: FilmSimulation
    var squareCrop: Bool

    func makeCoordinator() -> Renderer {
        Renderer()
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)
        view.delegate = context.coordinator
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = 30
        view.backgroundColor = .black

        camera.onPreviewFrame = { [weak coordinator = context.coordinator] image in
            coordinator?.submit(image)
        }
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.intensity = intensity
        context.coordinator.coolness = coolness
        context.coordinator.sim = sim
        context.coordinator.squareCrop = squareCrop
    }

    final class Renderer: NSObject, MTKViewDelegate {
        let device = MTLCreateSystemDefaultDevice()
        var intensity: Double = 1.0
        var coolness: Double = 0.0
        var sim: FilmSimulation = .standard
        var squareCrop = false

        private lazy var commandQueue = device?.makeCommandQueue()
        private lazy var ciContext: CIContext? = {
            guard let device else { return nil }
            // 作業色空間を sRGB に固定する。既定はリニアで、そこで階調カーブや
            // シャドウリフトを掛けると黒が浮いて霞み、暗部の色被りが暴れる。
            // フィルムのトーンは表示基準(ガンマ済み)で設計しているので、ここを合わせる。
            // PhotoRenderer と同じ設定にしてあり、プレビューと保存が一致する。
            return CIContext(mtlDevice: device, options: [
                .cacheIntermediates: false,
                .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            ])
        }()

        private let lock = NSLock()
        private var latestImage: CIImage?

        func submit(_ image: CIImage) {
            lock.lock()
            latestImage = image
            lock.unlock()
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            lock.lock()
            let image = latestImage
            lock.unlock()

            guard var input = image,
                  let ciContext,
                  let commandQueue,
                  let drawable = view.currentDrawable,
                  view.drawableSize.width > 0, view.drawableSize.height > 0 else { return }

            input = FilmSimulationFilter.shared.apply(to: input, sim: sim, intensity: intensity, coolness: coolness)

            if squareCrop {
                let side = min(input.extent.width, input.extent.height)
                let crop = CGRect(x: input.extent.midX - side / 2,
                                  y: input.extent.midY - side / 2,
                                  width: side, height: side)
                input = input.cropped(to: crop)
            }

            // アスペクトフィルで drawable を満たす(はみ出しは描画 bounds でクロップ)。
            // 保存画像(通常モードは 9:16 センタークロップ)とプレビューを一致させる。
            let drawableSize = view.drawableSize
            let scale = max(drawableSize.width / input.extent.width,
                            drawableSize.height / input.extent.height)
            input = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            input = input.transformed(by: CGAffineTransform(
                translationX: (drawableSize.width - input.extent.width) / 2 - input.extent.origin.x,
                y: (drawableSize.height - input.extent.height) / 2 - input.extent.origin.y))

            // レターボックス部分が前フレームのまま残らないよう黒背景に合成する
            input = input.composited(over: CIImage(color: .black)
                .cropped(to: CGRect(origin: .zero, size: drawableSize)))

            guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

            ciContext.render(input,
                             to: drawable.texture,
                             commandBuffer: commandBuffer,
                             bounds: CGRect(origin: .zero, size: drawableSize),
                             colorSpace: CGColorSpaceCreateDeviceRGB())

            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
