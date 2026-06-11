import CoreImage
import CoreImage.CIFilterBuiltins

/// Metal で書いた Core Image カーネル(noirFilm)のラッパー。
/// ビネットを重ねて周辺を落とし、黒の沈みを強調する。
final class NoirFilmFilter {
    static let shared = NoirFilmFilter()

    private let kernel: CIColorKernel? = {
        guard let url = Bundle.main.url(forResource: "default", withExtension: "metallib"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? CIColorKernel(functionName: "noirFilm", fromMetalLibraryData: data)
    }()

    func apply(to image: CIImage, intensity: Double) -> CIImage {
        guard intensity > 0.001 else { return image }

        var output = image
        if let kernel,
           let filtered = kernel.apply(extent: image.extent,
                                       arguments: [image, Float(intensity)]) {
            output = filtered
        }

        let vignette = CIFilter.vignette()
        vignette.inputImage = output
        vignette.intensity = Float(0.9 * intensity)
        vignette.radius = 2.2
        if let vignetted = vignette.outputImage {
            output = vignetted
        }
        return output
    }
}
