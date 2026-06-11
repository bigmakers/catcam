import CoreImage
import CoreImage.CIFilterBuiltins

/// Metal で書いた Core Image カーネル(retroFilm)のラッパー。
/// レトロ・フィルム風(退色プリント調)に仕上げ、周辺に温かみのある軽いビネットを重ねる。
final class RetroFilmFilter {
    static let shared = RetroFilmFilter()

    private let kernel: CIColorKernel? = {
        guard let url = Bundle.main.url(forResource: "default", withExtension: "metallib"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? CIColorKernel(functionName: "retroFilm", fromMetalLibraryData: data)
    }()

    func apply(to image: CIImage, intensity: Double) -> CIImage {
        guard intensity > 0.001 else { return image }

        var output = image
        if let kernel,
           let filtered = kernel.apply(extent: image.extent,
                                       arguments: [image, Float(intensity)]) {
            output = filtered
        }

        // レトロ調らしい軽めのビネット(ノワールほど強く落とさない)
        let vignette = CIFilter.vignette()
        vignette.inputImage = output
        vignette.intensity = Float(0.45 * intensity)
        vignette.radius = 2.6
        if let vignetted = vignette.outputImage {
            output = vignetted
        }
        return output
    }
}
