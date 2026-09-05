#include "sion_gtk_shim.h"

gulong sion_signal_connect(
  gpointer instance,
  const char *detailed_signal,
  GCallback handler,
  gpointer data,
  GClosureNotify destroy_data,
  gboolean after) {
  return g_signal_connect_data(
    instance, detailed_signal, handler, data, destroy_data, after ? G_CONNECT_AFTER : 0);
}

GtkAlertDialog *sion_alert_dialog_new(const char *message) {
  return gtk_alert_dialog_new("%s", message);
}

void sion_accessible_set_label(GtkAccessible *accessible, const char *label) {
  gtk_accessible_update_property(accessible, GTK_ACCESSIBLE_PROPERTY_LABEL, label, -1);
}

void sion_accessible_set_description(GtkAccessible *accessible, const char *description) {
  gtk_accessible_update_property(
    accessible, GTK_ACCESSIBLE_PROPERTY_DESCRIPTION, description, -1);
}

void sion_application_set_accels(
  GtkApplication *application,
  const char *action,
  const char *accel1,
  const char *accel2,
  const char *accel3) {
  const char *accels[4] = {accel1, accel2, accel3, NULL};
  gtk_application_set_accels_for_action(application, action, accels);
}

void sion_object_set_string(gpointer object, const char *property, const char *value) {
  g_object_set(object, property, value, NULL);
}

void sion_object_set_boolean(gpointer object, const char *property, gboolean value) {
  g_object_set(object, property, value, NULL);
}

void sion_object_set_int(gpointer object, const char *property, int value) {
  g_object_set(object, property, value, NULL);
}

void sion_object_set_double(gpointer object, const char *property, double value) {
  g_object_set(object, property, value, NULL);
}

void sion_object_set_object(gpointer object, const char *property, gpointer value) {
  g_object_set(object, property, value, NULL);
}

char *sion_object_get_string(gpointer object, const char *property) {
  char *value = NULL;
  g_object_get(object, property, &value, NULL);
  return value;
}

gboolean sion_object_get_boolean(gpointer object, const char *property) {
  gboolean value = FALSE;
  g_object_get(object, property, &value, NULL);
  return value;
}

int sion_object_get_int(gpointer object, const char *property) {
  int value = 0;
  g_object_get(object, property, &value, NULL);
  return value;
}

double sion_object_get_double(gpointer object, const char *property) {
  double value = 0;
  g_object_get(object, property, &value, NULL);
  return value;
}

gboolean sion_instance_is_a(gpointer instance, GType type) {
  return instance != NULL && G_TYPE_CHECK_INSTANCE_TYPE(instance, type);
}

GType sion_type_string(void) { return G_TYPE_STRING; }
GType sion_type_boolean(void) { return G_TYPE_BOOLEAN; }
GType sion_type_int(void) { return G_TYPE_INT; }
GType sion_type_uint(void) { return G_TYPE_UINT; }
GType sion_type_double(void) { return G_TYPE_DOUBLE; }
GType sion_type_object(void) { return G_TYPE_OBJECT; }
GType sion_type_pointer(void) { return G_TYPE_POINTER; }

gboolean sion_source_remove(void) { return G_SOURCE_REMOVE; }
gboolean sion_source_continue(void) { return G_SOURCE_CONTINUE; }
gboolean sion_event_stop(void) { return GDK_EVENT_STOP; }
gboolean sion_event_propagate(void) { return GDK_EVENT_PROPAGATE; }

const char *sion_value_get_string(const GValue *value) { return g_value_get_string(value); }
gpointer sion_value_get_object(const GValue *value) { return g_value_get_object(value); }
gpointer sion_value_get_boxed(const GValue *value) { return g_value_get_boxed(value); }
gboolean sion_value_holds(const GValue *value, GType type) { return G_VALUE_HOLDS(value, type); }

guint sion_list_length(GList *list) { return g_list_length(list); }
gpointer sion_list_nth(GList *list, guint index) { return g_list_nth_data(list, index); }
guint sion_slist_length(GSList *list) { return g_slist_length(list); }
gpointer sion_slist_nth(GSList *list, guint index) { return g_slist_nth_data(list, index); }

GdkRGBA sion_rgba(double red, double green, double blue, double alpha) {
  GdkRGBA color = {(float)red, (float)green, (float)blue, (float)alpha};
  return color;
}
