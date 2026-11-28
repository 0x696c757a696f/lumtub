#include "linux_shell.h"

#include <dlfcn.h>
#include <fontconfig/fontconfig.h>
#include <unistd.h>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <set>
#include <string>

#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif
#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/gdkwayland.h>
#include <wayland-client-core.h>
#endif

namespace {

constexpr char kChannel[] = "lumtub/windows_shell";
constexpr char kFrameChannel[] = "lumtub/window_frame";
constexpr char kMprisPath[] = "/org/mpris/MediaPlayer2";

// libayatana-appindicator3, loaded when the system has it.
using IndicatorNew = void* (*)(const char*, const char*, int, const char*);
using IndicatorSetStatus = void (*)(void*, int);
using IndicatorSetMenu = void (*)(void*, GtkMenu*);
using IndicatorSetTitle = void (*)(void*, const char*);
using IndicatorSetIcon = void (*)(void*, const char*, const char*);
constexpr int kCategoryApplicationStatus = 0;
constexpr int kStatusPassive = 0;
constexpr int kStatusActive = 1;

struct Shell {
  GtkWindow* window = nullptr;
  FlView* view = nullptr;
  // While the pointer is hidden over the video (HidePointer): the pointer
  // to give back once it moves, and where it was hidden.
  guint pointer_watch = 0;
  GdkCursor* pointer_before = nullptr;
  GdkCursor* pointer_blank = nullptr;
  int hidden_x = 0;
  int hidden_y = 0;
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
  IndicatorSetIcon indicator_set_icon = nullptr;
  // The icon file in data/ without .png: lumtub, lumtub-tabor or lumtub-gold.
  std::string icon_name = "lumtub";
  void* indicator = nullptr;
  GtkWidget* menu = nullptr;
  // Whether a StatusNotifier host runs, kept up to date by a name watch
  // instead of asking D-Bus and waiting for the answer.
  bool tray_runs = false;
  guint tray_watch = 0;

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

  // The window's size and place when it is neither maximised nor picture in
  // picture, kept in <data dir>/config/window.txt.
  bool has_normal = false;
  int normal_x = 0, normal_y = 0, normal_width = 0, normal_height = 0;
  guint save_timer = 0;

  // The last desktop glass asked for, set again when the window is shown:
  // on Wayland a hidden window loses its surface and the blur with it.
  bool glass_set = false;
  bool glass_on = false;
  bool glass_blur = false;
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

std::string IconPath() {
  return ExecutableDirectory() + "/data/" + shell.icon_name + ".png";
}

void Send(const char* method, FlValue* argument) {
  if (shell.channel == nullptr) {
    fl_value_unref(argument);
    return;
  }
  fl_method_channel_invoke_method(shell.channel, method, argument, nullptr,
                                  nullptr, nullptr);
  fl_value_unref(argument);
}

void SendFrame(const char* method, FlValue* argument) {
  if (shell.frame_channel == nullptr) {
    fl_value_unref(argument);
    return;
  }
  fl_method_channel_invoke_method(shell.frame_channel, method, argument,
                                  nullptr, nullptr, nullptr);
  fl_value_unref(argument);
}

void SendButton(const char* button) {
  Send("button", fl_value_new_string(button));
}

// ---- Tray -----------------------------------------------------------------

bool LoadIndicator() {
  if (shell.indicator_loaded) return shell.indicator_new != nullptr;
  shell.indicator_loaded = true;
  void* library = nullptr;
  for (const char* name :
       {"libayatana-appindicator3.so.1", "libappindicator3.so.1"}) {
    library = dlopen(name, RTLD_NOW | RTLD_LOCAL);
    if (library != nullptr) break;
  }
  if (library == nullptr) return false;
  shell.indicator_new = reinterpret_cast<IndicatorNew>(
      dlsym(library, "app_indicator_new_with_path"));
  shell.indicator_set_status = reinterpret_cast<IndicatorSetStatus>(
      dlsym(library, "app_indicator_set_status"));
  shell.indicator_set_menu = reinterpret_cast<IndicatorSetMenu>(
      dlsym(library, "app_indicator_set_menu"));
  shell.indicator_set_title = reinterpret_cast<IndicatorSetTitle>(
      dlsym(library, "app_indicator_set_title"));
  shell.indicator_set_icon = reinterpret_cast<IndicatorSetIcon>(
      dlsym(library, "app_indicator_set_icon_full"));
  if (shell.indicator_new == nullptr || shell.indicator_set_status == nullptr ||
      shell.indicator_set_menu == nullptr) {
    shell.indicator_new = nullptr;
    return false;
  }
  return true;
}

// Whether the window is there and shown; it is gone once destroyed.
bool WindowVisible() {
  return shell.window != nullptr &&
         gtk_widget_get_visible(GTK_WIDGET(shell.window));
}

void ShowFromTray() {
  if (shell.window == nullptr) return;
  if (shell.indicator != nullptr && !shell.close_to_tray &&
      !shell.minimize_to_tray)
    shell.indicator_set_status(shell.indicator, kStatusPassive);
  gtk_widget_show(GTK_WIDGET(shell.window));
  gtk_window_present(shell.window);
}

void ExitFromTray() {
  if (shell.window == nullptr) return;
  // The normal close path, so Dart saves progress and releases the player.
  shell.close_to_tray = false;
  shell.minimize_to_tray = false;
  if (shell.indicator != nullptr)
    shell.indicator_set_status(shell.indicator, kStatusPassive);
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
  gtk_menu_shell_append(
      items, MenuItem(shell.show_label, G_CALLBACK(+[](GtkMenuItem*, gpointer) {
                        ShowFromTray();
                      })));
  gtk_menu_shell_append(items, MenuItem(shell.play_pause_label,
                                        G_CALLBACK(+[](GtkMenuItem*, gpointer) {
                                          SendButton("playpause");
                                        })));
  gtk_menu_shell_append(
      items, MenuItem(shell.next_label, G_CALLBACK(+[](GtkMenuItem*, gpointer) {
                        SendButton("next");
                      })));
  GtkWidget* separator = gtk_separator_menu_item_new();
  gtk_widget_show(separator);
  gtk_menu_shell_append(items, separator);
  gtk_menu_shell_append(
      items, MenuItem(shell.exit_label, G_CALLBACK(+[](GtkMenuItem*, gpointer) {
                        ExitFromTray();
                      })));
  if (shell.indicator != nullptr)
    shell.indicator_set_menu(shell.indicator, GTK_MENU(shell.menu));
}

// Whether a tray that shows StatusNotifier icons runs: GNOME has none
// without an extension, and a hidden window would then be lost.
bool TrayRuns() { return shell.tray_runs; }

bool ShowTrayIcon();

void WatchTray() {
  if (shell.tray_watch != 0) return;
  shell.tray_watch = g_bus_watch_name(
      G_BUS_TYPE_SESSION, "org.kde.StatusNotifierWatcher",
      G_BUS_NAME_WATCHER_FLAGS_NONE,
      +[](GDBusConnection*, const gchar*, const gchar*, gpointer) {
        shell.tray_runs = true;
        // Tray settings that came before the answer show the icon now.
        if (shell.close_to_tray || shell.minimize_to_tray) ShowTrayIcon();
      },
      +[](GDBusConnection*, const gchar*, gpointer) {
        shell.tray_runs = false;
      },
      nullptr, nullptr);
}

// Shows the tray icon; false when there is no tray to show it in.
bool ShowTrayIcon() {
  if (!TrayRuns() || !LoadIndicator()) return false;
  if (shell.indicator == nullptr) {
    // An icon name looked up in the app's own folder: tray hosts read a
    // name with a theme path, not every one reads a file path.
    const std::string folder = ExecutableDirectory() + "/data";
    shell.indicator =
        shell.indicator_new("lumtub", shell.icon_name.c_str(),
                            kCategoryApplicationStatus, folder.c_str());
    if (shell.indicator == nullptr) return false;
    if (shell.indicator_set_title != nullptr)
      shell.indicator_set_title(shell.indicator, "Lumtub");
    BuildMenu();
  }
  shell.indicator_set_status(shell.indicator, kStatusActive);
  return true;
}

// Hides the window behind a tray icon; false when there is no tray to
// bring it back from, and the window stays open.
bool HideToTray() {
  if (shell.window == nullptr || !ShowTrayIcon()) return false;
  gtk_widget_hide(GTK_WIDGET(shell.window));
  return true;
}

// ---- Window size and place ------------------------------------------------

constexpr int kMinWidth = 480, kMinHeight = 360;

std::string WindowStateFile() {
  const char* home = getenv("LUMTUB_HOME");
  const char* data = getenv("XDG_DATA_HOME");
  const char* user = getenv("HOME");
  std::string root;
  if (home != nullptr && home[0] != '\0') {
    root = home;
  } else if (data != nullptr && data[0] == '/') {
    root = std::string(data) + "/lumtub";
  } else if (user != nullptr && user[0] == '/') {
    root = std::string(user) + "/.local/share/lumtub";
  } else {
    return "";
  }
  return root + "/config/window.txt";
}

bool OnWayland() {
#ifdef GDK_WINDOWING_WAYLAND
  return GDK_IS_WAYLAND_DISPLAY(gdk_display_get_default());
#else
  return false;
#endif
}

void SaveWindowState() {
  if (shell.window == nullptr || shell.pip || !shell.has_normal) return;
  GdkWindow* surface = gtk_widget_get_window(GTK_WIDGET(shell.window));
  if (surface != nullptr &&
      (gdk_window_get_state(surface) & GDK_WINDOW_STATE_FULLSCREEN))
    return;
  const std::string path = WindowStateFile();
  if (path.empty()) return;
  g_autofree gchar* directory = g_path_get_dirname(path.c_str());
  g_mkdir_with_parents(directory, 0755);
  FILE* file = fopen(path.c_str(), "w");
  if (file == nullptr) return;
  fprintf(file, "%d %d %d %d %d\n", shell.normal_width, shell.normal_height,
          shell.normal_x, shell.normal_y,
          gtk_window_is_maximized(shell.window) ? 1 : 0);
  fclose(file);
}

void SaveWindowStateSoon() {
  if (shell.save_timer != 0) return;
  shell.save_timer = g_timeout_add(
      1000,
      +[](gpointer) -> gboolean {
        shell.save_timer = 0;
        SaveWindowState();
        return G_SOURCE_REMOVE;
      },
      nullptr);
}

gboolean OnConfigure(GtkWidget*, GdkEventConfigure*, gpointer) {
  GtkWindow* window = shell.window;
  if (window == nullptr || shell.pip || gtk_window_is_maximized(window))
    return FALSE;
  GdkWindow* surface = gtk_widget_get_window(GTK_WIDGET(window));
  if (surface == nullptr ||
      (gdk_window_get_state(surface) &
       (GDK_WINDOW_STATE_FULLSCREEN | GDK_WINDOW_STATE_TILED)))
    return FALSE;
  gtk_window_get_size(window, &shell.normal_width, &shell.normal_height);
  gtk_window_get_position(window, &shell.normal_x, &shell.normal_y);
  shell.has_normal = true;
  SaveWindowStateSoon();
  return FALSE;
}

gboolean OnDelete(GtkWidget*, GdkEvent*, gpointer) {
  SaveWindowState();
  if (!shell.close_to_tray) return FALSE;
  // Without a tray Lumtub keeps running minimised, as it would in the tray.
  if (!HideToTray()) gtk_window_iconify(shell.window);
  return TRUE;
}

// Lumtub's own title bar: its minimise button goes to the tray directly, as
// Wayland would not tell the window it was minimised.
void OnMinimizeButton(GtkButton*, gpointer) {
  if (shell.window == nullptr) return;
  if (shell.minimize_to_tray && HideToTray()) return;
  gtk_window_iconify(shell.window);
}

void HookMinimizeButtons(GtkWidget* widget, gpointer) {
  if (GTK_IS_BUTTON(widget) &&
      gtk_style_context_has_class(gtk_widget_get_style_context(widget),
                                  "minimize") &&
      g_object_get_data(G_OBJECT(widget), "lumtub-minimize") == nullptr) {
    g_signal_handlers_disconnect_matched(widget, G_SIGNAL_MATCH_DATA, 0, 0,
                                         nullptr, nullptr, shell.window);
    g_signal_connect(widget, "clicked", G_CALLBACK(OnMinimizeButton), nullptr);
    g_object_set_data(G_OBJECT(widget), "lumtub-minimize", GINT_TO_POINTER(1));
  }
  if (GTK_IS_CONTAINER(widget))
    gtk_container_forall(GTK_CONTAINER(widget), HookMinimizeButtons, nullptr);
}

void HookHeaderBar() {
  if (shell.window == nullptr) return;
  GtkWidget* bar = gtk_window_get_titlebar(shell.window);
  if (bar != nullptr) HookMinimizeButtons(bar, nullptr);
}

// A minimised window goes to the tray; without a tray it stays minimised.
// Wayland tells no window that it was minimised, so there it stays too.
gboolean OnWindowState(GtkWidget*, GdkEventWindowState* event, gpointer) {
  if (event->changed_mask & GDK_WINDOW_STATE_MAXIMIZED) {
    SaveWindowStateSoon();
    SendFrame("maximized",
              fl_value_new_bool(
                  (event->new_window_state & GDK_WINDOW_STATE_MAXIMIZED) != 0));
  }
  if (event->changed_mask & GDK_WINDOW_STATE_FOCUSED) {
    SendFrame("active", fl_value_new_bool((event->new_window_state &
                                           GDK_WINDOW_STATE_FOCUSED) != 0));
  }
  g_idle_add(
      +[](gpointer) -> gboolean {
        HookHeaderBar();
        return G_SOURCE_REMOVE;
      },
      nullptr);
  const bool minimised = (event->changed_mask & GDK_WINDOW_STATE_ICONIFIED) &&
                         (event->new_window_state & GDK_WINDOW_STATE_ICONIFIED);
  if (minimised && shell.minimize_to_tray) {
    g_idle_add(
        +[](gpointer) -> gboolean {
          if (shell.minimize_to_tray && WindowVisible()) HideToTray();
          return G_SOURCE_REMOVE;
        },
        nullptr);
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

std::string TrackId() {
  return "/io/github/lumtub/track/" + std::to_string(shell.track);
}

GVariant* Metadata() {
  GVariantBuilder builder;
  g_variant_builder_init(&builder, G_VARIANT_TYPE("a{sv}"));
  if (shell.status != "Stopped" || !shell.title.empty()) {
    g_variant_builder_add(&builder, "{sv}", "mpris:trackid",
                          g_variant_new_object_path(TrackId().c_str()));
    g_variant_builder_add(&builder, "{sv}", "xesam:title",
                          g_variant_new_string(shell.title.c_str()));
    const gchar* artists[] = {shell.artist.c_str(), nullptr};
    g_variant_builder_add(&builder, "{sv}", "xesam:artist",
                          g_variant_new_strv(artists, -1));
    if (!shell.art.empty())
      g_variant_builder_add(&builder, "{sv}", "mpris:artUrl",
                            g_variant_new_string(shell.art.c_str()));
    if (shell.duration_ms > 0)
      g_variant_builder_add(&builder, "{sv}", "mpris:length",
                            g_variant_new_int64(shell.duration_ms * 1000));
  }
  return g_variant_builder_end(&builder);
}

GVariant* PlayerProperty(const gchar* name) {
  const std::string property(name);
  const bool active = shell.status != "Stopped";
  if (property == "PlaybackStatus")
    return g_variant_new_string(shell.status.c_str());
  if (property == "Rate" || property == "Volume" || property == "MinimumRate" ||
      property == "MaximumRate")
    return g_variant_new_double(1.0);
  if (property == "Metadata") return Metadata();
  if (property == "Position")
    return g_variant_new_int64(shell.position_ms * 1000);
  if (property == "CanGoNext") return g_variant_new_boolean(shell.can_next);
  if (property == "CanGoPrevious")
    return g_variant_new_boolean(shell.can_previous);
  if (property == "CanPlay" || property == "CanPause" || property == "CanSeek")
    return g_variant_new_boolean(active);
  if (property == "CanControl") return g_variant_new_boolean(TRUE);
  return nullptr;
}

GVariant* RootProperty(const gchar* name) {
  const std::string property(name);
  if (property == "CanQuit" || property == "CanRaise")
    return g_variant_new_boolean(TRUE);
  if (property == "HasTrackList") return g_variant_new_boolean(FALSE);
  if (property == "Identity") return g_variant_new_string("Lumtub");
  if (property == "DesktopEntry") return g_variant_new_string(APPLICATION_ID);
  if (property == "SupportedUriSchemes" || property == "SupportedMimeTypes")
    return g_variant_new_strv(nullptr, 0);
  return nullptr;
}

GVariant* GetProperty(GDBusConnection*, const gchar*, const gchar*,
                      const gchar* interface, const gchar* name, GError**,
                      gpointer) {
  return g_str_equal(interface, "org.mpris.MediaPlayer2")
             ? RootProperty(name)
             : PlayerProperty(name);
}

void SeekTo(int64_t ms) {
  if (ms < 0) ms = 0;
  if (shell.duration_ms > 0 && ms > shell.duration_ms) ms = shell.duration_ms;
  Send("seek", fl_value_new_int(ms));
}

void CallMethod(GDBusConnection*, const gchar*, const gchar*, const gchar*,
                const gchar* method, GVariant* parameters,
                GDBusMethodInvocation* invocation, gpointer) {
  const std::string name(method);
  if (name == "Raise") {
    ShowFromTray();
  } else if (name == "Minimized") {
    // KWin's script reports a minimised window, which Wayland itself does not.
    if (shell.minimize_to_tray && WindowVisible()) {
      g_idle_add(
          +[](gpointer) -> gboolean {
            if (shell.minimize_to_tray && WindowVisible()) HideToTray();
            return G_SOURCE_REMOVE;
          },
          nullptr);
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
  g_dbus_connection_emit_signal(
      shell.bus, nullptr, kMprisPath, "org.freedesktop.DBus.Properties",
      "PropertiesChanged",
      g_variant_new("(sa{sv}as)", "org.mpris.MediaPlayer2.Player", &changed,
                    nullptr),
      nullptr);
}

void OnBus(GDBusConnection* connection, const gchar*, gpointer) {
  GDBusNodeInfo* node = g_dbus_node_info_new_for_xml(kIntrospection, nullptr);
  if (node == nullptr) return;
  static const GDBusInterfaceVTable vtable = {
      CallMethod, GetProperty, nullptr, {}};
  for (int i = 0; node->interfaces[i] != nullptr; i++) {
    g_dbus_connection_register_object(connection, kMprisPath,
                                      node->interfaces[i], &vtable, nullptr,
                                      nullptr, nullptr);
  }
  g_dbus_node_info_unref(node);
  shell.bus = connection;
}

void StartMpris() {
  // A second Lumtub takes a name of its own, as the specification asks.
  const std::string name =
      "org.mpris.MediaPlayer2.lumtub.instance" + std::to_string(getpid());
  shell.bus_name = g_bus_own_name(G_BUS_TYPE_SESSION, name.c_str(),
                                  G_BUS_NAME_OWNER_FLAGS_NONE, OnBus, nullptr,
                                  nullptr, nullptr, nullptr);
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
      if (FcPatternGetString(fonts->fonts[i], FC_FAMILY, 0, &family) ==
              FcResultMatch &&
          family != nullptr) {
        names.insert(reinterpret_cast<const char*>(family));
      }
    }
    FcFontSetDestroy(fonts);
  }
  FcObjectSetDestroy(objects);
  FcPatternDestroy(pattern);
  FlValue* list = fl_value_new_list();
  for (const auto& name : names)
    fl_value_append_take(list, fl_value_new_string(name.c_str()));
  return list;
}

// ---- Channel --------------------------------------------------------------

std::string StringArg(FlValue* args, const char* key) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP)
    return "";
  FlValue* value = fl_value_lookup_string(args, key);
  return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_STRING
             ? fl_value_get_string(value)
             : "";
}

bool BoolArg(FlValue* args, const char* key) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP)
    return false;
  FlValue* value = fl_value_lookup_string(args, key);
  return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_BOOL &&
         fl_value_get_bool(value);
}

int64_t IntArg(FlValue* args, const char* key) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) return 0;
  FlValue* value = fl_value_lookup_string(args, key);
  return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_INT
             ? fl_value_get_int(value)
             : 0;
}

double DoubleArg(FlValue* args, const char* key) {
  FlValue* value = key != nullptr && args != nullptr &&
                           fl_value_get_type(args) == FL_VALUE_TYPE_MAP
                       ? fl_value_lookup_string(args, key)
                       : args;
  if (value == nullptr) return 0;
  if (fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT)
    return fl_value_get_float(value);
  if (fl_value_get_type(value) == FL_VALUE_TYPE_INT)
    return static_cast<double>(fl_value_get_int(value));
  return 0;
}

// A window size in pixels; 0 when it is missing, not finite or too large.
int SizeArg(FlValue* args, const char* key) {
  const double value = DoubleArg(args, key);
  return std::isfinite(value) && value >= 1 && value <= 16384
             ? static_cast<int>(value + 0.5)
             : 0;
}

bool BoolValue(FlValue* value) {
  return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_BOOL &&
         fl_value_get_bool(value);
}

// Keeps the window's ratio while it is resized; 0 lets it go.
void KeepAspect(double aspect) {
  if (aspect <= 0) {
    gtk_window_set_geometry_hints(shell.window, nullptr, nullptr,
                                  static_cast<GdkWindowHints>(0));
    gtk_widget_set_size_request(GTK_WIDGET(shell.window), 480, 360);
    return;
  }
  GdkGeometry geometry = {};
  geometry.min_width = 120;
  geometry.min_height = 120;
  geometry.min_aspect = aspect;
  geometry.max_aspect = aspect;
  gtk_widget_set_size_request(GTK_WIDGET(shell.window), -1, -1);
  gtk_window_set_geometry_hints(
      shell.window, nullptr, &geometry,
      static_cast<GdkWindowHints>(GDK_HINT_ASPECT | GDK_HINT_MIN_SIZE));
}

void EnterPip(double aspect, int width, int height) {
  GtkWindow* window = shell.window;
  if (window == nullptr || shell.pip || width <= 0 || height <= 0) return;
  if (!std::isfinite(aspect)) aspect = 0;
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
  GdkMonitor* monitor = surface != nullptr
                            ? gdk_display_get_monitor_at_window(
                                  gdk_window_get_display(surface), surface)
                            : nullptr;
  if (monitor == nullptr) return;
  GdkRectangle area;
  gdk_monitor_get_workarea(monitor, &area);
  int x = area.x + area.width - width - 16,
      y = area.y + area.height - height - 16;
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
  if (shell.window == nullptr || !shell.pip || !(aspect > 0) ||
      !std::isfinite(aspect))
    return;
  int width = 0, height = 0;
  gtk_window_get_size(shell.window, &width, &height);
  KeepAspect(aspect);
  gtk_window_resize(shell.window, width,
                    static_cast<int>(width / aspect + 0.5));
}

// Moves or resizes the window with the pointer, from a press on the picture.
void BeginDrag(bool resize) {
  GtkWindow* window = shell.window;
  if (window == nullptr) return;
  GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(window));
  GdkDevice* pointer =
      gdk_seat_get_pointer(gdk_display_get_default_seat(display));
  int x = 0, y = 0;
  gdk_device_get_position(pointer, nullptr, &x, &y);
  if (resize) {
    gtk_window_begin_resize_drag(window, GDK_WINDOW_EDGE_SOUTH_EAST, 1, x, y,
                                 GDK_CURRENT_TIME);
  } else {
    gtk_window_begin_move_drag(window, 1, x, y, GDK_CURRENT_TIME);
  }
}

// Keeps the screen from blanking or locking while [on]: GTK asks the
// desktop's session manager, the portal or the screen saver, whichever
// answers.
void SetKeepAwake(bool on) {
  GtkApplication* application = shell.window != nullptr
                                    ? gtk_window_get_application(shell.window)
                                    : nullptr;
  if (application == nullptr) return;
  if (on && shell.inhibit == 0) {
    shell.inhibit = gtk_application_inhibit(application, shell.window,
                                            GTK_APPLICATION_INHIBIT_IDLE,
                                            "Playing a video");
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
  if (shell.pip || shell.window == nullptr) return;
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
    gdk_device_get_position(
        gdk_seat_get_pointer(gdk_display_get_default_seat(display)), nullptr,
        &x, &y);
  }
  if (resize) {
    gtk_window_begin_resize_drag(window, edge, 1, x, y, time);
  } else {
    gtk_window_begin_move_drag(window, 1, x, y, time);
  }
}

GdkDevice* Pointer(GdkWindow* window) {
  return gdk_seat_get_pointer(
      gdk_display_get_default_seat(gdk_window_get_display(window)));
}

// Gives the pointer back once it moved, unless Flutter set another one
// meanwhile: Flutter answers the move with the pointer it wants, which may
// be the one it already had and so is not set again.
gboolean WatchHiddenPointer(gpointer) {
  GdkWindow* window = shell.window != nullptr
                          ? gtk_widget_get_window(GTK_WIDGET(shell.window))
                          : nullptr;
  int x = 0;
  int y = 0;
  if (window != nullptr)
    gdk_device_get_position(Pointer(window), nullptr, &x, &y);
  if (window != nullptr && x == shell.hidden_x && y == shell.hidden_y)
    return G_SOURCE_CONTINUE;
  if (window != nullptr && gdk_window_get_cursor(window) == shell.pointer_blank)
    gdk_window_set_cursor(window, shell.pointer_before);
  g_clear_object(&shell.pointer_before);
  shell.pointer_watch = 0;
  return G_SOURCE_REMOVE;
}

// Hides the pointer while it rests in the box |area| (left, top, right,
// bottom in logical pixels of Flutter's view), until it moves.
void HidePointer(FlValue* area) {
  if (area == nullptr || fl_value_get_type(area) != FL_VALUE_TYPE_LIST ||
      fl_value_get_length(area) != 4)
    return;
  if (shell.view == nullptr || shell.window == nullptr ||
      shell.pointer_watch != 0 || !gtk_window_is_active(shell.window))
    return;
  double box[4];
  for (size_t i = 0; i < 4; ++i) {
    FlValue* item = fl_value_get_list_value(area, i);
    const FlValueType type = fl_value_get_type(item);
    box[i] = type == FL_VALUE_TYPE_FLOAT ? fl_value_get_float(item)
             : type == FL_VALUE_TYPE_INT
                 ? static_cast<double>(fl_value_get_int(item))
                 : 0;
  }
  GdkWindow* window = gtk_widget_get_window(GTK_WIDGET(shell.window));
  if (window == nullptr) return;
  int x = 0;
  int y = 0;
  gdk_window_get_device_position(window, Pointer(window), &x, &y, nullptr);
  int view_x = 0;
  int view_y = 0;
  if (!gtk_widget_translate_coordinates(GTK_WIDGET(shell.window),
                                        GTK_WIDGET(shell.view), x, y, &view_x,
                                        &view_y))
    return;
  if (view_x < box[0] || view_y < box[1] || view_x >= box[2] ||
      view_y >= box[3])
    return;
  if (shell.pointer_blank == nullptr)
    shell.pointer_blank = gdk_cursor_new_for_display(
        gdk_window_get_display(window), GDK_BLANK_CURSOR);
  GdkCursor* before = gdk_window_get_cursor(window);
  shell.pointer_before =
      before != nullptr ? GDK_CURSOR(g_object_ref(before)) : nullptr;
  gdk_device_get_position(Pointer(window), nullptr, &shell.hidden_x,
                          &shell.hidden_y);
  gdk_window_set_cursor(window, shell.pointer_blank);
  shell.pointer_watch = g_timeout_add(100, WatchHiddenPointer, nullptr);
}

// ---- Desktop glass ---------------------------------------------------------

#ifdef GDK_WINDOWING_WAYLAND
// Blur behind the window on Wayland, written out by hand so no generated
// protocol code is needed. Two protocols:
//  - ext_background_effect_v1 (wayland-protocols, staging), the standard
//    one: KDE Plasma 6.7+, GNOME 51+, COSMIC, niri, Hyprland 0.56+;
//  - org_kde_kwin_blur, KWin's own, for older Plasma.
// libwayland-client is reached through GTK, which already loaded it, so
// the runner is not linked against a copy older than libmpv's.
const struct wl_interface* kNoTypes[] = {nullptr, nullptr};

const struct wl_interface* kBlurRegionTypes[] = {nullptr};
const struct wl_message kBlurRequests[] = {
    {"commit", "", nullptr},
    {"set_region", "?o", kBlurRegionTypes},
    {"release", "", nullptr},
};
const struct wl_interface kBlurInterface = {"org_kde_kwin_blur", 1, 3,
                                            kBlurRequests,       0, nullptr};
const struct wl_interface* kBlurCreateTypes[] = {&kBlurInterface, nullptr};
const struct wl_interface* kBlurUnsetTypes[] = {nullptr};
const struct wl_message kBlurManagerRequests[] = {
    {"create", "no", kBlurCreateTypes},
    {"unset", "o", kBlurUnsetTypes},
};
const struct wl_interface kBlurManagerInterface = {
    "org_kde_kwin_blur_manager", 1, 2, kBlurManagerRequests, 0, nullptr};

const struct wl_interface* kEffectRegionTypes[] = {nullptr};
const struct wl_message kEffectRequests[] = {
    {"destroy", "", nullptr},
    {"set_blur_region", "?o", kEffectRegionTypes},
};
const struct wl_interface kEffectInterface = {
    "ext_background_effect_surface_v1", 1, 2, kEffectRequests, 0, nullptr};
const struct wl_interface* kEffectGetTypes[] = {&kEffectInterface, nullptr};
const struct wl_message kEffectManagerRequests[] = {
    {"destroy", "", nullptr},
    {"get_background_effect", "no", kEffectGetTypes},
};
const struct wl_message kEffectManagerEvents[] = {
    {"capabilities", "u", kNoTypes},
};
const struct wl_interface kEffectManagerInterface = {
    "ext_background_effect_manager_v1",
    1,
    2,
    kEffectManagerRequests,
    1,
    kEffectManagerEvents};

struct WaylandClient {
  const struct wl_interface* registry_interface;
  const struct wl_interface* compositor_interface;
  const struct wl_interface* region_interface;
  struct wl_event_queue* (*create_queue)(struct wl_display*);
  int (*roundtrip_queue)(struct wl_display*, struct wl_event_queue*);
  void (*destroy_queue)(struct wl_event_queue*);
  int (*flush)(struct wl_display*);
  int (*add_listener)(struct wl_proxy*, void (**)(void), void*);
  void (*destroy)(struct wl_proxy*);
  uint32_t (*version)(struct wl_proxy*);
  void (*set_queue)(struct wl_proxy*, struct wl_event_queue*);
  struct wl_proxy* (*marshal)(struct wl_proxy*, uint32_t,
                              const struct wl_interface*, uint32_t, uint32_t,
                              ...);
};

// The functions of the libwayland-client GTK uses; false when one is missing.
bool LoadWaylandClient(WaylandClient& wl) {
  void* library = dlopen("libwayland-client.so.0", RTLD_NOW | RTLD_NOLOAD);
  if (library == nullptr) return false;
  auto find = [library](const char* name) { return dlsym(library, name); };
  auto surface =
      static_cast<const struct wl_interface*>(find("wl_surface_interface"));
  wl.registry_interface =
      static_cast<const struct wl_interface*>(find("wl_registry_interface"));
  wl.compositor_interface =
      static_cast<const struct wl_interface*>(find("wl_compositor_interface"));
  wl.region_interface =
      static_cast<const struct wl_interface*>(find("wl_region_interface"));
  wl.create_queue = reinterpret_cast<decltype(wl.create_queue)>(
      find("wl_display_create_queue"));
  wl.roundtrip_queue = reinterpret_cast<decltype(wl.roundtrip_queue)>(
      find("wl_display_roundtrip_queue"));
  wl.destroy_queue = reinterpret_cast<decltype(wl.destroy_queue)>(
      find("wl_event_queue_destroy"));
  wl.flush = reinterpret_cast<decltype(wl.flush)>(find("wl_display_flush"));
  wl.add_listener = reinterpret_cast<decltype(wl.add_listener)>(
      find("wl_proxy_add_listener"));
  wl.destroy = reinterpret_cast<decltype(wl.destroy)>(find("wl_proxy_destroy"));
  wl.version =
      reinterpret_cast<decltype(wl.version)>(find("wl_proxy_get_version"));
  wl.set_queue =
      reinterpret_cast<decltype(wl.set_queue)>(find("wl_proxy_set_queue"));
  wl.marshal =
      reinterpret_cast<decltype(wl.marshal)>(find("wl_proxy_marshal_flags"));
  if (surface == nullptr || wl.registry_interface == nullptr ||
      wl.compositor_interface == nullptr || wl.region_interface == nullptr ||
      wl.create_queue == nullptr || wl.roundtrip_queue == nullptr ||
      wl.destroy_queue == nullptr || wl.flush == nullptr ||
      wl.add_listener == nullptr || wl.destroy == nullptr ||
      wl.version == nullptr || wl.set_queue == nullptr ||
      wl.marshal == nullptr) {
    return false;
  }
  kBlurRegionTypes[0] = wl.region_interface;
  kBlurCreateTypes[1] = surface;
  kBlurUnsetTypes[0] = surface;
  kEffectRegionTypes[0] = wl.region_interface;
  kEffectGetTypes[1] = surface;
  return true;
}

struct WaylandBlur {
  bool looked = false;
  WaylandClient wl{};
  struct wl_proxy* compositor = nullptr;
  struct wl_proxy* effects = nullptr;
  struct wl_proxy* effect = nullptr;
  // The surface |effect| belongs to. GTK destroys a window's wl_surface
  // when it is hidden and makes a new one when it is shown again; using the
  // old effect then is a protocol error that ends the connection.
  struct wl_surface* effect_surface = nullptr;
  struct wl_proxy* kde = nullptr;
  struct wl_proxy* kde_blur = nullptr;
};
WaylandBlur wayland_blur;

// wl_registry.bind (request 0), as wayland-client-protocol.h writes it.
struct wl_proxy* Bind(struct wl_proxy* registry, uint32_t name,
                      const struct wl_interface* interface, uint32_t version) {
  return wayland_blur.wl.marshal(registry, 0, interface, version, 0, name,
                                 interface->name, version, nullptr);
}

void OnGlobal(void*, struct wl_proxy* registry, uint32_t name,
              const char* interface, uint32_t) {
  if (g_strcmp0(interface, kEffectManagerInterface.name) == 0 &&
      wayland_blur.effects == nullptr) {
    wayland_blur.effects = Bind(registry, name, &kEffectManagerInterface, 1);
  } else if (g_strcmp0(interface, kBlurManagerInterface.name) == 0 &&
             wayland_blur.kde == nullptr) {
    wayland_blur.kde = Bind(registry, name, &kBlurManagerInterface, 1);
  } else if (g_strcmp0(interface, "wl_compositor") == 0 &&
             wayland_blur.compositor == nullptr) {
    wayland_blur.compositor =
        Bind(registry, name, wayland_blur.wl.compositor_interface, 1);
  }
}
void OnGlobalRemove(void*, struct wl_proxy*, uint32_t) {}
struct {
  void (*global)(void*, struct wl_proxy*, uint32_t, const char*, uint32_t);
  void (*global_remove)(void*, struct wl_proxy*, uint32_t);
} kRegistryListener = {OnGlobal, OnGlobalRemove};

// Asks the compositor to blur behind the whole window; false where it
// offers neither protocol (Sway, older GNOME and others).
bool SetWaylandBlur(GdkWindow* surface, bool on) {
  struct wl_display* display =
      gdk_wayland_display_get_wl_display(gdk_window_get_display(surface));
  struct wl_surface* wl_surface = gdk_wayland_window_get_wl_surface(surface);
  if (display == nullptr || wl_surface == nullptr) return false;
  WaylandClient& wl = wayland_blur.wl;
  if (!wayland_blur.looked) {
    wayland_blur.looked = true;
    if (!LoadWaylandClient(wl)) return false;
    // A queue of our own, so GTK's events are left to GTK.
    struct wl_event_queue* queue = wl.create_queue(display);
    // wl_display.get_registry (request 1).
    auto* proxy_display = reinterpret_cast<struct wl_proxy*>(display);
    struct wl_proxy* registry =
        wl.marshal(proxy_display, 1, wl.registry_interface,
                   wl.version(proxy_display), 0, nullptr);
    wl.set_queue(registry, queue);
    wl.add_listener(registry,
                    reinterpret_cast<void (**)(void)>(&kRegistryListener),
                    nullptr);
    wl.roundtrip_queue(display, queue);
    for (struct wl_proxy* bound :
         {wayland_blur.effects, wayland_blur.kde, wayland_blur.compositor}) {
      if (bound != nullptr) wl.set_queue(bound, nullptr);
    }
    wl.destroy(registry);
    wl.destroy_queue(queue);
  }
  if (wayland_blur.effects != nullptr && wayland_blur.compositor != nullptr) {
    const uint32_t version = wl.version(wayland_blur.effects);
    if (wayland_blur.effect != nullptr &&
        wayland_blur.effect_surface != wl_surface) {
      wl.marshal(wayland_blur.effect, 0 /* destroy */, nullptr,
                 wl.version(wayland_blur.effect), WL_MARSHAL_FLAG_DESTROY);
      wayland_blur.effect = nullptr;
    }
    if (wayland_blur.effect == nullptr) {
      wayland_blur.effect =
          wl.marshal(wayland_blur.effects, 1 /* get_background_effect */,
                     &kEffectInterface, version, 0, nullptr, wl_surface);
      wayland_blur.effect_surface = wl_surface;
    }
    struct wl_proxy* region = nullptr;
    if (on) {
      // wl_compositor.create_region (1), then wl_region.add (1) over all of it.
      region = wl.marshal(wayland_blur.compositor, 1, wl.region_interface,
                          wl.version(wayland_blur.compositor), 0, nullptr);
      wl.marshal(region, 1, nullptr, wl.version(region), 0, 0, 0, INT32_MAX,
                 INT32_MAX);
    }
    // No region removes the blur.
    wl.marshal(wayland_blur.effect, 1 /* set_blur_region */, nullptr, version,
               0, region);
    if (region != nullptr)
      wl.marshal(region, 0 /* destroy */, nullptr, wl.version(region),
                 WL_MARSHAL_FLAG_DESTROY);
  } else if (wayland_blur.kde != nullptr) {
    const uint32_t version = wl.version(wayland_blur.kde);
    if (wayland_blur.kde_blur != nullptr) {
      wl.marshal(wayland_blur.kde_blur, 2 /* release */, nullptr, version,
                 WL_MARSHAL_FLAG_DESTROY);
      wayland_blur.kde_blur = nullptr;
    }
    if (on) {
      wayland_blur.kde_blur =
          wl.marshal(wayland_blur.kde, 0 /* create */, &kBlurInterface, version,
                     0, nullptr, wl_surface);
      // No region: the whole surface.
      wl.marshal(wayland_blur.kde_blur, 0 /* commit */, nullptr, version, 0);
    } else {
      wl.marshal(wayland_blur.kde, 1 /* unset */, nullptr, version, 0,
                 wl_surface);
    }
  } else {
    return false;
  }
  // Both take effect with the surface's next commit: a new frame.
  gdk_window_invalidate_rect(surface, nullptr, TRUE);
  wl.flush(display);
  return true;
}
#endif

// The desktop shows wherever Flutter leaves the window clear: only with a
// compositor, and with the alpha visual chosen at start
// (linux_shell_use_alpha_visual). KWin blurs it, on X11 and Wayland.
FlValue* SetDesktopGlass(bool on, bool blur) {
  shell.glass_set = true;
  shell.glass_on = on;
  shell.glass_blur = blur;
  GtkWidget* window = GTK_WIDGET(shell.window);
  GdkScreen* screen = gtk_widget_get_screen(window);
  const bool possible =
      shell.view != nullptr && gdk_screen_is_composited(screen) &&
      gtk_widget_get_visual(window) == gdk_screen_get_rgba_visual(screen);
  const bool clear = on && possible;
  GdkRGBA background{0, 0, 0, clear ? 0.0 : 1.0};
  if (shell.view != nullptr)
    fl_view_set_background_color(shell.view, &background);
  bool blurred = false;
  GdkWindow* surface = gtk_widget_get_window(window);
#ifdef GDK_WINDOWING_X11
  if (surface != nullptr && GDK_IS_X11_WINDOW(surface)) {
    GdkAtom atom =
        gdk_atom_intern_static_string("_KDE_NET_WM_BLUR_BEHIND_REGION");
    if (clear && blur) {
      gdk_property_change(surface, atom,
                          gdk_atom_intern_static_string("CARDINAL"), 32,
                          GDK_PROP_MODE_REPLACE, nullptr, 0);
      // KWin lists the atom among what it supports while its blur is on.
      blurred = gdk_x11_screen_supports_net_wm_hint(screen, atom);
    } else {
      gdk_property_delete(surface, atom);
    }
  }
#endif
#ifdef GDK_WINDOWING_WAYLAND
  if (surface != nullptr && GDK_IS_WAYLAND_WINDOW(surface)) {
    blurred = SetWaylandBlur(surface, clear && blur) && clear && blur;
  }
#endif
  gtk_widget_queue_draw(window);
  FlValue* answer = fl_value_new_map();
  fl_value_set_string_take(answer, "shown", fl_value_new_bool(clear));
  fl_value_set_string_take(answer, "blurred", fl_value_new_bool(blurred));
  return answer;
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
    fl_value_set_string_take(
        state, "maximized", fl_value_new_bool(gtk_window_is_maximized(window)));
    fl_value_set_string_take(state, "active",
                             fl_value_new_bool(gtk_window_is_active(window)));
    fl_method_call_respond_success(call, state, nullptr);
    return;
  }
  if (method == "setDesktopGlass") {
    g_autoptr(FlValue) answer =
        SetDesktopGlass(BoolArg(args, "on"), BoolArg(args, "blur"));
    fl_method_call_respond_success(call, answer, nullptr);
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
    const bool named =
        args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_STRING;
    BeginFrameDrag(true, EdgeOf(named ? fl_value_get_string(args) : ""));
  } else if (method == "hidePointer") {
    HidePointer(args);
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
      if (!shell.close_to_tray && !shell.minimize_to_tray &&
          shell.window != nullptr && !WindowVisible())
        ShowFromTray();
      if (!shell.close_to_tray && !shell.minimize_to_tray)
        shell.indicator_set_status(shell.indicator, kStatusPassive);
    }
    // With either tray option on, the icon stays while the window is open too.
    if (shell.close_to_tray || shell.minimize_to_tray) ShowTrayIcon();
  } else if (method == "setAppIcon") {
    const std::string chosen =
        args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_STRING
            ? fl_value_get_string(args)
            : "";
    const std::string name =
        chosen == "tabor" || chosen == "gold" ? "lumtub-" + chosen : "lumtub";
    if (name != shell.icon_name) {
      shell.icon_name = name;
      if (shell.window != nullptr)
        gtk_window_set_icon_from_file(shell.window, IconPath().c_str(),
                                      nullptr);
      if (shell.indicator != nullptr && shell.indicator_set_icon != nullptr)
        shell.indicator_set_icon(shell.indicator, name.c_str(), "Lumtub");
    }
  } else if (method == "setMetadata") {
    shell.title = StringArg(args, "title");
    shell.artist = StringArg(args, "artist");
    shell.art = StringArg(args, "thumbnail");
    shell.track++;
    shell.position_ms = 0;
    PlayerChanged({"Metadata"});
  } else if (method == "setStatus") {
    const std::string status =
        args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_STRING
            ? fl_value_get_string(args)
            : "";
    shell.status = status == "playing"  ? "Playing"
                   : status == "paused" ? "Paused"
                                        : "Stopped";
    if (shell.status == "Stopped") shell.title.clear();
    PlayerChanged(
        {"PlaybackStatus", "Metadata", "CanPlay", "CanPause", "CanSeek"});
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
      g_dbus_connection_emit_signal(
          shell.bus, nullptr, kMprisPath, "org.mpris.MediaPlayer2.Player",
          "Seeked", g_variant_new("(x)", position * 1000), nullptr);
    }
  } else if (method == "setKeepAwake") {
    SetKeepAwake(BoolValue(args));
  } else if (method == "setTopmost") {
    shell.above = BoolValue(args);
    if (shell.window != nullptr)
      gtk_window_set_keep_above(shell.window, shell.above);
  } else if (method == "enterPip") {
    EnterPip(DoubleArg(args, "aspect"), SizeArg(args, "width"),
             SizeArg(args, "height"));
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
  g_signal_connect(window, "window-state-event", G_CALLBACK(OnWindowState),
                   nullptr);
  g_signal_connect(window, "configure-event", G_CALLBACK(OnConfigure), nullptr);
  g_signal_connect(window, "map", G_CALLBACK(+[](GtkWidget*, gpointer) {
                     HookHeaderBar();
                     if (shell.glass_set) {
                       g_idle_add(
                           +[](gpointer) -> gboolean {
                             if (shell.window != nullptr)
                               fl_value_unref(SetDesktopGlass(
                                   shell.glass_on, shell.glass_blur));
                             return G_SOURCE_REMOVE;
                           },
                           nullptr);
                     }
                   }),
                   nullptr);
  // Nothing may reach the window, or the view inside it, once it is gone:
  // MPRIS, the tray and timers can still run while the app shuts down.
  g_signal_connect(window, "destroy", G_CALLBACK(+[](GtkWidget*, gpointer) {
                     if (shell.save_timer != 0) {
                       g_source_remove(shell.save_timer);
                       shell.save_timer = 0;
                     }
                     if (shell.pointer_watch != 0) {
                       g_source_remove(shell.pointer_watch);
                       shell.pointer_watch = 0;
                     }
                     g_clear_object(&shell.pointer_before);
                     shell.window = nullptr;
                     shell.view = nullptr;
                   }),
                   nullptr);
  WatchTray();
  gtk_window_set_icon_from_file(window, IconPath().c_str(), nullptr);
  StartMpris();
}

void linux_shell_restore_window(GtkWindow* window) {
  gtk_window_set_default_size(window, 1280, 720);
  const std::string path = WindowStateFile();
  if (path.empty()) return;
  FILE* file = fopen(path.c_str(), "r");
  if (file == nullptr) return;
  int width = 0, height = 0, x = 0, y = 0, maximized = 0;
  const int read =
      fscanf(file, "%d %d %d %d %d", &width, &height, &x, &y, &maximized);
  fclose(file);
  if (read != 5 || width < kMinWidth || height < kMinHeight || width > 16384 ||
      height > 16384)
    return;
  gtk_window_set_default_size(window, width, height);
  shell.normal_width = width;
  shell.normal_height = height;
  shell.normal_x = x;
  shell.normal_y = y;
  shell.has_normal = true;
  // Wayland compositors place windows themselves, so only the size is kept.
  if (!OnWayland()) {
    // Skip a place on a screen that is no longer there.
    GdkDisplay* display = gdk_display_get_default();
    bool visible = false;
    for (int i = 0;
         display != nullptr && i < gdk_display_get_n_monitors(display); i++) {
      GdkRectangle area, window_area = {x, y, width, height}, overlap;
      gdk_monitor_get_workarea(gdk_display_get_monitor(display, i), &area);
      if (gdk_rectangle_intersect(&area, &window_area, &overlap) &&
          overlap.width >= 120 && overlap.height >= 60)
        visible = true;
    }
    if (visible) gtk_window_move(window, x, y);
  }
  if (maximized) gtk_window_maximize(window);
}

void linux_shell_connect(FlView* view) {
  shell.view = view;
  FlEngine* engine = fl_view_get_engine(view);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  shell.channel = fl_method_channel_new(fl_engine_get_binary_messenger(engine),
                                        kChannel, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(shell.channel, HandleCall, nullptr,
                                            nullptr);
  shell.frame_channel =
      fl_method_channel_new(fl_engine_get_binary_messenger(engine),
                            kFrameChannel, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(shell.frame_channel,
                                            HandleFrameCall, nullptr, nullptr);
  g_signal_connect(view, "button-press-event", G_CALLBACK(OnViewButtonPress),
                   nullptr);
}

void linux_shell_use_alpha_visual(GtkWindow* window) {
  // A window with an alpha channel, so the desktop can show through when
  // asked; Flutter paints it opaque until then. It has to be chosen
  // before the window is realized.
  GdkScreen* screen = gtk_window_get_screen(window);
  GdkVisual* rgba = gdk_screen_get_rgba_visual(screen);
  if (rgba != nullptr && gdk_screen_is_composited(screen)) {
    gtk_widget_set_visual(GTK_WIDGET(window), rgba);
    gtk_widget_set_app_paintable(GTK_WIDGET(window), TRUE);
  }
}

void linux_shell_present() {
  if (shell.window != nullptr) ShowFromTray();
}
