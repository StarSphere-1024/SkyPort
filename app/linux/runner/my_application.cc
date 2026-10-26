#include "my_application.h"

#include <flutter_linux/flutter_linux.h>

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView *view)
{
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

static void close_response_cb(GObject* object, GAsyncResult* result,
                              gpointer user_data) {
  GtkWidget* window = GTK_WIDGET(user_data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(FlMethodResponse) response = fl_method_channel_invoke_method_finish(
      FL_METHOD_CHANNEL(object), result, &error);
  FlValue* value = response == nullptr
      ? nullptr : fl_method_response_get_result(response, &error);
  g_object_set_data(G_OBJECT(window), "close-pending", nullptr);
  if (value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_BOOL &&
      fl_value_get_bool(value)) {
    gtk_widget_destroy(window);
  } else {
    g_warning("Core shutdown not completed; keeping window open: %s",
              error == nullptr ? "host refused close" : error->message);
  }
  g_object_unref(window);
}

static gboolean close_requested_cb(GtkWidget* window, GdkEvent* event,
                                   gpointer user_data) {
  if (g_object_get_data(G_OBJECT(window), "close-pending") == nullptr) {
    g_object_set_data(G_OBJECT(window), "close-pending", GINT_TO_POINTER(1));
    fl_method_channel_invoke_method(FL_METHOD_CHANNEL(user_data),
        "requestClose", nullptr, nullptr, close_response_cb, g_object_ref(window));
  }
  return TRUE;
}

struct WindowState {
  FlMethodChannel* channel;
  gboolean maximized;
  gboolean active;
  GdkDevice* last_press_device;
  guint32 last_press_time;
  gdouble last_press_x;
  gdouble last_press_y;
  gboolean has_last_press;
};

static FlValue* window_state_value(const WindowState* state) {
  FlValue* value = fl_value_new_map();
  fl_value_set_string_take(value, "maximized",
                           fl_value_new_bool(state->maximized));
  fl_value_set_string_take(value, "active", fl_value_new_bool(state->active));
  fl_value_set_string_take(value, "maximizeHovered", fl_value_new_bool(FALSE));
  return value;
}

static void update_window_state(GtkWindow* window, gboolean maximized,
                                gboolean active) {
  WindowState* state = static_cast<WindowState*>(
      g_object_get_data(G_OBJECT(window), "window-state"));
  if (state == nullptr ||
      (state->maximized == maximized && state->active == active)) {
    return;
  }
  state->maximized = maximized;
  state->active = active;
  if (state->channel != nullptr) {
    g_autoptr(FlValue) value = window_state_value(state);
    fl_method_channel_invoke_method(state->channel, "windowState", value,
                                    nullptr, nullptr, nullptr);
  }
}

static gboolean window_state_cb(GtkWidget* widget, GdkEventWindowState* event,
                                gpointer user_data) {
  GtkWindow* window = GTK_WINDOW(widget);
  update_window_state(window,
      (event->new_window_state & GDK_WINDOW_STATE_MAXIMIZED) != 0,
      gtk_window_is_active(window));
  return FALSE;
}

static gboolean window_focus_cb(GtkWidget* widget, GdkEventFocus* event,
                                gpointer user_data) {
  WindowState* state = static_cast<WindowState*>(
      g_object_get_data(G_OBJECT(widget), "window-state"));
  update_window_state(GTK_WINDOW(widget), state->maximized, event->in);
  return FALSE;
}

static void toggle_maximize(GtkWindow* window) {
  if (gtk_window_is_maximized(window)) {
    gtk_window_unmaximize(window);
  } else {
    gtk_window_maximize(window);
  }
}

static void handle_titlebar_press(GtkWindow* window, GdkEventButton* event) {
  GdkWindow* native_window = gtk_widget_get_window(GTK_WIDGET(window));
  WindowState* state = static_cast<WindowState*>(
      g_object_get_data(G_OBJECT(window), "window-state"));
  if (event->button == 3) {
    state->has_last_press = FALSE;
    gdk_window_show_window_menu(native_window,
                               reinterpret_cast<GdkEvent*>(event));
    return;
  }

  guint double_click_time = 0;
  gint double_click_distance = 0;
  g_object_get(gtk_widget_get_settings(GTK_WIDGET(window)),
      "gtk-double-click-time", &double_click_time,
      "gtk-double-click-distance", &double_click_distance, nullptr);
  GdkDevice* device =
      gdk_event_get_device(reinterpret_cast<GdkEvent*>(event));
  const gdouble dx = event->x_root - state->last_press_x;
  const gdouble dy = event->y_root - state->last_press_y;
  // Beginning a native move can cancel GTK's gesture sequence. Keep the
  // click history independently so a stationary first press still permits
  // double-click maximize, using GTK's configured time/distance thresholds.
  const gboolean double_click = state->has_last_press &&
      state->last_press_device == device &&
      static_cast<guint32>(event->time - state->last_press_time) <=
          double_click_time &&
      dx > -double_click_distance && dx < double_click_distance &&
      dy > -double_click_distance && dy < double_click_distance;
  state->has_last_press = !double_click;
  state->last_press_device = device;
  state->last_press_time = event->time;
  state->last_press_x = event->x_root;
  state->last_press_y = event->y_root;
  if (double_click) {
    toggle_maximize(window);
  } else {
    // Unlike the device-less GTK wrapper, this preserves the initiating
    // pointer/seat as well as the real event timestamp on Wayland.
    gdk_window_begin_move_drag_for_device(native_window, device, event->button,
        static_cast<gint>(event->x_root), static_cast<gint>(event->y_root),
        event->time);
  }
}

static void titlebar_capture_pressed_cb(GtkGestureMultiPress* gesture,
                                        gint n_press, gdouble x, gdouble y,
                                        gpointer user_data) {
  GdkEventSequence* sequence =
      gtk_gesture_single_get_current_sequence(GTK_GESTURE_SINGLE(gesture));
  const GdkEvent* event =
      gtk_gesture_get_last_event(GTK_GESTURE(gesture), sequence);
  if (event == nullptr || event->type != GDK_BUTTON_PRESS) {
    return;
  }
  GdkEventButton* button_event =
      const_cast<GdkEventButton*>(&event->button);
  GtkWidget* view =
      gtk_event_controller_get_widget(GTK_EVENT_CONTROLLER(gesture));
  // Gesture coordinates are view-local even when the event targets FlView's
  // internal event box. GDK keeps the original root coordinates and device.
  if (x < 0 || y < 0 || y >= 48 ||
      x >= gtk_widget_get_allocated_width(view) - 3 * 46 ||
      (button_event->button != 1 && button_event->button != 3)) {
    WindowState* state = static_cast<WindowState*>(
        g_object_get_data(G_OBJECT(user_data), "window-state"));
    state->has_last_press = FALSE;
    return;
  }
  // FlView's internal event box consumes ordinary button presses. Capture
  // only native header gestures before that, leaving Flutter controls alone.
  gtk_gesture_set_state(GTK_GESTURE(gesture), GTK_EVENT_SEQUENCE_CLAIMED);
  handle_titlebar_press(GTK_WINDOW(user_data), button_event);
}

static void window_destroy_cb(GtkWidget* window, gpointer user_data) {
  WindowState* state = static_cast<WindowState*>(
      g_object_get_data(G_OBJECT(window), "window-state"));
  fl_method_channel_set_method_call_handler(state->channel, nullptr,
                                            nullptr, nullptr);
  state->channel = nullptr;
}

static void window_method_call_cb(FlMethodChannel* channel,
                                  FlMethodCall* method_call,
                                  gpointer user_data) {
  GtkWindow* window = GTK_WINDOW(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  if (g_strcmp0(method, "configure") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
      fl_method_call_respond_error(method_call, "invalid_arguments",
          "configure requires a window configuration map.", nullptr, nullptr);
      return;
    }
    FlValue* title = fl_value_lookup_string(args, "title");
    FlValue* dark = fl_value_lookup_string(args, "dark");
    if (title == nullptr || fl_value_get_type(title) != FL_VALUE_TYPE_STRING ||
        dark == nullptr || fl_value_get_type(dark) != FL_VALUE_TYPE_BOOL) {
      fl_method_call_respond_error(method_call, "invalid_arguments",
          "Expected string title and boolean dark.", nullptr, nullptr);
      return;
    }

    GtkSettings* settings = gtk_widget_get_settings(GTK_WIDGET(window));
    gboolean current_dark = FALSE;
    g_object_get(settings, "gtk-application-prefer-dark-theme",
                  &current_dark, nullptr);
    if (current_dark != fl_value_get_bool(dark)) {
      g_object_set(settings, "gtk-application-prefer-dark-theme",
                    fl_value_get_bool(dark), nullptr);
    }
    if (g_strcmp0(gtk_window_get_title(window),
                  fl_value_get_string(title)) != 0) {
      gtk_window_set_title(window, fl_value_get_string(title));
    }
    update_window_state(window, gtk_window_is_maximized(window),
                         gtk_window_is_active(window));
    WindowState* state = static_cast<WindowState*>(
        g_object_get_data(G_OBJECT(window), "window-state"));
    g_autoptr(FlValue) value = window_state_value(state);
    fl_method_call_respond_success(method_call, value, nullptr);
    return;
  }

  if (g_strcmp0(method, "minimize") == 0) {
    gtk_window_iconify(window);
  } else if (g_strcmp0(method, "toggleMaximize") == 0) {
    toggle_maximize(window);
  } else if (g_strcmp0(method, "close") == 0) {
    // Keep delete-event as the single entry point to awaited core shutdown.
    gtk_window_close(window);
  } else {
    fl_method_call_respond_not_implemented(method_call, nullptr);
    return;
  }
  fl_method_call_respond_success(method_call, nullptr, nullptr);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Flutter draws the titlebar; leave outer borders and corners to the compositor.
  gtk_window_set_decorated(window, FALSE);
  gtk_window_set_title(window, "SkyPort");

  gtk_window_set_default_size(window, 1200, 800);
  gtk_widget_set_size_request(GTK_WIDGET(window), 320, 480);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000 for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  GtkGesture* titlebar_gesture =
      gtk_gesture_multi_press_new(GTK_WIDGET(view));
  gtk_gesture_single_set_button(GTK_GESTURE_SINGLE(titlebar_gesture), 0);
  gtk_event_controller_set_propagation_phase(
      GTK_EVENT_CONTROLLER(titlebar_gesture), GTK_PHASE_CAPTURE);
  g_signal_connect(titlebar_gesture, "pressed",
                   G_CALLBACK(titlebar_capture_pressed_cb), window);
  g_object_set_data_full(G_OBJECT(view), "titlebar-gesture", titlebar_gesture,
                         g_object_unref);

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb), self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* host_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "skyport/host", FL_METHOD_CODEC(codec));
  g_object_set_data_full(G_OBJECT(window), "host-channel", host_channel,
                        g_object_unref);
  g_signal_connect(window, "delete-event", G_CALLBACK(close_requested_cb),
                   host_channel);

  FlMethodChannel* window_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "skyport/window", FL_METHOD_CODEC(codec));
  g_object_set_data_full(G_OBJECT(window), "window-channel", window_channel,
                        g_object_unref);
  fl_method_channel_set_method_call_handler(
      window_channel, window_method_call_cb, window, nullptr);
  WindowState* state = new WindowState{};
  state->channel = window_channel;
  state->maximized = gtk_window_is_maximized(window);
  state->active = gtk_window_is_active(window);
  g_object_set_data_full(G_OBJECT(window), "window-state", state,
      [](gpointer data) { delete static_cast<WindowState*>(data); });
  g_signal_connect(window, "window-state-event",
                   G_CALLBACK(window_state_cb), nullptr);
  g_signal_connect(window, "focus-in-event",
                   G_CALLBACK(window_focus_cb), nullptr);
  g_signal_connect(window, "focus-out-event",
                   G_CALLBACK(window_focus_cb), nullptr);
  g_signal_connect(window, "destroy", G_CALLBACK(window_destroy_cb), nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application, gchar*** arguments, int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
     g_warning("Failed to register: %s", error->message);
     *exit_status = 1;
     return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  //MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  //MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line = my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID,
                                     "flags", G_APPLICATION_NON_UNIQUE,
                                     nullptr));
}
