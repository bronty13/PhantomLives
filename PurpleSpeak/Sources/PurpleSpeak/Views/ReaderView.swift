import SwiftUI

/// The reading surface. Renders the document a paragraph at a time so the
/// active paragraph can be highlighted (word + sentence, synced to the
/// synthesizer) and auto-scrolled into view without re-laying-out the whole
/// document on every word callback.
struct ReaderView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tts: AVSpeechTTSEngine
    @EnvironmentObject var settings: SettingsStore

    /// Paragraph slices of the current text, recomputed when the text changes.
    @State private var paragraphs: [Para] = []

    struct Para: Identifiable {
        let id: Int
        let range: NSRange      // location/length in the full document
        let text: String
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: settings.settings.readerLineSpacing + 6) {
                        ForEach(paragraphs) { para in
                            paragraphView(para)
                                .id(para.id)
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 28)
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .onChange(of: tts.spokenWordRange?.location) { _, _ in
                    if let idx = activeParagraphIndex() {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(idx, anchor: .center)
                        }
                    }
                }
            }
            PlaybackBar()
        }
        .onAppear { rebuildParagraphs() }
        .onChange(of: appState.currentText) { _, _ in rebuildParagraphs() }
    }

    @ViewBuilder
    private func paragraphView(_ para: Para) -> some View {
        let active = isActive(para)
        Text(active ? highlighted(para) : AttributedString(para.text))
            .font(.system(size: settings.settings.readerFontSize))
            .lineSpacing(settings.settings.readerLineSpacing)
            .textSelection(.enabled)
            .opacity(dimmed(para) ? 0.35 : 1.0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { appState.startReading(from: para.range.location) }
    }

    /// Build an AttributedString for the active paragraph, painting the
    /// enclosing sentence faintly and the current word boldly — the synced
    /// highlight that is the app's signature feature.
    private func highlighted(_ para: Para) -> AttributedString {
        var attr = AttributedString(para.text)
        if settings.settings.highlightSentence,
           let sentence = tts.spokenSentenceRange,
           let local = localRange(sentence, in: para) {
            paint(&attr, in: para.text, nsRange: local,
                  background: Color.purple.opacity(0.14))
        }
        if let word = tts.spokenWordRange,
           let local = localRange(word, in: para) {
            paint(&attr, in: para.text, nsRange: local,
                  background: Color.yellow.opacity(0.85), bold: true)
        }
        return attr
    }

    private func paint(_ attr: inout AttributedString, in source: String,
                       nsRange: NSRange, background: Color, bold: Bool = false) {
        guard let strRange = Range(nsRange, in: source),
              let lo = AttributedString.Index(strRange.lowerBound, within: attr),
              let hi = AttributedString.Index(strRange.upperBound, within: attr),
              lo < hi else { return }
        attr[lo..<hi].backgroundColor = background
        if bold {
            attr[lo..<hi].font = .system(size: settings.settings.readerFontSize, weight: .bold)
        }
    }

    /// Convert a whole-document NSRange to a paragraph-local NSRange (the
    /// intersection), or nil if it doesn't fall in this paragraph.
    private func localRange(_ docRange: NSRange, in para: Para) -> NSRange? {
        let inter = NSIntersectionRange(docRange, para.range)
        guard inter.length > 0 else { return nil }
        return NSRange(location: inter.location - para.range.location, length: inter.length)
    }

    private func isActive(_ para: Para) -> Bool {
        guard let loc = tts.spokenWordRange?.location else { return false }
        return NSLocationInRange(loc, para.range)
    }

    /// Line-focus mode: dim every paragraph except the active one.
    private func dimmed(_ para: Para) -> Bool {
        settings.settings.lineFocusEnabled && tts.isSpeaking && !isActive(para)
    }

    private func activeParagraphIndex() -> Int? {
        guard let loc = tts.spokenWordRange?.location else { return nil }
        return paragraphs.first { NSLocationInRange(loc, $0.range) }?.id
    }

    private func rebuildParagraphs() {
        let text = appState.currentText
        let ns = text as NSString
        var result: [Para] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length),
                               options: .byParagraphs) { sub, range, _, _ in
            let s = sub ?? ""
            if !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(Para(id: result.count, range: range, text: s))
            }
        }
        paragraphs = result
    }
}
