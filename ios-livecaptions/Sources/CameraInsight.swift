import AVFoundation
import UIKit
import Vision

final class CameraInsight: NSObject, ObservableObject {
    @Published private(set) var status = "No image"
    @Published private(set) var result = ""

    private let synthesizer = AVSpeechSynthesizer()

    func process(image: UIImage, speak: Bool = true) {
        guard let cgImage = image.cgImage else {
            status = "Image unavailable"
            return
        }

        status = "Reading image…"
        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard let self else { return }
            let lines = (request.results as? [VNRecognizedTextObservation] ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
            let text = lines.joined(separator: "\n")
            DispatchQueue.main.async {
                if let error {
                    self.status = "Could not read image"
                    self.result = error.localizedDescription
                    return
                }
                self.result = text.isEmpty ? "No readable text found." : text
                self.status = "Ready"
                if speak { self.speak(self.result) }
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try VNImageRequestHandler(cgImage: cgImage).perform([request])
            } catch {
                DispatchQueue.main.async {
                    self.status = "Could not read image"
                    self.result = error.localizedDescription
                }
            }
        }
    }

    func speak(_ text: String) {
        guard !text.isEmpty else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.48
        synthesizer.speak(utterance)
    }
}
