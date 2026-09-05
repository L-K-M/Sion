import Foundation

#if !canImport(AppKit)
  /// The undo manager the shared editing layer registers with on Linux.
  ///
  /// swift-corelibs-foundation ships no `UndoManager`, so this carries the part
  /// of Foundation's contract the editor controller and the document rely on:
  /// a registration made while undoing lands on the redo stack, one made while
  /// redoing lands on the undo stack, `setActionName(_:)` names the group that
  /// is open, and registrations made during one main-loop event coalesce into
  /// one step once the toolkit installs an ``eventGroupScheduler``.
  @MainActor
  package final class SionUndoManager {
    package typealias EventGroupScheduler = (@escaping @MainActor () -> Void) -> Void

    package static let checkpointNotification = Notification.Name("NSUndoManagerCheckpoint")
    package static let didUndoChangeNotification = Notification.Name("NSUndoManagerDidUndoChange")
    package static let didRedoChangeNotification = Notification.Name("NSUndoManagerDidRedoChange")
    package static let didCloseUndoGroupNotification = Notification.Name(
      "NSUndoManagerDidCloseUndoGroup")

    private final class Group {
      var actions: [Action] = []
      var actionName = ""
    }

    private struct Action {
      weak var target: AnyObject?
      let perform: () -> Void
    }

    private var undoStack: [Group] = []
    private var redoStack: [Group] = []
    private var openGroups: [Group] = []
    private var eventGroupIsScheduled = false

    package private(set) var isUndoing = false
    package private(set) var isRedoing = false

    /// Zero keeps every step, like Foundation.
    package var levelsOfUndo = 0

    /// When false, only explicit groups collect registrations; a registration
    /// made outside one still opens a group that the next undo closes.
    package var groupsByEvent = true

    /// Closes the implicit group once the current event ends. The toolkit
    /// installs a main-loop idle here; without one, a registration closes the
    /// group the next registration or undo opens over.
    package var eventGroupScheduler: EventGroupScheduler?

    package init() {}

    package var canUndo: Bool {
      !undoStack.isEmpty || openGroups.contains { !$0.actions.isEmpty }
    }

    package var canRedo: Bool {
      !redoStack.isEmpty
    }

    package var groupingLevel: Int {
      openGroups.count
    }

    package var undoActionName: String {
      if let open = openGroups.first, !open.actions.isEmpty {
        return open.actionName
      }
      return undoStack.last?.actionName ?? ""
    }

    package var redoActionName: String {
      redoStack.last?.actionName ?? ""
    }

    package var undoMenuItemTitle: String {
      undoMenuTitle(forUndoActionName: undoActionName)
    }

    package var redoMenuItemTitle: String {
      redoMenuTitle(forUndoActionName: redoActionName)
    }

    package func undoMenuTitle(forUndoActionName actionName: String) -> String {
      actionName.isEmpty ? MenuTitle.undo : "\(MenuTitle.undo) \(actionName)"
    }

    package func redoMenuTitle(forUndoActionName actionName: String) -> String {
      actionName.isEmpty ? MenuTitle.redo : "\(MenuTitle.redo) \(actionName)"
    }

    package func registerUndo<Target: AnyObject>(
      withTarget target: Target,
      handler: @escaping @MainActor (Target) -> Void
    ) {
      let action = Action(target: target) { [weak target] in
        guard let target else { return }
        handler(target)
      }

      if isUndoing || isRedoing {
        // The group undo() or redo() opened collects the inverse registrations.
        openGroups.last?.actions.append(action)
        return
      }

      // A fresh edit discards what could have been redone, as Foundation does.
      redoStack.removeAll()
      currentEventGroup().actions.append(action)
    }

    package func setActionName(_ actionName: String) {
      guard let group = openGroups.last else { return }

      group.actionName = actionName
    }

    package func beginUndoGrouping() {
      openGroups.append(Group())
    }

    package func endUndoGrouping() {
      guard let group = openGroups.popLast() else { return }

      // Nested groups fold into their parent; the outermost lands on a stack.
      if let parent = openGroups.last {
        parent.actions.append(contentsOf: group.actions)
        if parent.actionName.isEmpty {
          parent.actionName = group.actionName
        }
        return
      }

      guard !group.actions.isEmpty else { return }

      if isUndoing {
        redoStack.append(group)
      } else {
        undoStack.append(group)
        trimUndoStack()
      }
      NotificationCenter.default.post(name: Self.didCloseUndoGroupNotification, object: self)
    }

    package func undo() {
      closeEventGroup()
      guard let group = undoStack.popLast() else { return }

      NotificationCenter.default.post(name: Self.checkpointNotification, object: self)
      isUndoing = true
      openGroups.append(Group())
      for action in group.actions.reversed() {
        action.perform()
      }
      if let inverse = openGroups.popLast() {
        inverse.actionName = inverse.actionName.isEmpty ? group.actionName : inverse.actionName
        if !inverse.actions.isEmpty {
          redoStack.append(inverse)
        }
      }
      isUndoing = false
      NotificationCenter.default.post(name: Self.didUndoChangeNotification, object: self)
    }

    package func redo() {
      closeEventGroup()
      guard let group = redoStack.popLast() else { return }

      NotificationCenter.default.post(name: Self.checkpointNotification, object: self)
      isRedoing = true
      openGroups.append(Group())
      for action in group.actions.reversed() {
        action.perform()
      }
      if let inverse = openGroups.popLast() {
        inverse.actionName = inverse.actionName.isEmpty ? group.actionName : inverse.actionName
        if !inverse.actions.isEmpty {
          undoStack.append(inverse)
          trimUndoStack()
        }
      }
      isRedoing = false
      NotificationCenter.default.post(name: Self.didRedoChangeNotification, object: self)
    }

    package func removeAllActions() {
      undoStack.removeAll()
      redoStack.removeAll()
      openGroups.removeAll()
      eventGroupIsScheduled = false
    }

    package func removeAllActions(withTarget target: AnyObject) {
      func prune(_ stack: inout [Group]) {
        for group in stack {
          group.actions.removeAll { $0.target === target }
        }
        stack.removeAll { $0.actions.isEmpty }
      }
      prune(&undoStack)
      prune(&redoStack)
      prune(&openGroups)
    }

    /// The implicit group every registration outside an explicit one joins.
    /// Without a scheduler it stays open until undo() or redo() closes it,
    /// which is what Foundation does between run-loop turns.
    private func currentEventGroup() -> Group {
      if let open = openGroups.last {
        return open
      }

      let group = Group()
      openGroups.append(group)
      if groupsByEvent, let eventGroupScheduler, !eventGroupIsScheduled {
        eventGroupIsScheduled = true
        eventGroupScheduler { [weak self] in
          guard let self else { return }
          self.eventGroupIsScheduled = false
          self.closeEventGroup()
        }
      }
      return group
    }

    private func closeEventGroup() {
      guard !isUndoing, !isRedoing, openGroups.count == 1 else { return }

      endUndoGrouping()
    }

    private func trimUndoStack() {
      guard levelsOfUndo > 0, undoStack.count > levelsOfUndo else { return }

      undoStack.removeFirst(undoStack.count - levelsOfUndo)
    }

    private enum MenuTitle {
      static let redo = "Redo"
      static let undo = "Undo"
    }
  }

  package typealias UndoManager = SionUndoManager
#endif
