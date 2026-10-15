// Built only with the Kokoro trait (see Package.swift).
#if Kokoro
import CLlama
import Foundation
import OnnxRuntimeBindings
import os

/// Plapre Turbo (syv.ai, MIT) Danish voices, run locally: a Llama reads the text
/// and its espeak phonemes and predicts Kanade audio tokens (llama.cpp, on the GPU),
/// which the Kanade decoder (MIT) and the HiFT vocoder (Apache-2.0) turn into 24 kHz
/// audio (ONNX export by elgehelge/plapre-onnx-web, CC BY 4.0: keep the credit in Settings).
/// The voices are Mic and Nic from the CoRal TTS dataset (CC0).
enum Plapre {
    /// Built-in speaker → display name, in menu order.
    static let voices = [("mic", "Mic"), ("nic", "Nic")]
    /// Plays this much faster on top of the speed setting.
    static let tempo: Float = 1

    // Pinned so a changed upstream file can't silently change the voices.
    // Small files first; the decoder and language model are nearly all of the 790 MB.
    // Plapre Pico, the smaller model, ran on the CPU only and couldn't keep up with playback.
    static let model = VoiceModel(
        name: "PlapreTurbo",
        source: "https://huggingface.co/elgehelge/plapre-onnx-web/resolve/0320a33b9f598db61c1c72d5f2df755f5cb08d5c/",
        files: [
            ("tokenizer.json", turboSource + "tokenizer.json"),
            ("hift_vocoder.onnx", "hift_vocoder.onnx"),
            ("hift_vocoder.onnx.data", "hift_vocoder.onnx.data"),
            ("kanade_decoder.onnx", "kanade_decoder.onnx"),
            ("kanade_decoder.onnx.data", "kanade_decoder.onnx.data"),
            ("turbo.gguf", turboSource + "gguf/plapre-turbo.q8_0.gguf"),
        ]
    )
    private static let turboSource = "https://huggingface.co/syvai/plapre-turbo/resolve/a1b035cc9efb7b85345a7a685fadccc5cc9c861f/"

    static func name(of voice: String) -> String? {
        voices.first { $0.0 == voice }?.1
    }

    /// Danish IPA as Plapre Turbo was trained on it: phonemizer's espeak output
    /// with punctuation kept and stress marks dropped.
    static func phonemes(_ text: String) -> String {
        Kokoro.phonemes(text, voice: "gmq/da").filter { !"ˈˌ'-".contains($0) }
    }

    /// The model file repeats one token's text (five phonemes became U+FFFD in its
    /// export), and llama.cpp won't load a vocabulary with repeats. Prompts use the
    /// ids from tokenizer.json, so the repeats only need telling apart: ">" becomes
    /// "a", "b", .... Done in place, once; the vocabulary sits near the start.
    static func patchRepeatedTokens(_ path: String) throws {
        let file = try FileHandle(forUpdating: URL(filePath: path))
        defer { try? file.close() }
        let head = try file.read(upToCount: 4 << 20) ?? Data()
        let token = Data("<phone_\u{FFFD}>".utf8)
        var offsets: [Int] = []
        var from = head.startIndex
        while let found = head.range(of: token, in: from..<head.endIndex) {
            offsets.append(found.lowerBound)
            from = found.upperBound
        }
        for (index, offset) in offsets.dropFirst().enumerated() {
            try file.seek(toOffset: UInt64(offset + token.count - 1))
            try file.write(contentsOf: [UInt8(ascii: "a") + UInt8(index)])
        }
    }

    /// Text as Plapre was trained on it: numbers as Danish words, ending on a
    /// full stop (its stop signal is strongest at the end of a sentence).
    static func normalize(_ text: String) -> String {
        var text = text
            // 2026-08-26 → "seksogtyvende august 2026"
            .replacing(#/(\d{4})-(\d{2})-(\d{2})/#) { match in
                guard let month = Int(match.output.2), let day = Int(match.output.3),
                      (1...12).contains(month), (1...31).contains(day) else { return String(match.output.0) }
                return "\(ordinals[day - 1]) \(months[month - 1]) \(match.output.1)"
            }
            // A web address as its domain: "deltek punktum com".
            .replacing(#/https?:\/\/(?:www\.)?([^\s\/)>]+)[^\s)>]*/#) { $0.output.1.replacing(".", with: " punktum ") }
            // Codes like A3 and D4: "A tre", not "Atre".
            .replacing(#/(\p{L})(\d)/#) { "\($0.output.1) \($0.output.2)" }
            .replacing(#/(\d)\s*%/#) { "\($0.output.1) procent" }
        text = text.replacing(#/\d{1,3}(?:\.\d{3})+(?:,\d+)?|\d+(?:[,.]\d+)?/#) { numberWords(String($0.output)) }
        text = text.trimmingCharacters(in: .whitespaces)
        if text.hasSuffix(",") { text.removeLast() }
        return text.last.map { ".?!:…".contains($0) } == false ? text + "." : text
    }

    /// "2" → "to", "2,5" → "to komma fem", "1.500" → "ettusinde og femhundrede",
    /// like plapre's own normalizer but with Danish thousands separators.
    static func numberWords(_ number: String) -> String {
        let grouped = number.wholeMatch(of: #/\d{1,3}(\.\d{3})+(,\d+)?/#) != nil
        let parts = (grouped ? number.replacing(".", with: "") : number).split(whereSeparator: { $0 == "," || $0 == "." })
        guard let whole = Int(parts[0]) else { return number }
        guard parts.count > 1 else { return words(whole) }
        return words(whole) + " komma " + parts[1].map { ones[Int(String($0))!] }.joined(separator: " ")
    }

    private static let months = [
        "januar", "februar", "marts", "april", "maj", "juni", "juli", "august", "september", "oktober", "november", "december",
    ]
    private static let ordinals = [
        "første", "anden", "tredje", "fjerde", "femte", "sjette", "syvende", "ottende", "niende", "tiende", "ellevte",
        "tolvte", "trettende", "fjortende", "femtende", "sekstende", "syttende", "attende", "nittende", "tyvende",
        "enogtyvende", "toogtyvende", "treogtyvende", "fireogtyvende", "femogtyvende", "seksogtyvende", "syvogtyvende",
        "otteogtyvende", "niogtyvende", "tredivte", "enogtredivte",
    ]

    /// A long sentence in pieces of about `max` characters, cut after a comma,
    /// semicolon or colon, or before a dash or parenthesis. The language model
    /// can say about 250 characters at most and babbles more the longer it goes,
    /// so this trades a little intonation for the whole sentence being said.
    static func pieces(_ text: String, max: Int = 150) -> [String] {
        guard text.count > max else { return [text] }
        var pieces: [String] = []
        var current = ""
        var pending = ""
        var depth = 0
        var rest = text[...]
        func take() {
            if !current.isEmpty, current.count + pending.count > max {
                pieces.append(current)
                current = ""
            }
            current += pending
            pending = ""
        }
        while let cut = rest.firstMatch(of: #/[,;:](?=\s)|\s(?=[-–]\s)|\s(?=\()/#) {
            let part = rest[..<cut.range.upperBound]
            rest = rest[cut.range.upperBound...]
            depth += part.count { $0 == "(" } - part.count { $0 == ")" }
            pending += part
            // Never cut inside parentheses.
            if depth <= 0 { take() }
        }
        pending += rest
        take()
        pieces.append(current)
        return pieces.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static let ones = [
        "nul", "et", "to", "tre", "fire", "fem", "seks", "syv", "otte", "ni", "ti", "elleve", "tolv",
        "tretten", "fjorten", "femten", "seksten", "sytten", "atten", "nitten",
    ]
    private static let tens = ["", "", "tyve", "tredive", "fyrre", "halvtreds", "treds", "halvfjerds", "firs", "halvfems"]

    private static func words(_ n: Int) -> String {
        switch n {
        case ..<20: return ones[n]
        case ..<100: return (n % 10 == 0 ? "" : (n % 10 == 1 ? "en" : ones[n % 10]) + "og") + tens[n / 10]
        case ..<1000: return ones[n / 100] + "hundrede" + (n % 100 == 0 ? "" : " og " + words(n % 100))
        case ..<1_000_000:
            let head = words(n / 1000)
            if n % 1000 == 0 { return head + "tusind" }
            return n >= 100_000 && n % 1000 >= 100 ? head + "tusind" + words(n % 1000) : head + "tusinde og " + words(n % 1000)
        case ..<1_000_000_000:
            let head = (n / 1_000_000 == 1 ? "en" : words(n / 1_000_000)) + " millioner"
            return n % 1_000_000 == 0 ? head : head + " " + words(n % 1_000_000)
        default:
            let head = (n / 1_000_000_000 == 1 ? "en" : words(n / 1_000_000_000)) + " milliarder"
            return n % 1_000_000_000 == 0 ? head : head + " " + words(n % 1_000_000_000)
        }
    }
}

/// Why the Danish voice couldn't read, as the user sees it.
enum PlapreError: LocalizedError {
    case modelNotLoaded
    case incompleteFiles
    case outOfMemory
    case tooLong(characters: Int)
    case modelFailed(code: Int32)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: "The Danish voice model couldn't be loaded. Download the Danish voices again in Settings."
        case .incompleteFiles: "The Danish voice files are incomplete. Download the Danish voices again in Settings."
        case .outOfMemory: "There isn't enough memory for the Danish voice. Close some apps and try again."
        case .tooLong(let characters): "A part of a sentence was too long for the Danish voice (\(characters) characters)."
        case .modelFailed(let code): "The Danish voice stopped (llama.cpp error \(code)). Close some apps and try again."
        }
    }
}

/// GPT-2 style byte-level BPE, the tokenizer Plapre's tokenizer.json describes.
struct BPETokenizer {
    private let vocab: [String: Int]
    private let ranks: [String: Int]
    /// Every byte as the printable character byte-level BPE uses for it.
    private static let byteChars: [Character] = {
        let printable = Array(33...126) + Array(161...172) + Array(174...255)
        var extra = 0
        return (0..<256).map { byte in
            if printable.contains(byte) { return Character(Unicode.Scalar(UInt8(byte))) }
            extra += 1
            return Character(Unicode.Scalar(UInt32(255 + extra))!)
        }
    }()

    init(contentsOf url: URL) throws {
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        guard let model = json?["model"] as? [String: Any],
              var vocab = model["vocab"] as? [String: Int],
              let merges = model["merges"] as? [Any] else { throw PlapreError.incompleteFiles }
        for token in json?["added_tokens"] as? [[String: Any]] ?? [] {
            if let content = token["content"] as? String, let id = token["id"] as? Int { vocab[content] = id }
        }
        self.vocab = vocab
        // Merges are ["a", "b"] pairs in newer files and "a b" strings in older ones.
        ranks = Dictionary(uniqueKeysWithValues: merges.enumerated().map { rank, merge in
            ((merge as? [String])?.joined(separator: " ") ?? merge as? String ?? "", rank)
        })
    }

    func id(_ token: String) -> Int? { vocab[token] }

    func encode(_ text: String) -> [Int] {
        let pieces = text.precomposedStringWithCanonicalMapping
            .matches(of: #/'s|'t|'re|'ve|'m|'ll|'d| ?\p{L}+| ?\p{N}+| ?[^\s\p{L}\p{N}]+|\s+(?!\S)|\s+/#)
        return pieces.flatMap { piece in
            bpe(String(piece.output).utf8.map { Self.byteChars[Int($0)] }.map(String.init)).compactMap { vocab[$0] }
        }
    }

    /// Merges the lowest-ranked adjacent pair until none is left.
    private func bpe(_ symbols: [String]) -> [String] {
        var symbols = symbols
        while symbols.count > 1 {
            let pairs = zip(symbols, symbols.dropFirst()).map { "\($0) \($1)" }
            guard let best = pairs.enumerated().compactMap({ i, pair in ranks[pair].map { (i, $0) } }).min(by: { $0.1 < $1.1 })
            else { break }
            let pair = pairs[best.0]
            var merged: [String] = []
            var i = 0
            while i < symbols.count {
                if i < symbols.count - 1, "\(symbols[i]) \(symbols[i + 1])" == pair {
                    merged.append(symbols[i] + symbols[i + 1])
                    i += 2
                } else {
                    merged.append(symbols[i])
                    i += 1
                }
            }
            symbols = merged
        }
        return symbols
    }
}

/// A Kanade mel spectrogram, ready for the vocoder.
struct PlapreMel: Sendable {
    let values: [Float]
    let shape: [Int]
}

/// HiFT, the slowest step, on its own actor: it runs on the CPU while the
/// language model works out the next piece on the GPU (see `VoicePlayer`).
actor PlapreVocoder {
    private let env: ORTEnv
    private let session: ORTSession

    init(path: String) throws {
        env = try ORTEnv(loggingLevel: .warning)
        session = try ORTSession(env: env, modelPath: path, sessionOptions: nil)
    }

    func wave(_ mel: PlapreMel) throws -> [Float] {
        try Task.checkCancellation()
        let shape = mel.shape.count == 2 ? [1] + mel.shape : mel.shape
        return try ortFloats(ortRun(session, ["mel": ortTensor(mel.values, .float, shape)]))
    }
}

/// llama.cpp's model and context. ggml's Metal backend aborts the process at exit
/// if a model still holds GPU memory, so every session is freed just before exit
/// (VoicePlayer keeps the engine, and so the session, for as long as the app runs).
/// The lock keeps that from landing in the middle of a generation step.
final class LlamaSession: @unchecked Sendable {  // model and context are only touched under `lock`
    private let lock = NSLock()
    private var model: OpaquePointer?
    private var context: OpaquePointer?

    init(model: OpaquePointer, context: OpaquePointer) {
        self.model = model
        self.context = context
        _ = Self.freeAllAtExit
        Self.live.withLock { $0.append(self) }
    }

    /// Runs `body` with the context, unless the process is exiting.
    func with<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        guard let context else { throw CancellationError() }
        return try body(context)
    }

    func free() {
        lock.lock()
        defer { lock.unlock() }
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
        context = nil
        model = nil
    }

    private static let live = OSAllocatedUnfairLock<[LlamaSession]>(initialState: [])
    // atexit handlers run before ggml's own clean-up, which registered after.
    private static let freeAllAtExit: Void = {
        atexit { LlamaSession.live.withLock { $0 }.forEach { $0.free() } }
    }()
}

/// Loads the models once and turns Danish text into audio.
actor PlapreEngine: SpeechEngine {
    private let session: LlamaSession
    private let vocabSize: Int
    private let env: ORTEnv
    private let decoder: ORTSession
    nonisolated let vocoder: PlapreVocoder
    private let tokenizer: BPETokenizer
    private let speakers: [String: (hidden: [Float], raw: [Float])]
    private let ids: [String: Int]
    private let firstAudio: Int, lastAudio: Int

    init() throws {
        let model = Plapre.model
        // llama.cpp's Metal and CPU backends are plugins: in the app's Frameworks,
        // or Homebrew's when run from `swift build`.
        let plugins = [Bundle.main.privateFrameworksPath, "/opt/homebrew/opt/ggml/libexec"].compactMap { $0 }
            .first { FileManager.default.fileExists(atPath: $0 + "/libggml-metal.so") }
        ggml_backend_load_all_from_path(plugins)
        llama_backend_init()
        try Plapre.patchRepeatedTokens(model.path("turbo.gguf"))
        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = 99
        guard let llama = llama_model_load_from_file(model.path("turbo.gguf"), modelParams) else {
            throw PlapreError.modelNotLoaded
        }
        var contextParams = llama_context_default_params()
        // Prompt (text, phonemes) and up to 500 audio tokens.
        contextParams.n_ctx = 1536
        contextParams.n_batch = 512
        contextParams.n_ubatch = 512
        guard let context = llama_init_from_model(llama, contextParams) else {
            llama_model_free(llama)
            throw PlapreError.outOfMemory
        }
        vocabSize = Int(llama_vocab_n_tokens(llama_model_get_vocab(llama)))
        session = LlamaSession(model: llama, context: context)

        env = try ORTEnv(loggingLevel: .warning)
        decoder = try ORTSession(env: env, modelPath: model.path("kanade_decoder.onnx"), sessionOptions: nil)
        vocoder = try PlapreVocoder(path: model.path("hift_vocoder.onnx"))
        let tokenizer = try BPETokenizer(contentsOf: URL(filePath: model.path("tokenizer.json")))
        self.tokenizer = tokenizer
        let json = try Bundle.module.url(forResource: "PlapreSpeakers", withExtension: "json")
            .map { try JSONSerialization.jsonObject(with: Data(contentsOf: $0)) }
        speakers = ((json as? [String: [String: [Double]]]) ?? [:]).mapValues {
            (hidden: ($0["hidden"] ?? []).map(Float.init), raw: ($0["raw"] ?? []).map(Float.init))
        }
        let names = ["<text>", "</text>", "<phonemes>", "</phonemes>", "<audio>", "</audio>", "<eos>", "<audio_0>", "<audio_12799>"]
        ids = Dictionary(uniqueKeysWithValues: names.compactMap { name in tokenizer.id(name).map { (name, $0) } })
        guard ids.count == names.count, !speakers.isEmpty else { throw PlapreError.incompleteFiles }
        firstAudio = ids["<audio_0>"]!
        lastAudio = ids["<audio_12799>"]!
    }

    /// One piece of a sentence: `VoicePlayer` splits long ones with `Plapre.pieces`.
    /// `speed` is applied at playback, so it's unused here.
    func audio(_ text: String, voice: String, speed: Float) async throws -> [Float] {
        try await vocoder.wave(mel(text, voice: voice))
    }

    /// The spectrogram for one piece of a sentence; `vocoder` makes it audio.
    func mel(_ text: String, voice: String) throws -> PlapreMel {
        guard let speaker = speakers[voice] ?? speakers[Plapre.voices[0].0] else { throw PlapreError.incompleteFiles }
        let normalized = Plapre.normalize(text)
        let phones = Plapre.phonemes(normalized).unicodeScalars.compactMap { tokenizer.id("<phone_\($0)>") }
        let prompt = [ids["<text>"]!] + tokenizer.encode(normalized) + [ids["</text>"]!, ids["<phonemes>"]!]
            + phones + [ids["</phonemes>"]!, ids["<audio>"]!]
        // Now and then the model doesn't stop and babbles on. Past the expected length (a
        // second of lead-in, then up to 2 tokens per character) `<eos>` gets likelier with
        // every token, and the hard limit stays under the 500 tokens the Kanade decoder
        // can take. Speech that still runs long is babble: generate it once more.
        let budget = 0.6 + Double(normalized.count) / 14
        var best: (mel: ORTValue, spoken: Int)?
        for _ in 0..<2 {
            try Task.checkCancellation()
            let codes = try generate(
                prompt, speaker: speaker.hidden,
                expected: 25 + 2 * normalized.count, limit: min(500, 30 + 3 * normalized.count)
            )
            guard !codes.isEmpty else { continue }
            let mel = try ortRun(decoder, [
                "content_token_indices": ortTensor(codes.map(Int64.init), .int64, [codes.count]),
                "global_embedding": ortTensor(speaker.raw, .float, [speaker.raw.count]),
            ])
            let spoken = try spokenFrames(mel)
            if best == nil || spoken < best!.spoken { best = (mel, spoken) }
            // Kanade gives 50 mel frames a second.
            if Double(spoken) / 50 <= budget { break }
        }
        guard let mel = best?.mel else { return PlapreMel(values: [], shape: [0, 0]) }
        // The vocoder needs the whole spectrogram: cutting its silent ends changes the voice.
        // `VoicePlayer` trims the silence from the audio instead.
        return try PlapreMel(values: ortFloats(mel), shape: mel.tensorTypeAndShapeInfo().shape.map(\.intValue))
    }

    /// Frames from the first to the last with speech in them.
    private func spokenFrames(_ mel: ORTValue) throws -> Int {
        let shape = try mel.tensorTypeAndShapeInfo().shape.map(\.intValue)
        let (bins, frames) = (shape[shape.count - 2], shape[shape.count - 1])
        let values = try ortFloats(mel)
        let spoken = (0..<frames).filter { frame in (0..<bins).contains { values[$0 * frames + frame] > -3.5 } }
        return (spoken.last ?? 0) - (spoken.first ?? 0)
    }

    /// Kanade token indices for the prompt, stopping at `</audio>` or `<eos>`.
    private func generate(_ prompt: [Int], speaker: [Float], expected: Int, limit: Int) throws -> [Int] {
        try session.with { llama_memory_clear(llama_get_memory($0), true) }
        // The speaker goes in as the first embedding, ahead of the prompt.
        var first = llama_batch_init(1, Int32(speaker.count), 1)
        defer { llama_batch_free(first) }
        first.n_tokens = 1
        speaker.withUnsafeBufferPointer { first.embd.update(from: $0.baseAddress!, count: speaker.count) }
        first.pos[0] = 0
        first.n_seq_id[0] = 1
        first.seq_id[0]![0] = 0
        first.logits[0] = 0
        guard prompt.count <= 512 else { throw PlapreError.tooLong(characters: prompt.count) }
        let code = try session.with { llama_decode($0, first) }
        guard code == 0 else { throw PlapreError.modelFailed(code: code) }

        var batch = llama_batch_init(512, 0, 1)
        defer { llama_batch_free(batch) }
        func put(_ tokens: [Int], from position: Int) throws {
            batch.n_tokens = Int32(tokens.count)
            for (index, token) in tokens.enumerated() {
                batch.token[index] = Int32(token)
                batch.pos[index] = Int32(position + index)
                batch.n_seq_id[index] = 1
                batch.seq_id[index]![0] = 0
                batch.logits[index] = index == tokens.count - 1 ? 1 : 0
            }
            let code = try session.with { llama_decode($0, batch) }
            guard code == 0 else { throw PlapreError.modelFailed(code: code) }
        }
        try put(prompt, from: 1)
        var position = 1 + prompt.count
        var codes: [Int] = []
        let stops: Set = [ids["</audio>"]!, ids["<eos>"]!]
        for count in 0..<limit {
            // Stop and Read Aloud again shouldn't wait for an old sentence to finish.
            try Task.checkCancellation()
            var row = try session.with { context in
                guard let logits = llama_get_logits_ith(context, -1) else { throw PlapreError.modelFailed(code: -1) }
                return Array(UnsafeBufferPointer(start: logits, count: vocabSize))
            }
            if count > expected { row[ids["<eos>"]!] += Float(count - expected) }
            let next = Self.sample(row)
            if stops.contains(next) { break }
            if (firstAudio...lastAudio).contains(next) { codes.append(next - firstAudio) }
            try put([next], from: position)
            position += 1
        }
        return codes
    }

    /// Top-k 50 and top-p 0.95 as plapre does, but temperature 0.6, not its 0.8:
    /// clearer pronunciation in a listening test (14.10.2026).
    static func sample(_ logits: [Float]) -> Int {
        var top: [(id: Int, logit: Float)] = []
        for (id, logit) in logits.enumerated() where top.count < 50 || logit > top[top.count - 1].logit {
            top.insert((id, logit), at: top.firstIndex { $0.logit < logit } ?? top.count)
            if top.count > 50 { top.removeLast() }
        }
        let weights = top.map { exp(($0.logit - top[0].logit) / 0.6) }
        let total = weights.reduce(0, +)
        var cumulative: Float = 0
        let kept = weights.prefix { weight in
            defer { cumulative += weight / total }
            return cumulative < 0.95
        }
        var pick = Float.random(in: 0..<kept.reduce(0, +))
        for (index, weight) in kept.enumerated() {
            pick -= weight
            if pick < 0 { return top[index].id }
        }
        return top[kept.count - 1].id
    }

}

private func ortRun(_ session: ORTSession, _ inputs: [String: ORTValue]) throws -> ORTValue {
    let name = try session.outputNames()[0]
    guard let output = try session.run(withInputs: inputs, outputNames: [name], runOptions: nil)[name] else {
        throw PlapreError.incompleteFiles
    }
    return output
}

private func ortTensor<T>(_ values: [T], _ type: ORTTensorElementDataType, _ shape: [Int]) throws -> ORTValue {
    try ORTValue(
        tensorData: NSMutableData(data: values.withUnsafeBytes { Data($0) }),
        elementType: type, shape: shape.map { NSNumber(value: $0) }
    )
}

private func ortFloats(_ value: ORTValue) throws -> [Float] {
    try (value.tensorData() as Data).withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
}
#endif
