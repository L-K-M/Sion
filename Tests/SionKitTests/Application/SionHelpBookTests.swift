import Foundation
import XCTest

final class SionHelpBookTests: XCTestCase {
  func testHelpBookMetadataResolvesLocalizedStartPage() throws {
    let appInfo = try propertyList(at: resourcesDirectory.appendingPathComponent("Info.plist"))
    let folder = try XCTUnwrap(appInfo[HelpBookContract.folderKey] as? String)
    let bookName = try XCTUnwrap(appInfo[HelpBookContract.nameKey] as? String)
    let helpBook = resourcesDirectory.appendingPathComponent(folder, isDirectory: true)
    let contents = helpBook.appendingPathComponent("Contents", isDirectory: true)
    let helpInfo = try propertyList(at: contents.appendingPathComponent("Info.plist"))

    XCTAssertEqual(folder, HelpBookContract.folderName)
    XCTAssertEqual(bookName, HelpBookContract.identifier)
    XCTAssertEqual(helpInfo[HelpBookContract.bundleIdentifierKey] as? String, bookName)
    XCTAssertEqual(
      helpInfo[HelpBookContract.developmentRegionKey] as? String,
      HelpBookContract.localization
    )
    XCTAssertEqual(helpInfo[HelpBookContract.titleKey] as? String, HelpBookContract.title)
    XCTAssertEqual(
      helpInfo[HelpBookContract.accessPathKey] as? String,
      HelpBookContract.startPageName
    )
    XCTAssertEqual(
      helpInfo[HelpBookContract.indexPathKey] as? String,
      HelpBookContract.indexName
    )

    let localizedResources =
      contents
      .appendingPathComponent("Resources", isDirectory: true)
      .appendingPathComponent("\(HelpBookContract.localization).lproj", isDirectory: true)
    let localizedInfo = try propertyList(
      at: localizedResources.appendingPathComponent("InfoPlist.strings")
    )
    let startPage = localizedResources.appendingPathComponent(HelpBookContract.startPageName)
    let metadata = try pageMetadata(at: startPage)

    XCTAssertEqual(localizedInfo[HelpBookContract.titleKey] as? String, HelpBookContract.title)
    XCTAssertTrue(FileManager.default.fileExists(atPath: startPage.path))
    XCTAssertEqual(metadata[HelpBookContract.appleTitleName], bookName)
    XCTAssertNil(metadata[HelpBookContract.robotsName])
  }

  private func propertyList(at url: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: url)
    return try XCTUnwrap(
      PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    )
  }

  private func pageMetadata(at url: URL) throws -> [String: String] {
    let parser = XMLParser(data: try Data(contentsOf: url))
    let delegate = HelpPageMetadataParser()
    parser.delegate = delegate

    XCTAssertTrue(parser.parse(), parser.parserError?.localizedDescription ?? "Invalid help page")
    return delegate.metadata
  }

  private var resourcesDirectory: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Resources", isDirectory: true)
  }
}

private final class HelpPageMetadataParser: NSObject, XMLParserDelegate {
  private(set) var metadata: [String: String] = [:]

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String]
  ) {
    guard elementName == HelpBookContract.metaElement,
      let name = attributeDict[HelpBookContract.metaNameAttribute],
      let content = attributeDict[HelpBookContract.metaContentAttribute]
    else {
      return
    }

    metadata[name] = content
  }
}

private enum HelpBookContract {
  static let folderKey = "CFBundleHelpBookFolder"
  static let nameKey = "CFBundleHelpBookName"
  static let bundleIdentifierKey = "CFBundleIdentifier"
  static let developmentRegionKey = "CFBundleDevelopmentRegion"
  static let accessPathKey = "HPDBookAccessPath"
  static let indexPathKey = "HPDBookIndexPath"
  static let titleKey = "HPDBookTitle"
  static let metaElement = "meta"
  static let metaNameAttribute = "name"
  static let metaContentAttribute = "content"
  static let appleTitleName = "AppleTitle"
  static let robotsName = "robots"

  static let folderName = "Sion.help"
  static let identifier = "ch.lkmc.Sion.help"
  static let localization = "en"
  static let title = "Sion Help"
  static let startPageName = "index.html"
  static let indexName = "Sion.helpindex"
}
