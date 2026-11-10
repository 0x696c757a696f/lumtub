#ifndef RUNNER_LINUX_SHELL_H_
#define RUNNER_LINUX_SHELL_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// The Linux side of lib/windows_shell.dart, on the same method channel:
// media keys and the desktop's media controls over MPRIS, the tray icon
// for "close to tray" (a StatusNotifier icon through libayatana-appindicator
// when the system has it), and the installed font families.
//
// Call before the Flutter view is added to [window], so that closing to
// the tray comes before Flutter's own handling of the close button.
void linux_shell_attach(GtkWindow* window);

// Sets the window's default size, and puts it where it was left last time
// (size only on Wayland, which places windows itself).
void linux_shell_restore_window(GtkWindow* window);

// Hooks the method channel up to the view's engine.
void linux_shell_connect(FlView* view);

// Shows the window again, for example when Lumtub is started a second time.
void linux_shell_present();

#endif  // RUNNER_LINUX_SHELL_H_
