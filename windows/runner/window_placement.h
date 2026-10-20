#ifndef RUNNER_WINDOW_PLACEMENT_H_
#define RUNNER_WINDOW_PLACEMENT_H_

#include <windows.h>

// Moves |window| (created hidden) to where it was when the app last closed,
// when that place is still on a connected monitor. Returns whether it was
// maximized then, so it can be shown maximized.
bool RestoreWindowPlacement(HWND window);

// Remembers |window|'s size, position and maximized state for the next
// launch. Not saved while it is fullscreen.
void SaveWindowPlacement(HWND window);

#endif  // RUNNER_WINDOW_PLACEMENT_H_
