import AVFoundation

/// 猫を振り向かせるための「呼び鈴」音を、著作権音源を同梱せず
/// PCM サンプルから合成して鳴らすプレイヤー。
/// 猫の注意を引くのが目的なので、高めで短い音をターゲットにしている。
final class CatCaller: ObservableObject {

    /// 呼び鈴のサウンド種別。
    enum Sound: String, CaseIterable, Identifiable {
        case squeak   // チュチュ(ネズミ/おもちゃのチューに近い高い音)
        case trill    // チチチ(鳥/虫のような短い連続チャープ)
        case meow     // ニャー(合成のミャーゥ)

        var id: String { rawValue }

        /// 選択 UI 等に出す日本語ラベル。
        var label: String {
            switch self {
            case .squeak: return "チュチュ"
            case .trill:  return "チチチ"
            case .meow:   return "ニャー"
            }
        }

        /// ボタン/メニュー用の SF Symbol 名。
        var symbol: String {
            switch self {
            case .squeak: return "hare.fill"
            case .trill:  return "bird.fill"
            case .meow:   return "cat.fill"
            }
        }
    }

    // MARK: - オーディオエンジン

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    /// 44100Hz mono float の再生フォーマット。
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

    /// AVAudioSession の初期化済みフラグ(初回再生時に一度だけ構成する)。
    private var sessionConfigured = false
    /// エンジン構成済みフラグ。
    private var engineConfigured = false

    private let sampleRate: Double = 44_100

    // MARK: - 公開 API

    /// 指定サウンドを合成して再生する。
    /// 再生中に再度呼ばれても新しい音を重ねて鳴らす(連打してもクラッシュしない)。
    func play(_ sound: Sound) {
        configureSessionIfNeeded()
        configureEngineIfNeeded()
        guard engine.isRunning else { return }

        guard let buffer = makeBuffer(for: sound) else { return }
        // player が停止していない限り schedule した音は順次/重ねて再生される。
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    // MARK: - セットアップ

    /// 初回再生時に AVAudioSession を .playback で構成する。
    /// .playback にすることでマナーモード(サイレントスイッチ)でも鳴る。
    /// カメラの AVCaptureSession(映像のみ)と共存する想定。エラーは握りつぶす。
    private func configureSessionIfNeeded() {
        guard !sessionConfigured else { return }
        sessionConfigured = true
        let session = AVAudioSession.sharedInstance()
        do {
            // 他アプリの音や映像キャプチャを邪魔しないよう mixWithOthers を付与。
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            // 失敗しても再生を試みるだけで、クラッシュさせない。
        }
    }

    /// エンジンに player を接続して起動する(初回のみ)。
    private func configureEngineIfNeeded() {
        guard !engineConfigured else {
            // 一度構成済みでも、中断後などで停止していたら再起動を試みる。
            if !engine.isRunning { try? engine.start() }
            return
        }
        engineConfigured = true
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            // 起動失敗時も握りつぶす(無音になるだけ)。
        }
    }

    // MARK: - サウンド合成

    /// サウンド種別に応じた PCM バッファを生成する。
    private func makeBuffer(for sound: Sound) -> AVAudioPCMBuffer? {
        let samples: [Float]
        switch sound {
        case .squeak: samples = synthesizeSqueak()
        case .trill:  samples = synthesizeTrill()
        case .meow:   samples = synthesizeMeow()
        }
        return makePCMBuffer(from: samples)
    }

    /// Float サンプル配列を mono の AVAudioPCMBuffer に詰める。
    /// クリップ防止に全体 0.9 でスケールし、先頭/末尾に短いフェードを掛ける。
    private func makePCMBuffer(from rawSamples: [Float]) -> AVAudioPCMBuffer? {
        var samples = rawSamples
        applyEdgeFade(&samples)
        let count = AVAudioFrameCount(samples.count)
        guard count > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count),
              let channel = buffer.floatChannelData?[0] else { return nil }

        let scale: Float = 0.9
        for i in 0..<samples.count {
            channel[i] = samples[i] * scale
        }
        buffer.frameLength = count
        return buffer
    }

    /// 先頭/末尾に数 ms のフェードを入れてプチノイズを防ぐ。
    private func applyEdgeFade(_ samples: inout [Float]) {
        let fade = min(Int(sampleRate * 0.004), samples.count / 2)  // 約 4ms
        guard fade > 0 else { return }
        for i in 0..<fade {
            let g = Float(i) / Float(fade)
            samples[i] *= g
            samples[samples.count - 1 - i] *= g
        }
    }

    // MARK: - 各サウンドの波形生成

    /// squeak: 約0.18秒。基本 ~3.5kHz を素早く上→下へピッチベンドし、
    /// 鋭いアタックと指数減衰エンベロープ。おもちゃのチューに近い高い音。
    private func synthesizeSqueak() -> [Float] {
        let duration = 0.18
        let n = Int(sampleRate * duration)
        var out = [Float](repeating: 0, count: n)
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / sampleRate
            let p = t / duration                       // 0→1 の進行
            // ピッチを素早く上げてから下げる(山型)。3.0kHz〜4.2kHz あたり。
            let bend = sin(p * .pi)                     // 0→1→0
            let freq = 3_000 + 1_200 * bend
            phase += 2 * .pi * freq / sampleRate
            // 鋭いアタック(立ち上がり一瞬)+ 指数減衰。
            let attack = min(1.0, t / 0.005)
            let decay = exp(-7.0 * p)
            out[i] = Float(sin(phase) * attack * decay)
        }
        return out
    }

    /// trill: 60ms 程度の短いチャープを 4 回、間に小さな無音。
    /// 各チャープ ~4〜5kHz。鳥/虫のチチチ。
    private func synthesizeTrill() -> [Float] {
        let chirpCount = 4
        let chirpDur = 0.045
        let gapDur = 0.030
        let chirpN = Int(sampleRate * chirpDur)
        let gapN = Int(sampleRate * gapDur)
        var out = [Float]()
        out.reserveCapacity((chirpN + gapN) * chirpCount)

        for _ in 0..<chirpCount {
            var phase = 0.0
            for i in 0..<chirpN {
                let t = Double(i) / sampleRate
                let p = t / chirpDur
                // 1チャープ内で 4.0kHz→5.2kHz へ上昇するチャープ。
                let freq = 4_000 + 1_200 * p
                phase += 2 * .pi * freq / sampleRate
                // 各チャープごとに山型エンベロープ。
                let env = sin(p * .pi)
                out.append(Float(sin(phase) * env))
            }
            // チャープ間の小さな無音。
            for _ in 0..<gapN { out.append(0) }
        }
        return out
    }

    /// meow: 約0.45秒。基本 ~700Hz にビブラート、ピッチを軽く上げてから
    /// 下げる「ミャーゥ」風の輪郭。倍音を少し足す。
    /// 合成なので作り物っぽい音になるが、注意喚起目的なので可。
    private func synthesizeMeow() -> [Float] {
        let duration = 0.45
        let n = Int(sampleRate * duration)
        var out = [Float](repeating: 0, count: n)
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / sampleRate
            let p = t / duration
            // ピッチ輪郭: 700Hz から軽く上げ(~820Hz)てから下げる(~620Hz)。
            let contour = sin(p * .pi) - 0.3 * p
            let base = 700 + 160 * contour
            // ビブラート(約6Hz)で「ミャーゥ」の揺らぎ。
            let vibrato = 1.0 + 0.02 * sin(2 * .pi * 6 * t)
            let freq = base * vibrato
            phase += 2 * .pi * freq / sampleRate
            // 倍音を少し足してそれらしく。
            let fundamental = sin(phase)
            let harmonic2 = 0.3 * sin(2 * phase)
            let harmonic3 = 0.12 * sin(3 * phase)
            // ゆるいアタック + なだらかな減衰の山型エンベロープ。
            let attack = min(1.0, t / 0.03)
            let env = attack * (0.6 + 0.4 * sin(p * .pi))
            out[i] = Float((fundamental + harmonic2 + harmonic3) * env * 0.7)
        }
        return out
    }
}
