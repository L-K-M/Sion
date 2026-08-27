import Foundation
import XCTest

@testable import SionCore

final class DocumentHistoryTests: XCTestCase {
  private let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

  func testDuplicateSceneIsNotRetainedTwice() {
    let scene = Data("scene".utf8)
    let history = DocumentHistory()
      .appending(sceneData: scene, at: referenceDate, intent: .manual)
      .appending(sceneData: scene, at: referenceDate.addingTimeInterval(60), intent: .manual)

    XCTAssertEqual(history.revisions.count, 1)
  }

  func testAutosaveSnapshotsAreRateLimited() {
    let history = DocumentHistory()
      .appending(sceneData: Data("one".utf8), at: referenceDate, intent: .autosave)
      .appending(
        sceneData: Data("two".utf8),
        at: referenceDate.addingTimeInterval(60),
        intent: .autosave
      )

    XCTAssertEqual(history.revisions.map(\.sceneData), [Data("one".utf8)])
  }

  func testFutureRevisionDoesNotSuppressAutosave() {
    let futureData = Data("future".utf8)
    let currentData = Data("current".utf8)
    let throttledData = Data("throttled".utf8)
    let history = DocumentHistory()
      .appending(
        sceneData: futureData,
        at: referenceDate.addingTimeInterval(DocumentHistory.autosaveCheckpointInterval),
        intent: .manual
      )
      .appending(sceneData: currentData, at: referenceDate, intent: .autosave)
      .appending(
        sceneData: throttledData,
        at: referenceDate.addingTimeInterval(DocumentHistory.autosaveCheckpointInterval / 2),
        intent: .autosave
      )

    XCTAssertEqual(history.revisions.map(\.sceneData), [futureData, currentData])
  }

  func testAutosavesAtSameDateAreRateLimited() {
    let history = DocumentHistory()
      .appending(sceneData: Data("one".utf8), at: referenceDate, intent: .autosave)
      .appending(sceneData: Data("two".utf8), at: referenceDate, intent: .autosave)

    XCTAssertEqual(history.revisions.map(\.sceneData), [Data("one".utf8)])
  }

  func testNewestRevisionsSurviveThinning() {
    let revisions = (0..<200).map { index in
      let data = Data("scene-\(index)".utf8)
      return HistoryRevision(
        identifier: SHA256.hexDigest(data),
        savedAt: referenceDate.addingTimeInterval(TimeInterval(-index * 60)),
        intent: .manual,
        sceneData: data
      )
    }

    let history = DocumentHistory(revisions: revisions)

    XCTAssertLessThanOrEqual(history.revisions.count, DocumentHistory.maximumRevisionCount)
    XCTAssertEqual(
      Array(history.revisions.prefix(DocumentHistory.alwaysKeepNewestCount)).map(\.sceneData),
      Array(revisions.prefix(DocumentHistory.alwaysKeepNewestCount)).map(\.sceneData)
    )
  }
}
