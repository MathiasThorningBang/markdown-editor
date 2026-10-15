import AVFoundation
import NaturalLanguage

/// Reads a markdown document aloud one sentence at a time, so the editor can
/// highlight it, in the document's language: English with a Kokoro voice and
/// Danish with a Plapre voice when built in and downloaded, otherwise with the
/// basic system voice for the language.
@MainActor
final class ReadAloud: NSObject, ObservableObject {
    static let shared = ReadAloud()

    enum State { case idle, speaking, paused }
    @Published private(set) var state = State.idle

    struct Sentence: Equatable {
        let text: String
        /// Last sentence of a heading, paragraph or list item: a longer pause follows.
        let endsBlock: Bool
    }

    /// English voice picked in Settings; empty means automatic.
    @Published var voiceID: String {
        didSet { UserDefaults.standard.set(voiceID, forKey: "readAloudVoice") }
    }
    /// Danish voice picked in Settings; empty means automatic.
    @Published var danishVoiceID: String {
        didSet { UserDefaults.standard.set(danishVoiceID, forKey: "readAloudDanishVoice") }
    }
    /// Speaking speed relative to the system's default rate.
    @Published var speed: Double {
        didSet { UserDefaults.standard.set(speed, forKey: "readAloudSpeed") }
    }

    /// Called with each sentence as it starts, and with nil when reading ends.
    var onSentence: ((String?) -> Void)?
    /// Shown to the user when reading fails.
    var onError: ((String) -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    /// The queue's last utterance; when it finishes, reading is done.
    private var lastUtterance: ObjectIdentifier?
    #if Kokoro
    private let player = VoicePlayer()
    #endif
    private var usingPlayer = false

    override private init() {
        let saved = UserDefaults.standard.string(forKey: "readAloudVoice") ?? ""
        // Only Kokoro voices can be picked; an older pick of a system voice becomes automatic.
        voiceID = saved.hasPrefix("kokoro:") ? saved : ""
        let danish = UserDefaults.standard.string(forKey: "readAloudDanishVoice") ?? ""
        #if Kokoro
        // A voice of an earlier Danish model (Pico's Ask and Tor) becomes automatic.
        danishVoiceID = Plapre.voices.contains { "plapre:" + $0.0 == danish } ? danish : ""
        #else
        danishVoiceID = danish
        #endif
        speed = UserDefaults.standard.object(forKey: "readAloudSpeed") as? Double ?? 1
        super.init()
        synthesizer.delegate = self
    }

    /// "da" for a Danish document, otherwise "en".
    nonisolated static func language(of text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.english, .danish]
        // The opening is enough to tell, and keeps this cheap for the toolbar's help text.
        recognizer.processString(String(text.prefix(2000)))
        return recognizer.dominantLanguage == .danish ? "da" : "en"
    }

    /// The system voice for the language, used without Kokoro: Daniel or Sara,
    /// which ship with macOS. Apps can't use the Siri voices.
    static func systemVoice(for language: String) -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice(language: language == "da" ? "da-DK" : "en-GB")
    }

    /// The Kokoro voice for an English document, if downloaded: the picked one,
    /// or Daniel when the voice is automatic. Kokoro can't speak Danish.
    func kokoroVoice(for language: String) -> String? {
        #if Kokoro
        guard language == "en", ModelDownload.kokoro.isInstalled else { return nil }
        if voiceID.isEmpty { return Kokoro.voices[0].0 }
        return voiceID.hasPrefix("kokoro:") ? String(voiceID.dropFirst("kokoro:".count)) : nil
        #else
        return nil
        #endif
    }

    /// The Plapre voice for a Danish document, if downloaded: the picked one,
    /// or Ask when the voice is automatic.
    func plapreVoice(for language: String) -> String? {
        #if Kokoro
        guard language == "da", ModelDownload.plapre.isInstalled else { return nil }
        return danishVoiceID.hasPrefix("plapre:") ? String(danishVoiceID.dropFirst("plapre:".count)) : Plapre.voices[0].0
        #else
        return nil
        #endif
    }

    func voiceName(for language: String) -> String {
        #if Kokoro
        if let name = kokoroVoice(for: language).flatMap(Kokoro.name) { return name }
        if let name = plapreVoice(for: language).flatMap(Plapre.name) { return name }
        #endif
        return Self.systemVoice(for: language)?.name ?? "the system voice"
    }

    /// The sentences `start` reads, in order.
    nonisolated static func sentences(of markdown: String) -> [Sentence] {
        sentences(blocks(markdown, language: language(of: markdown)))
    }

    /// Reads from sentence number `first` on (see `sentences(of:)`), e.g. where the cursor is.
    func start(_ markdown: String, from first: Int = 0) {
        stop()
        let language = Self.language(of: markdown)
        let all = Self.sentences(Self.blocks(markdown, language: language))
        let sentences = Array(all.dropFirst(all.indices.contains(first) ? first : 0))
        guard !sentences.isEmpty else { return }
        state = .speaking
        #if Kokoro
        let neural = kokoroVoice(for: language).map { (VoicePlayer.Kind.kokoro, $0) }
            ?? plapreVoice(for: language).map { (VoicePlayer.Kind.plapre, $0) }
        if let (kind, voice) = neural {
            usingPlayer = true
            player.play(sentences, with: kind, voice: voice, speed: Float(speed)) { [weak self] sentence in
                self?.onSentence?(sentence)
            } onFinish: { [weak self] error in
                self?.stop()
                if let error { self?.onError?("Couldn't read aloud: \(error.localizedDescription)") }
            }
            return
        }
        #endif
        let voice = Self.systemVoice(for: language)
        let rate = min(max(AVSpeechUtteranceDefaultSpeechRate * Float(speed), AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
        let utterances = sentences.map { sentence in
            let utterance = AVSpeechUtterance(string: sentence.text)
            utterance.voice = voice
            utterance.rate = rate
            // Tuned by ear: a touch lower than the default.
            utterance.pitchMultiplier = 0.92
            utterance.postUtteranceDelay = sentence.endsBlock ? 0.25 : 0.05
            return utterance
        }
        lastUtterance = utterances.last.map(ObjectIdentifier.init)
        utterances.forEach(synthesizer.speak)
    }

    func pause() {
        if usingPlayer {
            #if Kokoro
            player.pause()
            #endif
            state = .paused
        } else {
            // Takes effect asynchronously, so state follows the delegate.
            synthesizer.pauseSpeaking(at: .immediate)
        }
    }

    func resume() {
        if usingPlayer {
            #if Kokoro
            player.resume()
            #endif
            state = .speaking
        } else {
            synthesizer.continueSpeaking()
        }
    }

    func stop() {
        #if Kokoro
        player.stop()
        #endif
        usingPlayer = false
        lastUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
        if state != .idle { onSentence?(nil) }
        state = .idle
    }

    /// Blocks split into sentences.
    nonisolated static func sentences(_ blocks: [String]) -> [Sentence] {
        let tokenizer = NLTokenizer(unit: .sentence)
        return blocks.flatMap { block in
            tokenizer.string = block
            var parts: [String] = []
            var number = ""
            for range in tokenizer.tokens(for: block.startIndex..<block.endIndex) {
                let part = block[range].trimmingCharacters(in: .whitespacesAndNewlines)
                // A list number like "1." comes out as a sentence of its own; keep it with its item.
                if !part.contains(where: \.isLetter) && parts.isEmpty && number.isEmpty {
                    number = part + " "
                } else if !part.isEmpty {
                    parts.append(number + part)
                    number = ""
                }
            }
            if !number.isEmpty { parts.append(number) }
            return parts.enumerated().map { Sentence(text: $1, endsBlock: $0 == parts.count - 1) }
        }
    }

    /// Markdown as speakable blocks: markup stripped, code skipped, table
    /// rows read cell by cell.
    nonisolated static func blocks(_ markdown: String, language: String = "en") -> [String] {
        var blocks: [String] = []
        var paragraph: [String] = []
        var inCode = false
        func flush() {
            let text = speakable(paragraph.joined(separator: " "))
            if !text.isEmpty { blocks.append(text) }
            paragraph = []
        }
        for raw in markdown.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                flush()
                if !inCode { blocks.append(language == "da" ? "Kodeblok sprunget over." : "Code block skipped.") }
                inCode.toggle()
            } else if inCode {
                continue
            } else if line.isEmpty || line.wholeMatch(of: #/[-*_\s]{3,}/#) != nil {
                flush()
            } else if line.hasPrefix("|") {
                flush()
                // The |---|:---:| separator row has no words to read.
                guard line.contains(where: { $0.isLetter || $0.isNumber }) else { continue }
                // Each cell is a block of its own: a pause between cells, and highlighted one by one.
                for cell in line.split(separator: "|") {
                    paragraph = [String(cell)]
                    flush()
                }
            } else if let item = line.firstMatch(of: #/^(#{1,6}|[-*+]|\d+[.)])\s+(.*)/#) {
                // Headings and list items are blocks of their own, for a pause after each.
                flush()
                let number = item.1.first?.isNumber == true ? "\(item.1.dropLast()). " : ""
                paragraph = [number + item.2]
                // A heading is one line; a list item goes on over the lines below it.
                if item.1.first == "#" { flush() }
            } else {
                paragraph.append(line.replacing(#/^>\s?/#, with: ""))
            }
        }
        flush()
        return blocks
    }

    /// Inline markup to plain text: emphasis, code spans and links keep only
    /// their text; ChatGPT citation marks and emoji go.
    nonisolated private static func speakable(_ text: String) -> String {
        let plain = (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )).map { String($0.characters) } ?? text
        return plain
            .replacing(#/\s*(【[^】]*】|\[\^?\d+\])/#, with: "")
            .filter { !($0.unicodeScalars.first?.properties.isEmojiPresentation ?? false) }
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

extension ReadAloud: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let text = utterance.speechString
        Task { @MainActor in
            if self.state != .idle { self.onSentence?(text) }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in
            if id == self.lastUtterance { self.stop() }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if self.state == .speaking { self.state = .paused }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if self.state == .paused { self.state = .speaking }
        }
    }
}
