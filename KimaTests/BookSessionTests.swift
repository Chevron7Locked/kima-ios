import XCTest
@testable import Kima

/// An audiobook's timeline and the file loaded in it: which file a book time lands in, the book
/// time the engine is at, and the file after the loaded one. Pure values; no player.
final class BookSessionTests: XCTestCase {

    /// Three files: 0–100, 100–250, 250–300.
    private var book: BookSession {
        BookSession(bookId: "b", totalDuration: 300, files: [
            AudiobookTrack(index: 1, startOffset: 0, duration: 100),
            AudiobookTrack(index: 2, startOffset: 100, duration: 150),
            AudiobookTrack(index: 3, startOffset: 250, duration: 50)])
    }

    func testANewSessionHasNoFileLoaded() {
        XCTAssertNil(book.loadedFile)
        XCTAssertEqual(book.bookTime(engineTime: 12), 12, "no file loaded: the engine's time stands")
    }

    func testLoadingABookTimeLoadsItsFileAtTheTimeWithinIt() {
        var s = book
        let target = s.markLoaded(at: 130)
        XCTAssertEqual(target.file.index, 2)
        XCTAssertEqual(target.fileTime, 30)
        XCTAssertFalse(target.isSameFile, "nothing was loaded before")
        XCTAssertEqual(s.loadedFile?.index, 2)
    }

    func testLoadingWithinTheLoadedFileSaysSo() {
        var s = book
        s.markLoaded(at: 130)
        let target = s.markLoaded(at: 240)
        XCTAssertEqual(target.file.index, 2)
        XCTAssertEqual(target.fileTime, 140)
        XCTAssertTrue(target.isSameFile)
    }

    func testLoadingAnotherFileMovesTheCursor() {
        var s = book
        s.markLoaded(at: 130)
        let target = s.markLoaded(at: 260)
        XCTAssertFalse(target.isSameFile)
        XCTAssertEqual(s.loadedFile?.index, 3)
    }

    func testABookTimePastEitherEndIsClamped() {
        var s = book
        XCTAssertEqual(s.markLoaded(at: -5).fileTime, 0)
        XCTAssertEqual(s.loadedFile?.index, 1)
        let end = s.markLoaded(at: 999)
        XCTAssertEqual(end.file.index, 3)
        XCTAssertEqual(end.fileTime, 50)
    }

    func testTheEnginesTimeIsReadAgainstTheLoadedFile() {
        var s = book
        s.markLoaded(at: 260)
        XCTAssertEqual(s.bookTime(engineTime: 20), 270)
    }

    func testAdvancingLoadsTheNextFileAndStopsAfterTheLast() {
        var s = book
        s.markLoaded(at: 50)
        XCTAssertEqual(s.fileAfterLoaded?.index, 2)
        XCTAssertEqual(s.advanceFile()?.index, 2)
        XCTAssertEqual(s.loadedFile?.index, 2)
        XCTAssertEqual(s.advanceFile()?.index, 3)
        XCTAssertNil(s.fileAfterLoaded, "the last file has nothing after it")
        XCTAssertNil(s.advanceFile(), "the book is finished")
        XCTAssertEqual(s.loadedFile?.index, 3, "the last file stays loaded")
    }

    func testWithNoFileLoadedThereIsNothingToAdvanceTo() {
        var s = book
        XCTAssertNil(s.fileAfterLoaded)
        XCTAssertNil(s.advanceFile())
    }

    func testASessionCanStartWithAFileLoaded() {
        let s = BookSession(bookId: "b", totalDuration: 300, files: book.files, loadedFileIndex: 2)
        XCTAssertEqual(s.bookTime(engineTime: 5), 105)
    }
}
