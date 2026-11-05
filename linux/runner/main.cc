#include <stdlib.h>
#include <unistd.h>

#include <string>

#include "my_application.h"

// X11 compatibility mode (Settings): on a Wayland desktop the window goes
// through XWayland, where it can be kept on top and placed. The marker is
// a file in Lumtub's data folder, read before GTK opens the display.
static void UseX11IfAsked() {
  if (getenv("GDK_BACKEND") != nullptr) return;
  const char* lumtub = getenv("LUMTUB_HOME");
  const char* data = getenv("XDG_DATA_HOME");
  const char* home = getenv("HOME");
  std::string folder;
  if (lumtub != nullptr && *lumtub != '\0') {
    folder = lumtub;
  } else if (data != nullptr && data[0] == '/') {
    folder = std::string(data) + "/lumtub";
  } else if (home != nullptr && home[0] == '/') {
    folder = std::string(home) + "/.local/share/lumtub";
  } else {
    return;
  }
  if (access((folder + "/x11-mode").c_str(), F_OK) != 0) return;
  setenv("GDK_BACKEND", "x11", 1);
  setenv("LUMTUB_X11", "1", 1);
}

int main(int argc, char** argv) {
  UseX11IfAsked();
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
