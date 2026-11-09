#include "linux_shell.h"

#include <dlfcn.h>
#include <fontconfig/fontconfig.h>
#include <unistd.h>

#include <algorithm>
#include <cstdlib>
#include <set>
#include <string>

namespace {

constexpr char kChannel[] = "lumtub/windows_shell";
constexpr char kFrameChannel[] = "lumtub/window_frame";
constexpr char kMprisPath[] = "/org/mpris/MediaPlayer2";

// libayatana-appindicator3, loaded when the system has it.
using IndicatorNew = void* (*)(const char*, const char*, int, const char*);
using IndicatorSetStatus = void (*)(void*, int);
using IndicatorSetMenu = void (*)(void*, GtkMenu*);
using IndicatorSetTitle = void (*)(void*, const char*);
constexpr int kCategoryApplicationStatus = 0;
constexpr int kStatusPassive = 0;
constexpr int kStatusActive = 1;

struct Shell {
  GtkWindow* window = nullptr;
  FlMethodChannel* channel = nullptr;

  bool close_to_tray = false;
  bool minimize_to_tray = false;
  std::string show_label = "Show";
  std::string play_pause_label = "Play/Pause";
  std::string next_label = "Next";
  std::string exit_label = "Exit";

  bool indicator_loaded = false;
  IndicatorNew indicator_new = nullptr;
  IndicatorSetStatus indicator_set_status = nullptr;
  IndicatorSetMenu indicator_set_menu = nullptr;
  IndicatorSetTitle indicator_set_title = nullptr;
  void* indicator = nullptr;
  GtkWidget* menu = nullptr;

  GDBusConnection* bus = nullptr;
  guint bus_name = 0;
  std::string title;
  std::string artist;
  std::string art;
  std::string status = "Stopped";
  int64_t position_ms = 0;
  int64_t duration_ms = 0;
  bool can_next = false;
  bool can_previous = false;
  int track = 0;

  // Picture in picture: how the window was before, and where it was left.
  bool pip = false;
  bool above = false;
  bool was_maximized = false;
  int before_x = 0, before_y = 0, before_width = 0, before_height = 0;
  bool has_last = false;
  int last_x = 0, last_y = 0;

  // The screen saver held off while a video plays.
  guint inhibit = 0;

  // The app's own title bar (lib/window_frame.dart), on a channel of its
  // own. Wayland starts a move or resize only from the press that began it,
  // so the last left press is kept.
  FlMethodChannel* frame_channel = nullptr;
  bool custom_frame = false;
  GdkEvent* press = nullptr;
};

Shell shell;

std::string ExecutableDirectory() {
  char path[4096];
  const ssize_t length = readlink("/proc/self/exe", path, sizeof(path) - 1);
  if (length <= 0) return ".";
  path[length] = '\0';
  std::string full(path);
  return full.substr(0, full.rfind('/'));
}

std::string IconPath() { return ExecutableDirectory() + "/data/lumtub.png"; }

void Send(const char* method, FlValue* argument) {
  if (shell.channel == nullptr) {
    fl_value_unref(argument);
    return;
  }
  fl_method_channel_invoke_method(shell.channel, method, argument, nullptr, nullptr, nullptr);
  fl_value_unref(argument);
}

void SendFrame(const char* method, FlValue* argument) {
  if (shell.frame_channel == nullptr) {
    fl_value_unref(argument);
    return;
  }
  fl_method_channel_invoke_method(shell.frame_channel, method, argument, nullptr, nullptr, nullptr);
  fl_value_unref(argument);
}

void SendButton(const char* button) { Send("button", fl_value_new_string(button)); }

// ---- Tray -----------------------------------------------------------------

bool LoadIndicator() {
  if (shell.indicator_loaded) return shell.indicator_new != nullptr;
  shell.indicator_loaded = true;
  void* library = nullptr;
  for (const char* name : {"libayatana-appindicator3.so.1", "libappindicator3.so.1"}) {
    library = dlopen(name, RTLD_NOW | RTLD_LOCAL);
    if (library != nullptr) break;
  }
  if (library == nullptr) return false;
  shell.indicator_new = reinterpret_cast<IndicatorNew>(dlsym(library, "app_indicator_new_with_path"));
  shell.indicator_set_status = reinterpret_cast<IndicatorSetStatus>(dlsym(library, "app_indicator_set_status"));
  shell.indicator_set_menu = reinterpret_cast<IndicatorSetMenu>(dlsym(library, "app_indicator_set_menu"));
  shell.indicator_set_title = reinterpret_cast<IndicatorSetTitle>(dlsym(library, "app_indicator_set_title"));
  if (shell.indicator_new == nullptr || shell.indicator_set_status == nullptr || shell.indicator_set_menu == nullptr) {
    shell.indicator_new = nullptr;
    return false;
  }
  return true;
}

void ShowFromTray() {
  if (shell.indicator != nullptr) shell.indicator_set_status(shell.indicator, kStatusPassive);
  gtk_widget_show(GTK_WIDGET(shell.window));
  gtk_window_present(shell.window);
}

void ExitFromTray() {
  // The normal close path, so Dart saves progress and releases the player.
  shell.close_to_tray = false;
  shell.minimize_to_tray = false;
  if (shell.indicator != nullptr) shell.indicator_set_status(shell.indicator, kStatusPassive);
  gtk_widget_show(GTK_WIDGET(shell.window));
  gtk_window_close(shell.window);
}

GtkWidget* MenuItem(const std::string& label, GCallback callback) {
  GtkWidget* item = gtk_menu_item_new_with_label(label.c_str());
  g_signal_connect(item, "activate", callback, nullptr);
  gtk_widget_show(item);
  return item;
}

void BuildMenu() {
  if (shell.menu != nullptr) gtk_widget_destroy(shell.menu);
  shell.menu = gtk_menu_new();
  GtkMenuShell* items = GTK_MENU_SHELL(shell.menu);
  gtk_menu_shell_append(items, MenuItem(shell.show_label, G_CALLBACK(+[](GtkMenuItem*, gpointer) { ShowFromTray(); })));
  gtk_menu_shell_append(items, MenuItem(shell.play_pause_label, G_CALLBACK(+[](GtkMenuItem*, gpointer) { SendButton("playpause"); })));
  gtk_menu_shell_append(items, MenuItem(shell.next_label, G_CALLBACK(+[](GtkMenuItem*, gpointer) { SendButton("next"); })));
  GtkWidget* separator = gtk_separator_menu_item_new();
  gtk_widget_show(separator);
  gtk_menu_shell_append(items, separator);
  gtk_menu_shell_append(items, MenuItem(shell.exit_label, G_CALLBACK(+[](GtkMenuItem*, gpointer) { ExitFromTray(); })));
  if (shell.indicator != nullptr) shell.indicator_set_menu(shell.indicator, GTK_MENU(shell.menu));
}

// Whether a tray that shows StatusNotifier icons runs: GNOME has none
// without an extension, and a hidden window would then be lost.
bool TrayRuns() {
  g_autoptr(GDBusConnection) bus = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, nullptr);
  if (bus == nullptr) return false;
  g_autoptr(GVariant) answer = g_dbus_connection_call_sync(
      bus, "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "NameHasOwner",
      g_variant_new("(s)", "org.kde.StatusNotifierWatcher"), G_VARIANT_TYPE("(b)"), G_DBUS_CALL_FLAGS_NONE, 1000, nullptr, nullptr);
  gboolean owned = FALSE;
  if (answer != nullptr) g_variant_get(answer, "(b)", &owned);
  return owned;
}

// Hides the window behind a tray icon; false when there is no tray to
// bring it back from, and the window stays open.
bool HideToTray() {
  if (!TrayRuns() || !LoadIndicator()) return false;
  if (shell.indicator == nullptr) {
    // An icon name looked up in the app's own folder: tray hosts read a
    // name with a theme path, not every one reads a file path.
    const std::string folder = ExecutableDirectory() + "/data";
    shell.indicator = shell.indicator_new("lumtub", "lumtub", kCategoryApplicationStatus, folder.c_str());
    if (shell.indicator == nullptr) return false;
    if (shell.indicator_set_title != nullptr) shell.indicator_set_title(shell.indicator, "Lumtub");
    BuildMenu();
  }
  shell.indicator_set_status(shell.indicator, kStatusActive);
  gtk_widget_hide(GTK_WIDGET(shell.window));
  return true;
}

gboolean OnDelete(GtkWidget*, GdkEvent*, gpointer) {
  if (!shell.close_to_tray) return FALSE;
  // Without a tray Lumtub keeps running minimised, as it would in the tray.
  if (!HideToTray()) gtk_window_iconify(shell.window);
  return TRUE;
}

// Lumtub's own title bar: its minimise button goes to the tray directly, as
// Wayland would not tell the window it was minimised.
void OnMinimizeButton(GtkButton*, gpointer) {
  if (shell.minimize_to_tray && HideToTray()) return;
  gtk_window_iconify(shell.window);
}

void HookMinimizeButtons(GtkWidget* widget, gpointer) {
  if (GTK_IS_BUTTON(widget) && gtk_style_context_has_class(gtk_widget_get_style_context(widget), "minimize") &&
      g_object_get_data(G_OBJECT(widget), "lumtub-minimize") == nullptr) {
    g_signal_handlers_disconnect_matched(widget, G_SIGNAL_MATCH_DATA, 0, 0, nullptr, nullptr, shell.window);
    g_signal_connect(widget, "clicked", G_CALLBACK(OnMinimizeButton), nullptr);
    g_object_set_data(G_OBJECT(widget), "lumtub-minimize", GINT_TO_POINTER(1));
  }
  if (GTK_IS_CONTAINER(widget)) gtk_container_forall(GTK_CONTAINER(widget), HookMinimizeButtons, nullptr);
}

void HookHeaderBar() {
  GtkWidget* bar = gtk_window_get_titlebar(shell.window);
  if (bar != nullptr) HookMinimizeButtons(bar, nullptr);
}

// A minimised window goes to the tray; without a tray it stays minimised.
// Wayland tells no window that it was minimised, so there it stays too.
gboolean OnWindowState(GtkWidget*, GdkEventWindowState* event, gpointer) {
  if (event->changed_mask & GDK_WINDOW_STATE_MAXIMIZED) {
    SendFrame("maximized", fl_value_new_bool((event->new_window_state & GDK_WINDOW_STATE_MAXIMIZED) != 0));
  }
  if (event->changed_mask & GDK_WINDOW_STATE_FOCUSED) {
    SendFrame("active", fl_value_new_bool((event->new_window_state & GDK_WINDOW_STATE_FOCUSED) != 0));
  }
  g_idle_add(+[](gpointer) -> gboolean {
    HookHeaderBar();
    return G_SOURCE_REMOVE;
  }, nullptr);
  const bool minimised = (event->changed_mask & GDK_WINDOW_STATE_ICONIFIED) && (event->new_window_state & GDK_WINDOW_STATE_ICONIFIED);
  if (minimised && shell.minimize_to_tray) {
    g_idle_add(+[](gpointer) -> gboolean {
      if (shell.minimize_to_tray && gtk_widget_get_visible(GTK_WIDGET(shell.window))) HideToTray();
      return G_SOURCE_REMOVE;
    }, nullptr);
  }
  return FALSE;
}

// ---- MPRIS ----------------------------------------------------------------

constexpr char kIntrospection[] = R"XML(
<node>
  <interface name="org.mpris.MediaPlayer2">
    <method name="Raise"/>
    <method name="Quit"/>
    <property name="CanQuit" type="b" access="read"/>
    <property name="CanRaise" type="b" access="read"/>
    <property name="HasTrackList" type="b" access="read"/>
    <property name="Identity" type="s" access="read"/>
    <property name="DesktopEntry" type="s" access="read"/>
    <property name="SupportedUriSchemes" type="as" access="read"/>
    <property name="SupportedMimeTypes" type="as" access="read"/>
  </interface>
  <interface name="org.mpris.MediaPlayer2.Player">
    <method name="Next"/>
    <method name="Previous"/>
    <method name="Pause"/>
    <method name="PlayPause"/>
    <method name="Stop"/>
    <method name="Play"/>
    <method name="Seek"><arg direction="in" name="Offset" type="x"/></method>
    <method name="SetPosition"><arg direction="in" name="TrackId" type="o"/><arg direction="in" name="Position" type="x"/></method>
    <method name="OpenUri"><arg direction="in" name="Uri" type="s"/></method>
    <signal name="Seeked"><arg name="Position" type="x"/></signal>
    <property name="PlaybackStatus" type="s" access="read"/>
    <property name="Rate" type="d" access="read"/>
    <property name="Metadata" type="a{sv}" access="read"/>
    <property name="Volume" type="d" access="read"/>
    <property name="Position" type="x" access="read"/>
    <property name="MinimumRate" type="d" access="read"/>
    <property name="MaximumRate" type="d" access="read"/>
    <property name="CanGoNext" type="b" access="read"/>
    <property name="CanGoPrevious" type="b" access="read"/>
    <property name="CanPlay" type="b" access="read"/>
    <property name="CanPause" type="b" access="read"/>
    <property name="CanSeek" type="b" access="read"/>
    <property name="CanControl" type="b" access="read"/>
  </interface>
  <interface name="io.github.lumtub.Window">
    <method name="Minimized"/>
  </interface>
</node>)XML";

std::string TrackId() { return "/io/github/lumtub/track/" + std::to_string(shell.track); }

GVariant* Metadata() {
  GVariantBuilder builder;
  g_variant_builder_init(&builder, G_VARIANT_TYPE("a{sv}"));
  if (shell.status != "Stopped" || !shell.title.empty()) {
    g_variant_builder_add(&builder, "{sv}", "mpris:trackid", g_variant_new_object_path(TrackId().c_str()));
    g_variant_builder_add(&builder, "{sv}", "xesam:title", g_variant_new_string(shell.title.c_str()));
    const gchar* artists[] = {shell.artist.c_str(), nullptr};
    g_variant_builder_add(&builder, "{sv}", "xesam:artist", g_variant_new_strv(artists, -1));
    if (!shell.art.empty()) g_variant_builder_add(&builder, "{sv}", "mpris:artUrl", g_variant_new_string(shell.art.c_str()));
    if (shell.duration_ms > 0) g_variant_builder_add(&builder, "{sv}", "mpris:length", g_variant_new_int64(shell.duration_ms * 1000));
  }
  return g_variant_builder_end(&builder);
}

GVariant* PlayerProperty(const gchar* name) {
  const std::string property(name);
  const bool active = shell.status != "Stopped";
  if (property == "PlaybackStatus") return g_variant_new_string(shell.status.c_str());
  if (property == "Rate" || property == "Volume" || property == "MinimumRate" || property == "MaximumRate") return g_variant_new_double(1.0);
  if (property == "Metadata") return Metadata();
  if (property == "Position") return g_variant_new_int64(shell.position_ms * 1000);
  if (property == "CanGoNext") return g_variant_new_boolean(shell.can_next);
  if (property == "CanGoPrevious") return g_variant_new_boolean(shell.can_previous);
  if (property == "CanPlay" || property == "CanPause" || property == "CanSeek") return g_variant_new_boolean(active);
  if (property == "CanControl") return g_variant_new_boolean(TRUE);
  return nullptr;
}

GVariant* RootProperty(const gchar* name) {
  const std::string property(name);
  if (property == "CanQuit" || property == "CanRaise") return g_variant_new_boolean(TRUE);
  if (property == "HasTrackList") return g_variant_new_boolean(FALSE);
  if (property == "Identity") return g_variant_new_string("Lumtub");
  if (property == "DesktopEntry") return g_variant_new_string(APPLICATION_ID);
  if (property == "SupportedUriSchemes" || property == "SupportedMimeTypes") return g_variant_new_strv(nullptr, 0);
  return nullptr;
}

GVariant* GetProperty(GDBusConnection*, const gchar*, const gchar*, const gchar* interface, const gchar* name, GError**, gpointer) {
  return g_str_equal(interface, "org.mpris.MediaPlayer2") ? RootProperty(name) : PlayerProperty(name);
}

void SeekTo(int64_t ms) {
  if (ms < 0) ms = 0;
  if (shell.duration_ms > 0 && ms > shell.duration_ms) ms = shell.duration_ms;
  Send("seek", fl_value_new_int(ms));
}

void CallMethod(GDBusConnection*, const gchar*, const gchar*, const gchar*, const gchar* method, GVariant* parameters,
                GDBusMethodInvocation* invocation, gpointer) {
  const std::string name(method);
  if (name == "Raise") {
    ShowFromTray();
  } else if (name == "Minimized") {
    // KWin's script reports a minimised window, which Wayland itself does not.
    if (shell.minimize_to_tray && gtk_widget_get_visible(GTK_WIDGET(shell.window))) {
      g_idle_add(+[](gpointer) -> gboolean {
        if (shell.minimize_to_tray && gtk_widget_get_visible(GTK_WIDGET(shell.window))) HideToTray();
        return G_SOURCE_REMOVE;
      }, nullptr);
    }
  } else if (name == "Quit") {
    ExitFromTray();
  } else if (name == "Next") {
    SendButton("next");
  } else if (name == "Previous") {
    SendButton("previous");
  } else if (name == "Pause") {
    SendButton("pause");
  } else if (name == "PlayPause") {
    SendButton("playpause");
  } else if (name == "Stop") {
    SendButton("stop");
  } else if (name == "Play") {
    SendButton("play");
  } else if (name == "Seek") {
    gint64 offset = 0;
    g_variant_get(parameters, "(x)", &offset);
    SeekTo(shell.position_ms + offset / 1000);
  } else if (name == "SetPosition") {
    const gchar* track = nullptr;
    gint64 position = 0;
    g_variant_get(parameters, "(&ox)", &track, &position);
    if (TrackId() == track) SeekTo(position / 1000);
  }
  g_dbus_method_invocation_return_value(invocation, nullptr);
}

void PlayerChanged(std::initializer_list<const char*> names) {
  if (shell.bus == nullptr) return;
  GVariantBuilder changed;
  g_variant_builder_init(&changed, G_VARIANT_TYPE("a{sv}"));
  for (const char* name : names) {
    GVariant* value = PlayerProperty(name);
    if (value != nullptr) g_variant_builder_add(&changed, "{sv}", name, value);
  }
  g_dbus_connection_emit_signal(shell.bus, nullptr, kMprisPath, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                                g_variant_new("(sa{sv}as)", "org.mpris.MediaPlayer2.Player", &changed, nullptr), nullptr);
}

void OnBus(GDBusConnection* connection, const gchar*, gpointer) {
  GDBusNodeInfo* node = g_dbus_node_info_new_for_xml(kIntrospection, nullptr);
  if (node == nullptr) return;
  static const GDBusInterfaceVTable vtable = {CallMethod, GetProperty, nullptr, {}};
  for (int i = 0; node->interfaces[i] != nullptr; i++) {
    g_dbus_connection_register_object(connection, kMprisPath, node->interfaces[i], &vtable, nullptr, nullptr, nullptr);
  }
  g_dbus_node_info_unref(node);
  shell.bus = connection;
}

void StartMpris() {
  // A second Lumtub takes a name of its own, as the specification asks.
  const std::string name = "org.mpris.MediaPlayer2.lumtub.instance" + std::to_string(getpid());
  shell.bus_name = g_bus_own_name(G_BUS_TYPE_SESSION, name.c_str(), G_BUS_NAME_OWNER_FLAGS_NONE, OnBus, nullptr, nullptr, nullptr, nullptr);
}

// ---- Fonts ----------------------------------------------------------------

FlValue* SystemFontFamilies() {
  std::set<std::string> names;
  FcPattern* pattern = FcPatternCreate();
  FcObjectSet* objects = FcObjectSetBuild(FC_FAMILY, nullptr);
  FcFontSet* fonts = FcFontList(nullptr, pattern, objects);
  if (fonts != nullptr) {
    for (int i = 0; i < fonts->nfont; i++) {
      FcChar8* family = nullptr;
      if (FcPatternGetString(fonts->fonts[i], FC_FAMILY, 0, &family) == FcResultMatch && family != nullptr) {
        names.insert(reinterpret_cast<const char*>(family));
      }
    }
    FcFontSetDestroy(fonts);
  }
  FcObjectSetDestroy(objects);
  FcPatternDestroy(pattern);
  FlValue* list = fl_value_new_list();
  for (const auto& name : names) fl_value_append_take(list, fl_value_new_string(name.c_str()));
  return list;
}

// ---- Channel --------------------------------------------------------------

std::string StringArg(FlValue* args, const char* key) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) return "";
  FlValue* value = fl_value_lookup_string(args, key);
  return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_STRING ? fl_value_get_string(value) : "";
}

bool BoolArg(FlValue* args, const char* key) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) return false;
  FlValue* value = fl_value_lookup_string(args, key);
  return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_BOOL && fl_value_get_bool(value);
}

int64_t IntArg(FlValue* args, const char* key) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) return 0;
  FlValue* value = fl_value_lookup_string(args, key);
  return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_INT ? fl_value_get_int(value) : 0;
}

double DoubleArg(FlValue* args, const char* key) {
  FlValue* value = key != nullptr && args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP ? fl_value_lookup_string(args, key) : args;
  if (value == nullptr) return 0;
  if (fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT) return fl_value_get_float(value);
  if (fl_value_get_type(value) == FL_VALUE_TYPE_INT) return static_cast<double>(fl_value_get_int(value));
  return 0;
}

bool BoolValue(FlValue* value) { return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_BOOL && fl_value_get_bool(value); }

// Keeps the window's ratio while it is resized; 0 lets it go.
void KeepAspect(double aspect) {
  if (aspect <= 0) {
    gtk_window_set_geometry_hints(shell.window, nullptr, nullptr, static_cast<GdkWindowHints>(0));
    gtk_widget_set_size_request(GTK_WIDGET(shell.window), 480, 360);
    return;
  }
  GdkGeometry geometry = {};
  geometry.min_width = 120;
  geometry.min_height = 120;
  geometry.min_aspect = aspect;
  geometry.max_aspect = aspect;
  gtk_widget_set_size_request(GTK_WIDGET(shell.window), -1, -1);
  gtk_window_set_geometry_hints(shell.window, nullptr, &geometry, static_cast<GdkWindowHints>(GDK_HINT_ASPECT | GDK_HINT_MIN_SIZE));
}

void EnterPip(double aspect, int width, int height) {
  GtkWindow* window = shell.window;
  if (window == nullptr || shell.pip) return;
  shell.pip = true;
  shell.was_maximized = gtk_window_is_maximized(window);
  // Unmaximizing takes effect later; the size read now would still be the
  // maximized one, and the window comes back maximized anyway.
  gtk_window_get_position(window, &shell.before_x, &shell.before_y);
  gtk_window_get_size(window, &shell.before_width, &shell.before_height);
  if (shell.was_maximized) gtk_window_unmaximize(window);
  gtk_window_set_decorated(window, FALSE);
  gtk_window_set_keep_above(window, TRUE);
  KeepAspect(aspect);
  gtk_window_resize(window, width, height);
  // Wayland compositors place windows themselves and ignore this.
  GdkWindow* surface = gtk_widget_get_window(GTK_WIDGET(window));
  GdkMonitor* monitor = surface != nullptr ? gdk_display_get_monitor_at_window(gdk_window_get_display(surface), surface) : nullptr;
  if (monitor == nullptr) return;
  GdkRectangle area;
  gdk_monitor_get_workarea(monitor, &area);
  int x = area.x + area.width - width - 16, y = area.y + area.height - height - 16;
  if (shell.has_last) {
    x = std::max(area.x, std::min(shell.last_x, area.x + area.width - width));
    y = std::max(area.y, std::min(shell.last_y, area.y + area.height - height));
  }
  gtk_window_move(window, x, y);
}

void ExitPip(bool keep_on_top) {
  GtkWindow* window = shell.window;
  if (window == nullptr || !shell.pip) return;
  shell.pip = false;
  gtk_window_get_position(window, &shell.last_x, &shell.last_y);
  shell.has_last = true;
  KeepAspect(0);
  gtk_window_set_decorated(window, !shell.custom_frame);
  gtk_window_set_keep_above(window, keep_on_top);
  shell.above = keep_on_top;
  if (shell.was_maximized) {
    gtk_window_maximize(window);
  } else {
    gtk_window_resize(window, shell.before_width, shell.before_height);
    gtk_window_move(window, shell.before_x, shell.before_y);
  }
}

void SetPipAspect(double aspect) {
  if (shell.window == nullptr || !shell.pip || aspect <= 0) return;
  int width = 0, height = 0;
  gtk_window_get_size(shell.window, &width, &height);
  KeepAspect(aspect);
  gtk_window_resize(shell.window, width, static_cast<int>(width / aspect + 0.5));
}

// Moves or resizes the window with the pointer, from a press on the picture.
void BeginDrag(bool resize) {
  GtkWindow* window = shell.window;
  if (window == nullptr) return;
  GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(window));
  GdkDevice* pointer = gdk_seat_get_pointer(gdk_display_get_default_seat(display));
  int x = 0, y = 0;
  gdk_device_get_position(pointer, nullptr, &x, &y);
  if (resize) {
    gtk_window_begin_resize_drag(window, GDK_WINDOW_EDGE_SOUTH_EAST, 1, x, y, GDK_CURRENT_TIME);
  } else {
    gtk_window_begin_move_drag(window, 1, x, y, GDK_CURRENT_TIME);
  }
}

// Keeps the screen from blanking or locking while [on]: GTK asks the
// desktop's session manager, the portal or the screen saver, whichever
// answers.
void SetKeepAwake(bool on) {
  GtkApplication* application = shell.window != nullptr ? gtk_window_get_application(shell.window) : nullptr;
  if (application == nullptr) return;
  if (on && shell.inhibit == 0) {
    shell.inhibit = gtk_application_inhibit(application, shell.window, GTK_APPLICATION_INHIBIT_IDLE, "Playing a video");
  } else if (!on && shell.inhibit != 0) {
    gtk_application_uninhibit(application, shell.inhibit);
    shell.inhibit = 0;
  }
}

// ---- Own title bar ---------------------------------------------------------

// Removes the system title bar (the header bar too); the bar and the edges
// are Flutter's, which asks for moves and resizes below.
void SetCustomFrame(bool on) {
  shell.custom_frame = on;
  if (shell.pip) return;
  GtkWidget* bar = gtk_window_get_titlebar(shell.window);
  if (bar != nullptr) gtk_widget_set_visible(bar, !on);
  gtk_window_set_decorated(shell.window, !on);
}

GdkWindowEdge EdgeOf(const std::string& name) {
  if (name == "top") return GDK_WINDOW_EDGE_NORTH;
  if (name == "bottom") return GDK_WINDOW_EDGE_SOUTH;
  if (name == "left") return GDK_WINDOW_EDGE_WEST;
  if (name == "right") return GDK_WINDOW_EDGE_EAST;
  if (name == "topLeft") return GDK_WINDOW_EDGE_NORTH_WEST;
  if (name == "topRight") return GDK_WINDOW_EDGE_NORTH_EAST;
  if (name == "bottomLeft") return GDK_WINDOW_EDGE_SOUTH_WEST;
  return GDK_WINDOW_EDGE_SOUTH_EAST;
}

// Moves, or resizes from [edge], with the pointer from the press that is
// going on.
void BeginFrameDrag(bool resize, GdkWindowEdge edge) {
  GtkWindow* window = shell.window;
  if (window == nullptr) return;
  int x = 0, y = 0;
  guint32 time = GDK_CURRENT_TIME;
  if (shell.press != nullptr) {
    x = static_cast<int>(shell.press->button.x_root);
    y = static_cast<int>(shell.press->button.y_root);
    time = shell.press->button.time;
  } else {
    GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(window));
    gdk_device_get_position(gdk_seat_get_pointer(gdk_display_get_default_seat(display)), nullptr, &x, &y);
  }
  if (resize) {
    gtk_window_begin_resize_drag(window, edge, 1, x, y, time);
  } else {
    gtk_window_begin_move_drag(window, 1, x, y, time);
  }
}

void HandleFrameCall(FlMethodChannel*, FlMethodCall* call, gpointer) {
  const std::string method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  GtkWindow* window = shell.window;
  if (window == nullptr) {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  if (method == "state") {
    g_autoptr(FlValue) state = fl_value_new_map();
    fl_value_set_string_take(state, "maximized", fl_value_new_bool(gtk_window_is_maximized(window)));
    fl_value_set_string_take(state, "active", fl_value_new_bool(gtk_window_is_active(window)));
    fl_method_call_respond_success(call, state, nullptr);
    return;
  }
  if (method == "setCustom") {
    SetCustomFrame(BoolValue(args));
  } else if (method == "minimize") {
    OnMinimizeButton(nullptr, nullptr);
  } else if (method == "toggleMaximize") {
    if (gtk_window_is_maximized(window)) {
      gtk_window_unmaximize(window);
    } else {
      gtk_window_maximize(window);
    }
  } else if (method == "close") {
    // The same delete-event as the system button, so close-to-tray applies.
    gtk_window_close(window);
  } else if (method == "startDrag") {
    BeginFrameDrag(false, GDK_WINDOW_EDGE_NORTH);
  } else if (method == "startResize") {
    const bool named = args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_STRING;
    BeginFrameDrag(true, EdgeOf(named ? fl_value_get_string(args) : ""));
  } else if (method == "setCaption") {
    // Hit-testing is Windows' own.
  } else {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  fl_method_call_respond_success(call, nullptr, nullptr);
}

gboolean OnViewButtonPress(GtkWidget*, GdkEventButton* event, gpointer) {
  if (event->type == GDK_BUTTON_PRESS && event->button == 1) {
    if (shell.press != nullptr) gdk_event_free(shell.press);
    shell.press = gdk_event_copy(reinterpret_cast<GdkEvent*>(event));
  }
  return FALSE;
}

void HandleCall(FlMethodChannel*, FlMethodCall* call, gpointer) {
  const std::string method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  if (method == "listSystemFonts") {
    g_autoptr(FlValue) fonts = SystemFontFamilies();
    fl_method_call_respond_success(call, fonts, nullptr);
    return;
  }
  if (method == "setTray") {
    shell.close_to_tray = BoolArg(args, "enabled");
    shell.minimize_to_tray = BoolArg(args, "minimize");
    shell.show_label = StringArg(args, "show");
    shell.play_pause_label = StringArg(args, "playPause");
    shell.next_label = StringArg(args, "next");
    shell.exit_label = StringArg(args, "exit");
    if (shell.indicator != nullptr) {
      BuildMenu();
      if (!shell.close_to_tray && !shell.minimize_to_tray && !gtk_widget_get_visible(GTK_WIDGET(shell.window))) ShowFromTray();
      if (!shell.close_to_tray && !shell.minimize_to_tray) shell.indicator_set_status(shell.indicator, kStatusPassive);
    }
  } else if (method == "setMetadata") {
    shell.title = StringArg(args, "title");
    shell.artist = StringArg(args, "artist");
    shell.art = StringArg(args, "thumbnail");
    shell.track++;
    shell.position_ms = 0;
    PlayerChanged({"Metadata"});
  } else if (method == "setStatus") {
    const std::string status = args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_STRING ? fl_value_get_string(args) : "";
    shell.status = status == "playing" ? "Playing" : status == "paused" ? "Paused" : "Stopped";
    if (shell.status == "Stopped") shell.title.clear();
    PlayerChanged({"PlaybackStatus", "Metadata", "CanPlay", "CanPause", "CanSeek"});
  } else if (method == "setTimeline") {
    const int64_t position = IntArg(args, "position");
    const int64_t duration = IntArg(args, "duration");
    const bool jumped = std::llabs(position - shell.position_ms) > 3000;
    shell.position_ms = position;
    if (duration != shell.duration_ms) {
      shell.duration_ms = duration;
      PlayerChanged({"Metadata"});
    }
    if (jumped && shell.bus != nullptr) {
      g_dbus_connection_emit_signal(shell.bus, nullptr, kMprisPath, "org.mpris.MediaPlayer2.Player", "Seeked",
                                    g_variant_new("(x)", position * 1000), nullptr);
    }
  } else if (method == "setKeepAwake") {
    SetKeepAwake(BoolValue(args));
  } else if (method == "setTopmost") {
    shell.above = BoolValue(args);
    if (shell.window != nullptr) gtk_window_set_keep_above(shell.window, shell.above);
  } else if (method == "enterPip") {
    EnterPip(DoubleArg(args, "aspect"), static_cast<int>(DoubleArg(args, "width") + 0.5), static_cast<int>(DoubleArg(args, "height") + 0.5));
  } else if (method == "exitPip") {
    ExitPip(BoolValue(args));
  } else if (method == "setPipAspect") {
    SetPipAspect(DoubleArg(args, nullptr));
  } else if (method == "startDrag" || method == "startResize") {
    BeginDrag(method == "startResize");
  } else if (method == "setButtons") {
    shell.can_next = BoolArg(args, "next");
    shell.can_previous = BoolArg(args, "previous");
    PlayerChanged({"CanGoNext", "CanGoPrevious"});
  } else {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  fl_method_call_respond_success(call, nullptr, nullptr);
}

}  // namespace

void linux_shell_attach(GtkWindow* window) {
  shell.window = window;
  // The display is open: programs Lumtub starts, such as the browser for
  // signing in, keep the desktop's own choice.
  if (getenv("LUMTUB_X11") != nullptr) unsetenv("GDK_BACKEND");
  g_signal_connect(window, "delete-event", G_CALLBACK(OnDelete), nullptr);
  g_signal_connect(window, "window-state-event", G_CALLBACK(OnWindowState), nullptr);
  g_signal_connect(window, "map", G_CALLBACK(+[](GtkWidget*, gpointer) { HookHeaderBar(); }), nullptr);
  gtk_window_set_icon_from_file(window, IconPath().c_str(), nullptr);
  StartMpris();
}

void linux_shell_connect(FlView* view) {
  FlEngine* engine = fl_view_get_engine(view);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  shell.channel = fl_method_channel_new(fl_engine_get_binary_messenger(engine), kChannel, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(shell.channel, HandleCall, nullptr, nullptr);
  shell.frame_channel = fl_method_channel_new(fl_engine_get_binary_messenger(engine), kFrameChannel, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(shell.frame_channel, HandleFrameCall, nullptr, nullptr);
  g_signal_connect(view, "button-press-event", G_CALLBACK(OnViewButtonPress), nullptr);
}

void linux_shell_present() {
  if (shell.window != nullptr) ShowFromTray();
}
