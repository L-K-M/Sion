// C entry points for GLib and GTK facilities Swift cannot reach directly:
// macros, variadic functions, and fundamental GType constants.
#ifndef SION_GTK_SHIM_H
#define SION_GTK_SHIM_H

#include <adwaita.h>
#include <gtk/gtk.h>

G_BEGIN_DECLS

/// `g_signal_connect` without the `G_CALLBACK` macro. Returns the handler ID.
gulong sion_signal_connect(
  gpointer instance,
  const char *detailed_signal,
  GCallback handler,
  gpointer data,
  GClosureNotify destroy_data,
  gboolean after);

/// `gtk_alert_dialog_new` takes a printf format; this passes a literal message.
GtkAlertDialog *sion_alert_dialog_new(const char *message);

/// `gtk_accessible_update_property` is variadic.
void sion_accessible_set_label(GtkAccessible *accessible, const char *label);
void sion_accessible_set_description(GtkAccessible *accessible, const char *description);

/// `gtk_application_set_accels_for_action` wants a NULL-terminated array.
void sion_application_set_accels(
  GtkApplication *application, const char *action, const char *accel1, const char *accel2);

/// `g_object_set` is variadic; these set one typed property each.
void sion_object_set_string(gpointer object, const char *property, const char *value);
void sion_object_set_boolean(gpointer object, const char *property, gboolean value);
void sion_object_set_int(gpointer object, const char *property, int value);
void sion_object_set_double(gpointer object, const char *property, double value);
void sion_object_set_object(gpointer object, const char *property, gpointer value);

/// Returns a newly allocated string property value (free with `g_free`) or NULL.
char *sion_object_get_string(gpointer object, const char *property);
gboolean sion_object_get_boolean(gpointer object, const char *property);
int sion_object_get_int(gpointer object, const char *property);
double sion_object_get_double(gpointer object, const char *property);

/// `G_TYPE_CHECK_INSTANCE_TYPE` without the macro.
gboolean sion_instance_is_a(gpointer instance, GType type);

/// Fundamental GTypes are macros, not functions.
GType sion_type_string(void);
GType sion_type_boolean(void);
GType sion_type_int(void);
GType sion_type_uint(void);
GType sion_type_double(void);
GType sion_type_object(void);
GType sion_type_pointer(void);

/// `G_SOURCE_REMOVE` / `G_SOURCE_CONTINUE` and `GDK_EVENT_*` are macros.
gboolean sion_source_remove(void);
gboolean sion_source_continue(void);
gboolean sion_event_stop(void);
gboolean sion_event_propagate(void);

/// Reads a GValue that a drop target or clipboard produced.
const char *sion_value_get_string(const GValue *value);
gpointer sion_value_get_object(const GValue *value);
gpointer sion_value_get_boxed(const GValue *value);
gboolean sion_value_holds(const GValue *value, GType type);

/// `g_list_model_get_item` result plus `G_N_ELEMENTS`-style helpers.
guint sion_list_length(GList *list);
gpointer sion_list_nth(GList *list, guint index);
guint sion_slist_length(GSList *list);
gpointer sion_slist_nth(GSList *list, guint index);

/// `GDK_RGBA` literal helper.
GdkRGBA sion_rgba(double red, double green, double blue, double alpha);

G_END_DECLS

#endif
