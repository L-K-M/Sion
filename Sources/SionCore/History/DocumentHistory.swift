import Foundation

public enum SaveIntent: String, Codable, Sendable {
  case manual
  case autosave
  case saveAs
}

public struct HistoryRevision: Equatable, Sendable {
  public let identifier: String
  public let savedAt: Date
  public let intent: SaveIntent
  public let sceneData: Data

  public init(
    identifier: String,
    savedAt: Date,
    intent: SaveIntent,
    sceneData: Data
  ) {
    self.identifier = identifier
    self.savedAt = savedAt
    self.intent = intent
    self.sceneData = sceneData
  }
}

public struct DocumentHistory: Equatable, Sendable {
  public static let maximumRevisionCount = 120
  public static let alwaysKeepNewestCount = 12
  public static let autosaveCheckpointInterval: TimeInterval = 5 * 60

  public private(set) var revisions: [HistoryRevision]

  public init(revisions: [HistoryRevision] = []) {
    self.revisions = Self.thinned(revisions)
  }

  /// Loading preserves every valid retained snapshot; retention belongs to writers.
  init(preservingValidatedRevisions revisions: [HistoryRevision]) {
    precondition(revisions.count <= Self.maximumRevisionCount)

    self.revisions = revisions
  }

  public func appending(
    sceneData: Data,
    at date: Date,
    intent: SaveIntent
  ) -> DocumentHistory {
    let identifier = SHA256.hexDigest(sceneData)
    if revisions.first?.identifier == identifier {
      return self
    }

    if intent == .autosave,
      let newest = revisions.first,
      date.timeIntervalSince(newest.savedAt) < Self.autosaveCheckpointInterval
    {
      return self
    }

    let revision = HistoryRevision(
      identifier: identifier,
      savedAt: date,
      intent: intent,
      sceneData: sceneData
    )
    return DocumentHistory(revisions: [revision] + revisions)
  }

  private static func thinned(_ input: [HistoryRevision]) -> [HistoryRevision] {
    let sorted = input.sorted { lhs, rhs in
      if lhs.savedAt != rhs.savedAt {
        return lhs.savedAt > rhs.savedAt
      }
      return lhs.identifier < rhs.identifier
    }
    guard sorted.count > alwaysKeepNewestCount else {
      return sorted
    }

    let newest = Array(sorted.prefix(alwaysKeepNewestCount))
    guard let referenceDate = newest.first?.savedAt else {
      return []
    }

    var buckets = Set<RetentionBucket>()
    var retained = newest

    for revision in sorted.dropFirst(alwaysKeepNewestCount) {
      let bucket = retentionBucket(for: revision.savedAt, relativeTo: referenceDate)
      guard buckets.insert(bucket).inserted else {
        continue
      }

      retained.append(revision)
      if retained.count == maximumRevisionCount {
        break
      }
    }

    return retained
  }

  private static func retentionBucket(for date: Date, relativeTo newest: Date) -> RetentionBucket {
    let age = max(0, newest.timeIntervalSince(date))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = RetentionInterval.utcTimeZone

    if age < RetentionInterval.oneDay {
      return .hour(calendar.dateComponents([.year, .month, .day, .hour], from: date))
    }
    if age < RetentionInterval.thirtyDays {
      return .day(calendar.dateComponents([.year, .month, .day], from: date))
    }
    if age < RetentionInterval.oneYear {
      return .week(calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date))
    }
    return .month(calendar.dateComponents([.year, .month], from: date))
  }
}

private enum RetentionInterval {
  static let oneDay: TimeInterval = 24 * 60 * 60
  static let thirtyDays: TimeInterval = 30 * oneDay
  static let oneYear: TimeInterval = 365 * oneDay
  static let utcTimeZone = TimeZone(secondsFromGMT: 0)!
}

private enum RetentionBucket: Hashable {
  case hour(DateComponents)
  case day(DateComponents)
  case week(DateComponents)
  case month(DateComponents)
}
