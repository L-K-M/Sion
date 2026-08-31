import AppKit
import XCTest

@testable import SionKit

@MainActor
final class SionEditorFeedbackPresenterTests: XCTestCase {
  func testFeedbackIsVisibleAndAnnounced() throws {
    _ = NSApplication.shared
    let host = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
    var announcements: [String] = []
    let presenter = SionEditorFeedbackPresenter(
      announcementHandler: { _, message in announcements.append(message) }
    )
    let feedback = SionEditorFeedback.mermaidSourcePreserved(
      .omissions(firstLine: 3, count: 2)
    )
    presenter.attach(to: host)

    presenter.handle(.show(feedback))
    host.layoutSubtreeIfNeeded()

    let messageLabel = try XCTUnwrap(
      host.descendants.compactMap { $0 as? NSTextField }.first {
        $0.stringValue == feedback.message
      }
    )
    XCTAssertFalse(messageLabel.frame.isEmpty)
    XCTAssertEqual(announcements, [feedback.message])
  }

  func testResolutionRemovesMatchingFeedbackWithoutAnnouncing() {
    _ = NSApplication.shared
    let host = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
    var announcements: [String] = []
    let presenter = SionEditorFeedbackPresenter(
      announcementHandler: { _, message in announcements.append(message) }
    )
    let feedback = SionEditorFeedback.mermaidSourcePreserved(
      .omissions(firstLine: 3, count: 1)
    )
    presenter.attach(to: host)
    presenter.handle(.show(feedback))

    presenter.handle(.clear(.mermaidSource))

    XCTAssertFalse(
      host.descendants.compactMap { $0 as? NSTextField }.contains {
        $0.stringValue == feedback.message
      }
    )
    XCTAssertEqual(announcements, [feedback.message])
  }

  func testCommandFailureIsVisibleAndAnnounced() {
    _ = NSApplication.shared
    let host = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
    var announcements: [String] = []
    let presenter = SionEditorFeedbackPresenter(
      announcementHandler: { _, message in announcements.append(message) }
    )
    let feedback = SionEditorFeedback.commandFailed(.pasteMermaid)
    presenter.attach(to: host)

    presenter.handle(.show(feedback))

    XCTAssertTrue(
      host.descendants.compactMap { $0 as? NSTextField }.contains {
        $0.stringValue == feedback.message
      }
    )
    XCTAssertEqual(announcements, [feedback.message])
  }

  func testDismissButtonRemovesFeedback() throws {
    _ = NSApplication.shared
    let host = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
    let presenter = SionEditorFeedbackPresenter(announcementHandler: { _, _ in })
    let feedback = SionEditorFeedback.mermaidSourcePreserved(.noSupportedElements)
    presenter.attach(to: host)
    presenter.handle(.show(feedback))

    let dismissButton = try XCTUnwrap(
      host.descendants.compactMap { $0 as? NSButton }.first {
        $0.toolTip == FeedbackPresenterTestCopy.dismiss
      }
    )
    dismissButton.performClick(nil)

    XCTAssertFalse(
      host.descendants.compactMap { $0 as? NSTextField }.contains {
        $0.stringValue == feedback.message
      }
    )
  }
}

private enum FeedbackPresenterTestCopy {
  static let dismiss = "Dismiss notification"
}

extension NSView {
  fileprivate var descendants: [NSView] {
    subviews + subviews.flatMap(\.descendants)
  }
}
