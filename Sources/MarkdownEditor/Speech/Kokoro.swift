// Built only with the Kokoro trait (see Package.swift).
#if Kokoro
import AVFoundation
import CEspeakNG
import NaturalLanguage
import OnnxRuntimeBindings

/// Kokoro-82M (Apache-2.0) voices, run locally: espeak-ng turns text into
/// phonemes and ONNX Runtime turns phonemes into 24 kHz audio.
enum Kokoro {
    static let sampleRate = 24_000.0
    /// Voice file name → display name, in menu order.
    static let voices = [("bm_daniel", "Daniel"), ("bm_george", "George")]

    // Pinned so a changed upstream file can't silently change the voices.
    // The model comes last; it is nearly all of the 326 MB.
    static let model = VoiceModel(
        name: "Kokoro",
        source: "https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX/resolve/1939ad2a8e416c0acfeecc08a694d14ef25f2231/",
        files: voices.map { ("\($0.0).bin", "voices/\($0.0).bin") } + [("model.onnx", "onnx/model.onnx")]
    )

    static func name(of voice: String) -> String? {
        voices.first { $0.0 == voice }?.1
    }

    // MARK: Phonemes

    /// The model takes at most 510 phonemes per call.
    static let maxPhonemes = 510

    /// Phonemes in chunks the model accepts, split between sentences where possible.
    static func phonemeChunks(_ text: String) -> [[Int64]] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var chunks: [[Int64]] = []
        var current: [Int64] = []
        for range in tokenizer.tokens(for: text.startIndex..<text.endIndex) {
            let sentence = tokens(phonemes(String(text[range])))
            if current.isEmpty || current.count + 1 + sentence.count <= maxPhonemes {
                current += (current.isEmpty ? [] : [space]) + sentence
            } else {
                chunks.append(current)
                current = sentence
            }
            while current.count > maxPhonemes {
                // One overlong sentence: cut at the last word break that fits.
                let cut = current[..<maxPhonemes].lastIndex(of: space) ?? maxPhonemes
                chunks.append(Array(current[..<cut]))
                current = Array(current[cut...].drop { $0 == space })
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    /// IPA with stress marks, punctuation kept, like phonemizer's
    /// `phonemize(text, "en-gb", preserve_punctuation=True, with_stress=True)`
    /// that Kokoro was trained on. espeak drops punctuation, so it is cut out
    /// first and put back after. `voice` is an espeak voice file: Plapre asks for Danish.
    static func phonemes(_ text: String, voice: String = "gmw/en") -> String {
        guard espeakReady else { return "" }
        // espeak keeps the voice in global state, and the Kokoro and Plapre engines take turns.
        espeakLock.lock()
        defer { espeakLock.unlock() }
        if espeakVoice != voice {
            guard espeak_SetVoiceByName(voice) == EE_OK else { return "" }
            espeakVoice = voice
        }
        var output = ""
        var rest = text[...]
        // Not a "." or "," inside a number like 2.50.
        while let mark = rest.firstMatch(of: #/(\s*)([;:,.!?¡¿—…"«»“”(){}\[\]]+)(?!\d)(\s*)/#) {
            output += espeak(rest[..<mark.range.lowerBound])
            output += (mark.output.1.isEmpty ? "" : " ") + mark.output.2 + (mark.output.3.isEmpty ? "" : " ")
            rest = rest[mark.range.upperBound...]
        }
        output += espeak(rest)
        return output.split(separator: " ").joined(separator: " ")
    }

    static func tokens(_ phonemes: String) -> [Int64] {
        phonemes.unicodeScalars.compactMap { vocab[$0] }
    }

    private static let space: Int64 = 16

    private static func espeak(_ text: Substring) -> String {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        var parts: [String] = []
        text.withCString { cString in
            var pointer: UnsafeRawPointer? = UnsafeRawPointer(cString)
            // IPA, phonemes separated by "_" (removed below)
            let mode = Int32(UInt8(ascii: "_")) << 8 | 0x02
            while pointer != nil, let result = espeak_TextToPhonemes(&pointer, espeakCHARS_UTF8, mode) {
                parts.append(String(cString: result))
            }
        }
        return parts.joined(separator: " ")
            .replacing(#/\([a-z-]+\)/#, with: "") // language switch flags like (fr)
            .replacing("_", with: "")
            .replacing("\n", with: " ")
    }

    /// The bundled English and Danish espeak data, or Homebrew's when run from `swift build`.
    private static let espeakReady: Bool = {
        let bundled = Bundle.main.resourceURL?.path
        let parent = [bundled, "/opt/homebrew/opt/espeak-ng/share"].compactMap { $0 }
            .first { FileManager.default.fileExists(atPath: $0 + "/espeak-ng-data/phontab") }
        // espeak exits the process when its data is missing, so check first.
        guard let parent else { return false }
        return espeak_Initialize(AUDIO_OUTPUT_SYNCHRONOUS, 0, parent, 0) > 0
    }()
    private static let espeakLock = NSLock()
    /// The voice file espeak has loaded: "gmw/en" is behind en-gb (British English), "gmq/da" Danish.
    nonisolated(unsafe) private static var espeakVoice = ""

    /// Kokoro v1.0's phoneme vocabulary.
    private static let vocab: [Unicode.Scalar: Int64] = [
        ";": 1, ":": 2, ",": 3, ".": 4, "!": 5, "?": 6, "\u{2014}": 9, "\u{2026}": 10,
        "\"": 11, "(": 12, ")": 13, "\u{201C}": 14, "\u{201D}": 15, "\u{20}": 16, "\u{303}": 17, "\u{2A3}": 18,
        "\u{2A5}": 19, "\u{2A6}": 20, "\u{2A8}": 21, "\u{1D5D}": 22, "\u{AB67}": 23, "A": 24, "I": 25, "O": 31,
        "Q": 33, "S": 35, "T": 36, "W": 39, "Y": 41, "\u{1D4A}": 42, "a": 43, "b": 44,
        "c": 45, "d": 46, "e": 47, "f": 48, "h": 50, "i": 51, "j": 52, "k": 53,
        "l": 54, "m": 55, "n": 56, "o": 57, "p": 58, "q": 59, "r": 60, "s": 61,
        "t": 62, "u": 63, "v": 64, "w": 65, "x": 66, "y": 67, "z": 68, "\u{251}": 69,
        "\u{250}": 70, "\u{252}": 71, "\u{E6}": 72, "\u{3B2}": 75, "\u{254}": 76, "\u{255}": 77, "\u{E7}": 78, "\u{256}": 80,
        "\u{F0}": 81, "\u{2A4}": 82, "\u{259}": 83, "\u{25A}": 85, "\u{25B}": 86, "\u{25C}": 87, "\u{25F}": 90, "\u{261}": 92,
        "\u{265}": 99, "\u{268}": 101, "\u{26A}": 102, "\u{29D}": 103, "\u{26F}": 110, "\u{270}": 111, "\u{14B}": 112, "\u{273}": 113,
        "\u{272}": 114, "\u{274}": 115, "\u{F8}": 116, "\u{278}": 118, "\u{3B8}": 119, "\u{153}": 120, "\u{279}": 123, "\u{27E}": 125,
        "\u{27B}": 126, "\u{281}": 128, "\u{27D}": 129, "\u{282}": 130, "\u{283}": 131, "\u{288}": 132, "\u{2A7}": 133, "\u{28A}": 135,
        "\u{28B}": 136, "\u{28C}": 138, "\u{263}": 139, "\u{264}": 140, "\u{3C7}": 142, "\u{28E}": 143, "\u{292}": 147, "\u{294}": 148,
        "\u{2C8}": 156, "\u{2CC}": 157, "\u{2D0}": 158, "\u{2B0}": 162, "\u{2B2}": 164, "\u{2193}": 169, "\u{2192}": 171, "\u{2197}": 172,
        "\u{2198}": 173, "\u{1D7B}": 177,
    ]
}

/// A downloadable set of model files in Application Support.
struct VoiceModel: Sendable {
    let directory: URL
    let source: URL
    /// Local file name → path in the model repo, or a full URL.
    let files: [(String, String)]

    init(name: String, source: String, files: [(String, String)]) {
        directory = URL.applicationSupportDirectory
            .appending(path: "MarkdownEditor/\(name)", directoryHint: .isDirectory)
        self.source = URL(string: source)!
        self.files = files
    }

    var isInstalled: Bool {
        files.allSatisfy { FileManager.default.fileExists(atPath: directory.appending(path: $0.0).path) }
    }

    func path(_ file: String) -> String {
        directory.appending(path: file).path
    }
}

/// Turns one sentence into 24 kHz samples.
protocol SpeechEngine: Actor {
    func audio(_ text: String, voice: String, speed: Float) async throws -> [Float]
}

/// Loads the model once and turns text into audio. An actor, so espeak and
/// the session are only ever used from one thread at a time.
actor KokoroEngine: SpeechEngine {
    private let env: ORTEnv
    private let session: ORTSession
    private var styles: [String: Data] = [:]

    init() throws {
        env = try ORTEnv(loggingLevel: .warning)
        session = try ORTSession(
            env: env,
            modelPath: Kokoro.model.path("model.onnx"),
            sessionOptions: nil
        )
    }

    func audio(_ text: String, voice: String, speed: Float) throws -> [Float] {
        let style = try styles[voice] ?? Data(contentsOf: URL(filePath: Kokoro.model.path("\(voice).bin")))
        styles[voice] = style
        var samples: [Float] = []
        for tokens in Kokoro.phonemeChunks(text) where !tokens.isEmpty {
            // Stop and Read Aloud again shouldn't wait for an old sentence to finish.
            try Task.checkCancellation()
            samples += try infer(tokens, style: style, speed: speed)
        }
        return samples
    }

    private func infer(_ tokens: [Int64], style: Data, speed: Float) throws -> [Float] {
        var ids = [0] + tokens + [0]
        var speed = speed
        // One 256-float style vector per phoneme count: n phonemes use row n - 1.
        let row = (min(tokens.count, Kokoro.maxPhonemes) - 1) * 256 * 4
        let output = try session.run(
            withInputs: [
                "input_ids": ORTValue(
                    tensorData: NSMutableData(bytes: &ids, length: ids.count * 8),
                    elementType: .int64, shape: [1, NSNumber(value: ids.count)]
                ),
                "style": ORTValue(
                    tensorData: NSMutableData(data: style.subdata(in: row..<row + 256 * 4)),
                    elementType: .float, shape: [1, 256]
                ),
                "speed": ORTValue(
                    tensorData: NSMutableData(bytes: &speed, length: 4),
                    elementType: .float, shape: [1]
                ),
            ],
            outputNames: ["waveform"],
            runOptions: nil
        )
        guard let waveform = output["waveform"] else { return [] }
        let data = try waveform.tensorData() as Data
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}

/// Fetches a model's files into Application Support, once.
@MainActor
final class ModelDownload: ObservableObject {
    static let kokoro = ModelDownload(Kokoro.model)
    static let plapre = ModelDownload(Plapre.model)

    let model: VoiceModel
    /// 0...1 while downloading, for the current file.
    @Published private(set) var progress: Double?
    @Published private(set) var isInstalled: Bool
    @Published private(set) var error: String?

    init(_ model: VoiceModel) {
        self.model = model
        isInstalled = model.isInstalled
    }

    func start() {
        guard progress == nil, !isInstalled else { return }
        progress = 0
        error = nil
        Task {
            do {
                try FileManager.default.createDirectory(at: model.directory, withIntermediateDirectories: true)
                for (name, path) in model.files {
                    let destination = model.directory.appending(path: name)
                    guard !FileManager.default.fileExists(atPath: destination.path) else { continue }
                    // A path in the model repo, or a full URL for a file from elsewhere.
                    try await fetch(URL(string: path, relativeTo: model.source)!.absoluteURL, to: destination)
                }
                isInstalled = model.isInstalled
            } catch {
                self.error = "Download failed: \(error.localizedDescription)"
            }
            progress = nil
        }
    }

    /// Downloads to a temporary file and only then moves it into place, so
    /// an interrupted download never looks installed.
    private func fetch(_ url: URL, to destination: URL) async throws {
        var task: URLSessionDownloadTask?
        let poll = Task {
            while !Task.isCancelled {
                if let fraction = task?.progress.fractionCompleted { progress = fraction }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        defer { poll.cancel() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task = URLSession.shared.downloadTask(with: url) { file, response, error in
                do {
                    if let error { throw error }
                    guard let file, (response as? HTTPURLResponse)?.statusCode == 200 else {
                        throw URLError(.badServerResponse)
                    }
                    try FileManager.default.moveItem(at: file, to: destination)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            task?.resume()
        }
    }
}

/// Plays sentences with a Kokoro or Plapre voice, generating a few ahead of playback.
@MainActor
final class VoicePlayer {
    enum Kind { case kokoro, plapre }

    /// One load per model, shared: starting again while a model loads mustn't load it twice.
    private var engines: [Kind: Task<any SpeechEngine, Error>] = [:]
    private let audioEngine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    /// Speeds Plapre up without raising its pitch; Kokoro sets its own speed.
    private let tempo = AVAudioUnitTimePitch()
    private let format = AVAudioFormat(standardFormatWithSampleRate: Kokoro.sampleRate, channels: 1)!
    private var generation: Task<Void, Never>?
    /// Bumped on every play and stop; callbacks from an older run are ignored.
    private var run = 0
    /// Sentences scheduled but not yet played, the first one playing; nil for the
    /// later pieces of a sentence Plapre reads in pieces.
    private var queued: [String?] = []
    /// Seconds of audio scheduled but not yet played.
    private var queuedSeconds: [Double] = []
    private var onSentence: (String) -> Void = { _ in }
    private var onFinish: (Error?) -> Void = { _ in }
    private var paused = false
    /// Playback has begun; before that, audio collects until `startBuffer` seconds are queued.
    private var started = false
    private var startBuffer = 0.0

    init() {
        audioEngine.attach(player)
        audioEngine.attach(tempo)
        audioEngine.connect(player, to: tempo, format: format)
        audioEngine.connect(tempo, to: audioEngine.mainMixerNode, format: format)
    }

    /// One piece of a sentence to synthesize, with what to announce when it
    /// starts playing and the pause after it.
    private struct Item {
        let text: String
        let sentence: String?
        let pause: Double
        let isLast: Bool
    }

    /// `onSentence` gets each sentence as it starts; `onFinish` runs once
    /// at the end, with the error if generating failed.
    func play(
        _ sentences: [ReadAloud.Sentence], with kind: Kind, voice: String, speed: Float,
        onSentence: @escaping (String) -> Void, onFinish: @escaping (Error?) -> Void
    ) {
        stop()
        self.onSentence = onSentence
        self.onFinish = onFinish
        tempo.rate = kind == .plapre ? Plapre.tempo * speed : 1
        // Plapre's short sentences take longer to make than to play; a little
        // audio in hand first keeps them from coming out in fits.
        startBuffer = kind == .plapre ? 2.5 : 0
        // Plapre reads a long sentence in pieces; each plays as soon as it's ready,
        // and only the first starts the sentence, for the highlight.
        let items = sentences.enumerated().flatMap { index, sentence in
            let pieces = kind == .plapre ? Plapre.pieces(Plapre.normalize(sentence.text)) : [sentence.text]
            return pieces.enumerated().map { number, piece in
                let last = number == pieces.count - 1
                return Item(
                    text: piece, sentence: number == 0 ? sentence.text : nil,
                    pause: !last ? 0.15 : sentence.endsBlock ? 0.45 : 0.2,
                    isLast: last && index == sentences.count - 1
                )
            }
        }
        let run = run
        generation = Task {
            do {
                let engine = try await loadEngine(kind)
                if !audioEngine.isRunning { try audioEngine.start() }
                if let plapre = engine as? PlapreEngine {
                    try await playOverlapped(items, with: plapre, voice: voice, run: run)
                } else {
                    for item in items {
                        try await waitForRoom()
                        let samples = try await engine.audio(item.text, voice: voice, speed: speed)
                        guard run == self.run else { return }
                        schedule(item, samples, run: run)
                    }
                }
            } catch is CancellationError {
            } catch {
                if run == self.run { self.onFinish(error) }
            }
        }
    }

    /// Plapre's language model works out the next piece on the GPU while the
    /// vocoder renders this one on the CPU.
    private func playOverlapped(_ items: [Item], with plapre: PlapreEngine, voice: String, run: Int) async throws {
        var previous: (item: Item, mel: PlapreMel)?
        for item in items.map(Optional.some) + [nil] {
            try await waitForRoom()
            let melToRender = previous?.mel
            async let rendered = Self.render(melToRender, with: plapre.vocoder)
            let mel: PlapreMel? = if let item { try await plapre.mel(item.text, voice: voice) } else { nil }
            let samples = try await rendered
            guard run == self.run else { return }
            if let previous, let samples { schedule(previous.item, samples, run: run) }
            previous = if let item, let mel { (item, mel) } else { nil }
        }
    }

    private nonisolated static func render(_ mel: PlapreMel?, with vocoder: PlapreVocoder) async throws -> [Float]? {
        guard let mel else { return nil }
        return try await vocoder.wave(mel)
    }

    /// Stays ~8 s ahead, not a fixed number of sentences: a run of short table
    /// cells mustn't leave too little to cover a long sentence after it.
    private func waitForRoom() async throws {
        while queuedSeconds.reduce(0, +) >= 8 { try await Task.sleep(for: .milliseconds(150)) }
    }

    func pause() {
        paused = true
        player.pause()
    }

    func resume() {
        paused = false
        if started { player.play() } else { startIfReady(force: true) }
    }

    func stop() {
        run += 1
        generation?.cancel()
        generation = nil
        player.stop()
        if audioEngine.isRunning { audioEngine.stop() }
        queued = []
        queuedSeconds = []
        paused = false
        started = false
    }

    private func loadEngine(_ kind: Kind) async throws -> any SpeechEngine {
        // Loading a model takes a few seconds; keep it off the main thread.
        let load = engines[kind] ?? Task.detached(priority: .userInitiated) {
            switch kind {
            case .kokoro: try KokoroEngine() as any SpeechEngine
            case .plapre: try PlapreEngine()
            }
        }
        engines[kind] = load
        do {
            return try await load.value
        } catch {
            // Let a later try load it again, e.g. once the files are downloaded.
            if engines[kind] == load { engines[kind] = nil }
            throw error
        }
    }

    /// The models pad each sentence with up to a second of silence of their own;
    /// cut it, keeping a little so soft first and last sounds survive, so the
    /// pause between sentences is ours alone.
    nonisolated static func trimmed(_ samples: [Float]) -> [Float] {
        guard let first = samples.firstIndex(where: { abs($0) > 0.01 }),
              let last = samples.lastIndex(where: { abs($0) > 0.01 }) else { return [] }
        let margin = Int(Kokoro.sampleRate * 0.05)
        return Array(samples[max(0, first - margin)...min(samples.count - 1, last + margin)])
    }

    nonisolated static func silence(_ seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(Kokoro.sampleRate * seconds))
    }

    private func schedule(_ item: Item, _ samples: [Float], run: Int) {
        let samples = Self.trimmed(samples) + Self.silence(item.pause)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = buffer.frameCapacity
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        queued.append(item.sentence)
        queuedSeconds.append(Double(samples.count) / Kokoro.sampleRate / Double(tempo.rate))
        // Already playing with nothing queued (generation fell behind): this starts right away.
        if queued.count == 1, started, !paused, let sentence = item.sentence { onSentence(sentence) }
        let isLast = item.isLast
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
            Task { @MainActor in
                guard run == self.run else { return }
                self.queued.removeFirst()
                self.queuedSeconds.removeFirst()
                if let next = self.queued.first, let next { self.onSentence(next) }
                if isLast { self.onFinish(nil) }
            }
        }
        startIfReady(force: item.isLast)
    }

    /// Starts playback once `startBuffer` seconds are queued, or everything is.
    private func startIfReady(force: Bool) {
        guard !started, !paused, force || queuedSeconds.reduce(0, +) >= startBuffer else { return }
        started = true
        player.play()
        if let first = queued.first, let first { onSentence(first) }
    }
}
#endif
