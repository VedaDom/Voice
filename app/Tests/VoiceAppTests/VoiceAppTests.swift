import XCTest
@testable import VoiceApp

final class VersionCompareTests: XCTestCase {
    func testNewerVersions() {
        XCTAssertTrue(UpdateChecker.isNewer("0.2.0", than: "0.1.0"))
        XCTAssertTrue(UpdateChecker.isNewer("1.0.0", than: "0.9.9"))
        XCTAssertTrue(UpdateChecker.isNewer("0.1.1", than: "0.1.0"))
        XCTAssertTrue(UpdateChecker.isNewer("0.1.0.1", than: "0.1.0"))
    }

    func testNotNewerVersions() {
        XCTAssertFalse(UpdateChecker.isNewer("0.1.0", than: "0.1.0"))
        XCTAssertFalse(UpdateChecker.isNewer("0.0.9", than: "0.1.0"))
        XCTAssertFalse(UpdateChecker.isNewer("0.1", than: "0.1.0"))
    }
}

final class NotePresentationTests: XCTestCase {
    func testTitleIsFirstWordsWithoutTrailingPunctuation() {
        let note = Note(text: "Send the Q3 report to finance, before noon today please.",
                        wav: "", date: Date(), duration: 10)
        XCTAssertEqual(note.title, "Send the Q3 report to finance")
    }

    func testEmptyTextFallsBackToPlaceholderTitle() {
        let note = Note(text: "", wav: "", date: Date(), duration: 0)
        XCTAssertEqual(note.title, "Voice note")
    }

    func testParagraphsGroupSentencesInPairs() {
        let note = Note(text: "One. Two. Three. Four. Five.",
                        wav: "", date: Date(), duration: 5)
        XCTAssertEqual(note.paragraphs.count, 3)
        XCTAssertEqual(note.paragraphs[0], "One.  Two.")
        XCTAssertEqual(note.paragraphs[2], "Five.")
    }

    func testDurationLabel() {
        let note = Note(text: "x", wav: "", date: Date(), duration: 83)
        XCTAssertEqual(note.durationLabel, "1:23")
    }
}

@MainActor
final class PostProcessTests: XCTestCase {
    private func withSettings(_ body: (SettingsStore) -> Void) {
        let s = SettingsStore.shared
        let savedPunct = s.smartPunctuation
        let savedFillers = s.removeFillers
        let savedReplacements = s.vocabulary.replacements
        defer {
            s.smartPunctuation = savedPunct
            s.removeFillers = savedFillers
            s.vocabulary.replacements = savedReplacements
        }
        body(s)
    }

    func testFillerRemoval() {
        withSettings { s in
            s.smartPunctuation = true
            s.removeFillers = true
            let out = s.postProcess("So um I think uh we should, erm, ship it.")
            XCTAssertFalse(out.lowercased().contains("um"))
            XCTAssertFalse(out.lowercased().contains("uh"))
            XCTAssertTrue(out.contains("ship it"))
        }
    }

    func testPunctuationStripWhenSmartPunctuationOff() {
        withSettings { s in
            s.smartPunctuation = false
            s.removeFillers = false
            let out = s.postProcess("Hello, world. How are you?")
            XCTAssertFalse(out.contains(","))
            XCTAssertFalse(out.contains("."))
            XCTAssertFalse(out.contains("?"))
        }
    }

    func testReplacementsApply() {
        withSettings { s in
            s.smartPunctuation = true
            s.removeFillers = false
            s.vocabulary.replacements = [.init(spoken: "voice dot app", written: "voice.app")]
            let out = s.postProcess("Check out voice dot app today.")
            XCTAssertTrue(out.contains("voice.app"))
        }
    }
}
