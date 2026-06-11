import SwiftUI
import MetalKit
import CoreImage

/// MTKView + CIContext(Metal) でフィルタ済みのライブプレビューを描画する。
struct MetalPreviewView: UIViewRepresentable {
    @ObservedObject var camera: CameraManager
    var intensity: Double
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
        context.coordinator.squareCrop = squareCrop
    }

    final class Renderer: NSObject, MTKViewDelegate {
        let device = MTLCreateSystemDefaultDevice()
        var intensity: Double = 1.0
        var squareCrop = false

        private lazy var commandQueue = device?.makeCommandQueue()
        private lazy var ciContext: CIContext? = {
            guard let device else { return nil }
            return CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
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
            var image = latestImage
            lock.unlock()

            guard var input = image,
                  let ciContext,
                  let commandQueue,
                  let drawable = view.currentDrawable,
                  view.drawableSize.width > 0, view.drawableSize.height > 0 else { return }

            input = RetroFilmFilter.shared.apply(to: input, intensity: intensity)

            if squareCrop {
                let side = min(input.extent.width, input.extent.height)
                let crop = CGRect(x: input.extent.midX - side / 2,
                                  y: input.extent.midY - side / 2,
                                  width: side, height: side)
                input = input.cropped(to: crop)
            }

            // アスペクトフィットで drawable に収める
            let drawableSize = view.drawableSize
            let scale = min(drawableSize.width / input.extent.width,
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
