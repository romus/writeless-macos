import Foundation
import Testing

@testable import WritelessCore

@Suite("Sentence splitter")
struct SentenceSplitterTests {
    @Test("Punctuated text is cut into sentences")
    func plain() {
        let sentences = SentenceSplitter.split("Привет. Как дела? Всё хорошо! Ну и ладно.")
        #expect(sentences == ["Привет.", "Как дела?", "Всё хорошо!", "Ну и ладно."])
        #expect(SentenceSplitter.split("Hey, quick update. We shipped it. Talk soon.").count == 3)
    }

    @Test("Abbreviations do not end a sentence")
    func abbreviations() {
        #expect(SentenceSplitter.split("Мы это доделали, т.е. закончили совсем. Потом ушли домой.").count == 2)
        #expect(SentenceSplitter.split("Нужны логи, алерты и т.д. по всем сервисам. Потом посмотрим.").count == 2)
        #expect(SentenceSplitter.split("We tried the build, e.g. the nightly one. It worked.").count == 2)
    }

    @Test("Decimals and quotes survive")
    func decimalsAndQuotes() {
        let sentences = SentenceSplitter.split("Это заняло 3.5 часа. «Нормально», сказал он. Потом ушли.")
        #expect(sentences == ["Это заняло 3.5 часа.", "«Нормально», сказал он.", "Потом ушли."])
        // The tokenizer keeps a sentence that begins with a digit attached to
        // the one before ("он. 2 дня"); that costs nothing for paragraphs, so
        // it is left alone.
        #expect(SentenceSplitter.split("Сказал он. 2 дня осталось.").count == 1)
    }

    @Test("Empty and blank text give nothing")
    func empty() {
        #expect(SentenceSplitter.split("").isEmpty)
        #expect(SentenceSplitter.split("   \n ").isEmpty)
    }
}

@Suite("Paragraph windows")
struct ParagraphWindowsTests {
    @Test("Short lists are one window")
    func single() {
        #expect(ParagraphWindows.make(count: 0).isEmpty)
        #expect(ParagraphWindows.make(count: 1) == [0..<1])
        #expect(ParagraphWindows.make(count: 14) == [0..<14])
    }

    @Test("Long lists are cut into windows of even size")
    func balanced() {
        #expect(ParagraphWindows.make(count: 15) == [0..<8, 8..<15])
        #expect(ParagraphWindows.make(count: 20) == [0..<10, 10..<20])
        #expect(ParagraphWindows.make(count: 48) == [0..<12, 12..<24, 24..<36, 36..<48])
        #expect(ParagraphWindows.make(count: 7, maxSentences: 3) == [0..<3, 3..<5, 5..<7])
    }
}

@Suite("Paragraph layout")
struct ParagraphLayoutTests {
    // Seven words each, so any two of them clear the twelve-word minimum.
    private let sentences = [
        "Первое предложение про встречу с заказчиком вчера вечером.",
        "Второе предложение про сроки второго этапа проекта.",
        "Третье предложение уже про команду и отпуск Саши.",
        "Четвёртое предложение про мобильное приложение и Лену.",
        "Пятое предложение про инфраструктуру и упавший стейджинг.",
        "Шестое предложение про ротацию логов и алерты.",
    ]

    @Test("Paragraphs begin at the sentences the model named")
    func basic() {
        let text = ParagraphLayout.apply(starts: [1, 3, 5], to: sentences)
        #expect(text == [
            sentences[0] + " " + sentences[1],
            sentences[2] + " " + sentences[3],
            sentences[4] + " " + sentences[5],
        ].joined(separator: "\n\n"))
    }

    @Test("Garbage from the model is ignored and 1 is implied")
    func garbage() {
        let text = ParagraphLayout.apply(starts: [0, 99, 5, 5, -3, 3], to: sentences)
        #expect(text.components(separatedBy: "\n\n").count == 3)
        #expect(text.hasPrefix(sentences[0]))
        #expect(ParagraphLayout.apply(starts: [], to: sentences) == sentences.joined(separator: " "))
        #expect(ParagraphLayout.apply(starts: [1], to: []).isEmpty)
    }

    @Test("Every word comes back, in order")
    func fidelity() {
        let text = ParagraphLayout.apply(starts: [1, 2, 4], to: sentences)
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        #expect(words == sentences.joined(separator: " ").split(separator: " ").map(String.init))
    }

    @Test("Short paragraphs are glued to the one before")
    func shortParagraphs() {
        let short = ["Так, по поводу встречи.", "Всё прошло нормально.", "Ещё спрашивали про интеграцию.", "Ну и последнее.", "На связи."]
        #expect(ParagraphLayout.apply(starts: [1, 3, 4, 5], to: short) == short.joined(separator: " "))

        // A long paragraph after a short opener absorbs it.
        let opener = ["Теперь по команде."] + Array(sentences[2...])
        let text = ParagraphLayout.apply(starts: [1, 2, 4], to: opener)
        #expect(text.components(separatedBy: "\n\n").count == 2)
        #expect(text.hasPrefix("Теперь по команде. " + sentences[2]))
    }

    @Test("Too little text is not worth a request")
    func threshold() {
        #expect(!ParagraphLayout.isWorthSplitting(Array(sentences[0..<2])))
        #expect(!ParagraphLayout.isWorthSplitting(["Раз.", "Два.", "Три."]))
        #expect(ParagraphLayout.isWorthSplitting(sentences))
        #expect(ParagraphLayout.wordCount(["a b", "c  d e"]) == 5)
    }
}

@Suite("Paragraphs availability")
struct ParagraphsAvailabilityTests {
    @Test("Only an eligible Mac shows the row, only a ready one can toggle")
    func flags() {
        #expect(ParagraphsAvailability.available.canToggle)
        #expect(!ParagraphsAvailability.turnedOff.canToggle)
        #expect(!ParagraphsAvailability.downloading.canToggle)
        #expect(ParagraphsAvailability.turnedOff.showsRow)
        #expect(ParagraphsAvailability.downloading.showsRow)
        #expect(!ParagraphsAvailability.unsupported.showsRow)
    }

    @Test("Subtitles follow the design")
    func copy() {
        #expect(ParagraphsAvailability.available.subtitle(isOn: true) == "New paragraph when the topic changes")
        #expect(ParagraphsAvailability.available.subtitle(isOn: false) == "One continuous block")
        #expect(ParagraphsAvailability.turnedOff.subtitle(isOn: true) == "Turn on Apple Intelligence in System Settings")
        #expect(ParagraphsAvailability.downloading.subtitle(isOn: false) == "Apple Intelligence is still downloading")
        #expect(ParagraphsAvailability.turnedOff.actionTitle == "Open System Settings…")
        #expect(ParagraphsAvailability.available.actionTitle == nil)
        #expect(ParagraphsAvailability.downloading.actionTitle == nil)
    }
}
