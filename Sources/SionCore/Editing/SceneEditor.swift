import Foundation

public enum EditorOperationResult: Equatable, Sendable {
  case applied
  case noChange
}

public struct SceneEditor: Sendable {
  public static let defaultHistoryLimit = 100

  public private(set) var document: SionDocument

  private let historyLimit: Int
  private var undoHistory: [HistoryEntry]
  private var redoHistory: [HistoryEntry]
  private var pendingGesture: PendingGesture?

  public init(
    document: SionDocument = SionDocument(),
    historyLimit: Int = SceneEditor.defaultHistoryLimit
  ) throws {
    guard historyLimit > 0 else {
      throw SceneEditingError.invalidHistoryLimit(historyLimit)
    }

    try document.validate()

    self.document = document
    self.historyLimit = historyLimit
    undoHistory = []
    redoHistory = []
    pendingGesture = nil
  }

  public var canUndo: Bool {
    guard let pendingGesture else {
      return !undoHistory.isEmpty
    }

    return pendingGesture.documentBefore != document || !undoHistory.isEmpty
  }

  public var canRedo: Bool {
    pendingGesture == nil && !redoHistory.isEmpty
  }

  /// Whether a coalesced edit is between begin and end, cancel, or undo.
  public var hasPendingGesture: Bool {
    pendingGesture != nil
  }

  @discardableResult
  public mutating func perform(_ transaction: SceneTransaction) throws -> EditorOperationResult {
    guard pendingGesture == nil else {
      throw SceneEditingError.commandDuringGesture
    }

    // A validated snapshot makes a multi-command user intent atomic and undoable.
    let documentBefore = document
    let result = try apply(transaction.commands)
    guard result == .applied else {
      return .noChange
    }

    record(
      HistoryEntry(
        name: transaction.name,
        documentBefore: documentBefore,
        documentAfter: document
      )
    )
    return .applied
  }

  public mutating func beginGesture(named name: String) throws {
    guard pendingGesture == nil else {
      throw SceneEditingError.gestureAlreadyActive
    }

    pendingGesture = PendingGesture(name: name, documentBefore: document)
  }

  @discardableResult
  public mutating func updateGesture(
    with commands: [SceneCommand]
  ) throws -> EditorOperationResult {
    guard pendingGesture != nil else {
      throw SceneEditingError.noActiveGesture
    }

    return try apply(commands)
  }

  @discardableResult
  public mutating func updateGesture(
    with command: SceneCommand
  ) throws -> EditorOperationResult {
    try updateGesture(with: [command])
  }

  @discardableResult
  public mutating func endGesture() throws -> EditorOperationResult {
    guard let pendingGesture else {
      throw SceneEditingError.noActiveGesture
    }

    self.pendingGesture = nil

    guard pendingGesture.documentBefore != document else {
      return .noChange
    }

    record(
      HistoryEntry(
        name: pendingGesture.name,
        documentBefore: pendingGesture.documentBefore,
        documentAfter: document
      )
    )
    return .applied
  }

  @discardableResult
  public mutating func cancelGesture() throws -> EditorOperationResult {
    guard let pendingGesture else {
      throw SceneEditingError.noActiveGesture
    }

    self.pendingGesture = nil

    guard pendingGesture.documentBefore != document else {
      return .noChange
    }

    document = pendingGesture.documentBefore
    return .applied
  }

  /// Undo during a drag restores its start and keeps the drag redoable.
  @discardableResult
  public mutating func undo() -> String? {
    if let pendingGesture {
      self.pendingGesture = nil

      guard pendingGesture.documentBefore != document else {
        return undo()
      }

      let entry = HistoryEntry(
        name: pendingGesture.name,
        documentBefore: pendingGesture.documentBefore,
        documentAfter: document
      )
      document = pendingGesture.documentBefore
      redoHistory.insert(entry, at: 0)
      return entry.name
    }

    guard let entry = undoHistory.popLast() else {
      return nil
    }

    document = entry.documentBefore
    redoHistory.insert(entry, at: 0)
    return entry.name
  }

  @discardableResult
  public mutating func redo() -> String? {
    guard pendingGesture == nil, !redoHistory.isEmpty else {
      return nil
    }

    let entry = redoHistory.removeFirst()
    document = entry.documentAfter
    appendToUndoHistory(entry)
    return entry.name
  }

  private mutating func apply(_ commands: [SceneCommand]) throws -> EditorOperationResult {
    var candidate = document

    for command in commands {
      try command.apply(to: &candidate.scene)
    }

    try candidate.validate()

    guard candidate != document else {
      return .noChange
    }

    document = candidate
    return .applied
  }

  private mutating func record(_ entry: HistoryEntry) {
    appendToUndoHistory(entry)
    redoHistory.removeAll(keepingCapacity: true)
  }

  private mutating func appendToUndoHistory(_ entry: HistoryEntry) {
    undoHistory.append(entry)

    let excessCount = undoHistory.count - historyLimit
    guard excessCount > 0 else {
      return
    }

    undoHistory.removeFirst(excessCount)
  }
}

private struct HistoryEntry: Sendable {
  let name: String
  let documentBefore: SionDocument
  let documentAfter: SionDocument
}

private struct PendingGesture: Sendable {
  let name: String
  let documentBefore: SionDocument
}
