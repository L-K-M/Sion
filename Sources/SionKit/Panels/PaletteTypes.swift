#if canImport(AppKit)
  import AppKit

  /// A stable, application-wide palette identity.
  public struct PaletteKind: Hashable, Sendable {
    public let identifier: String

    public init(_ identifier: String) {
      precondition(!identifier.isEmpty, "A palette kind needs an identifier")

      self.identifier = identifier
    }
  }

  public enum PaletteSizing {
    case fixed
    case resizable(minimumContentSize: NSSize)
  }

  /// Presentation details shared by the attached and floating forms.
  public struct PaletteDefinition {
    public let kind: PaletteKind
    public let title: String
    public let contentSize: NSSize
    public let sizing: PaletteSizing

    public init(
      kind: PaletteKind,
      title: String,
      contentSize: NSSize,
      sizing: PaletteSizing = .fixed
    ) {
      precondition(!title.isEmpty, "A palette needs a title")
      precondition(
        contentSize.width > 0 && contentSize.height > 0,
        "A palette needs a positive content size")

      if case .resizable(let minimumContentSize) = sizing {
        precondition(
          minimumContentSize.width > 0 && minimumContentSize.height > 0,
          "A resizable palette needs a positive minimum size")
      }

      self.kind = kind
      self.title = title
      self.contentSize = contentSize
      self.sizing = sizing
    }
  }

  public enum PalettePresentation: Equatable, Sendable {
    case popover
    case panel
  }

  /// A typed adapter between palette UI and its current front-document target.
  ///
  /// The factory registered with ``PaletteCenter`` creates one instance for the
  /// popover and another for the panel. Keep shared selection state outside the
  /// view controllers when both presentations must remain synchronized.
  @MainActor
  public protocol PaletteContent: AnyObject {
    associatedtype Target

    var paletteViewController: NSViewController { get }
    var paletteInitialFirstResponder: NSView? { get }

    func retarget(to target: Target?)
    func paletteDidPresent(_ presentation: PalettePresentation)
    func paletteDidDismiss(_ presentation: PalettePresentation)
  }

  extension PaletteContent {
    public var paletteInitialFirstResponder: NSView? { nil }

    public func paletteDidPresent(_ presentation: PalettePresentation) {}
    public func paletteDidDismiss(_ presentation: PalettePresentation) {}
  }

  extension PaletteContent where Self: NSViewController {
    public var paletteViewController: NSViewController { self }
  }

  /// Erases the content target while preserving type-safe registration.
  @MainActor
  final class AnyPaletteContent {
    let viewController: NSViewController

    private let initialFirstResponder: @MainActor () -> NSView?
    private let resolveTarget: @MainActor () -> Void
    private let clearTarget: @MainActor () -> Void
    private let didPresent: @MainActor (PalettePresentation) -> Void
    private let didDismiss: @MainActor (PalettePresentation) -> Void

    init<Content: PaletteContent>(
      content: Content,
      target: @escaping @MainActor () -> Content.Target?
    ) {
      viewController = content.paletteViewController
      initialFirstResponder = { content.paletteInitialFirstResponder }
      resolveTarget = { content.retarget(to: target()) }
      clearTarget = { content.retarget(to: nil) }
      didPresent = { content.paletteDidPresent($0) }
      didDismiss = { content.paletteDidDismiss($0) }
    }

    var preferredFirstResponder: NSView? {
      initialFirstResponder()
    }

    func retarget() {
      resolveTarget()
    }

    func releaseTarget() {
      clearTarget()
    }

    func presented(as presentation: PalettePresentation) {
      didPresent(presentation)
    }

    func dismissed(from presentation: PalettePresentation) {
      didDismiss(presentation)
    }
  }
#endif
