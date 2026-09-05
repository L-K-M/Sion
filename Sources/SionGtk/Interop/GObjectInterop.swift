import CGtk
import CSionGtkShim
import Foundation

// MARK: - Pointer casts

extension UnsafeMutablePointer {
  /// GObject instances are C structs related by layout, so GTK's cast macros
  /// reinterpret pointers; Swift needs the same step spelled out.
  func cast<Target>() -> UnsafeMutablePointer<Target> {
    UnsafeMutableRawPointer(self).assumingMemoryBound(to: Target.self)
  }

  /// The untyped instance pointer GLib's object and signal functions take.
  var gobject: gpointer {
    gpointer(self)
  }
}

extension UnsafeMutablePointer {
  /// Final GTK types have no public instance struct, so their pointers import
  /// as `OpaquePointer`; this is the cast to one of those.
  var opaque: OpaquePointer {
    OpaquePointer(self)
  }
}

extension OpaquePointer {
  func cast<Target>() -> UnsafeMutablePointer<Target> {
    UnsafeMutablePointer<Target>(self)
  }

  var gobject: gpointer {
    UnsafeMutableRawPointer(self)
  }
}

extension UnsafeMutableRawPointer {
  func cast<Target>() -> UnsafeMutablePointer<Target> {
    assumingMemoryBound(to: Target.self)
  }
}

/// Reports whether an instance is (a subclass of) the given type.
func gtkInstance(_ instance: gpointer?, isA type: GType) -> Bool {
  guard let instance else { return false }
  return sion_instance_is_a(instance, type) != 0
}

// MARK: - Strings

extension String {
  /// Copies a string GLib still owns.
  init?(gtkString pointer: UnsafePointer<gchar>?) {
    guard let pointer else { return nil }
    self.init(cString: pointer)
  }

  /// Copies a string GLib handed over, then frees it.
  init?(takingOwnershipOf pointer: UnsafeMutablePointer<gchar>?) {
    guard let pointer else { return nil }
    defer { g_free(pointer) }
    self.init(cString: pointer)
  }
}

// MARK: - Errors

/// A `GError` carried into Swift's error handling.
struct GLibError: LocalizedError, Equatable {
  let domain: String
  let code: Int32
  let message: String

  init(_ error: UnsafeMutablePointer<GError>) {
    domain = String(gtkString: g_quark_to_string(error.pointee.domain)) ?? ""
    code = error.pointee.code
    message = String(gtkString: error.pointee.message) ?? ""
  }

  var errorDescription: String? {
    message
  }

  /// Runs a GLib call that reports failure through an out `GError`, throwing
  /// it as a Swift error and freeing the C record either way.
  static func check<Result>(
    _ body: (UnsafeMutablePointer<UnsafeMutablePointer<GError>?>) -> Result
  ) throws -> Result {
    var error: UnsafeMutablePointer<GError>?
    let result = body(&error)
    if let error {
      let swiftError = GLibError(error)
      g_error_free(error)
      throw swiftError
    }
    return result
  }
}

// MARK: - Lists

extension UnsafeMutablePointer where Pointee == GList {
  /// Every element of a `GList`, without taking ownership.
  var elements: [gpointer] {
    let count = sion_list_length(self)
    return (0..<count).compactMap { sion_list_nth(self, $0) }
  }
}

extension UnsafeMutablePointer where Pointee == GSList {
  var elements: [gpointer] {
    let count = sion_slist_length(self)
    return (0..<count).compactMap { sion_slist_nth(self, $0) }
  }
}

// MARK: - GValue

extension GValue {
  /// A zeroed value ready for `g_value_init`.
  static func empty() -> GValue {
    GValue()
  }

  static func string(_ value: String) -> GValue {
    var gvalue = GValue.empty()
    g_value_init(&gvalue, sion_type_string())
    g_value_set_string(&gvalue, value)
    return gvalue
  }

  var stringValue: String? {
    var copy = self
    guard sion_value_holds(&copy, sion_type_string()) != 0 else { return nil }
    return String(gtkString: sion_value_get_string(&copy))
  }
}

// MARK: - Fundamental types

enum GTypes {
  static var string: GType { sion_type_string() }
  static var boolean: GType { sion_type_boolean() }
  static var int: GType { sion_type_int() }
  static var uint: GType { sion_type_uint() }
  static var double: GType { sion_type_double() }
  static var object: GType { sion_type_object() }
  static var pointer: GType { sion_type_pointer() }
  static var file: GType { g_file_get_type() }
  static var fileList: GType { gdk_file_list_get_type() }
  static var texture: GType { gdk_texture_get_type() }
}

enum GtkEventResult {
  static var stop: gboolean { sion_event_stop() }
  static var propagate: gboolean { sion_event_propagate() }
}
