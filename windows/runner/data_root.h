#ifndef RUNNER_DATA_ROOT_H_
#define RUNNER_DATA_ROOT_H_

#include <cwctype>
#include <string>

// The folder Lumtub keeps its settings, data, cache, components and logs in,
// without a trailing backslash; empty when there is none.
//
// The portable package ships portable.txt next to the executable: then it is
// the userdata folder beside it, so everything stays where the ZIP was
// unpacked. Otherwise, or when that folder cannot be written (an unpacked
// copy under Program Files), it is %LOCALAPPDATA%\Lumtub. The first call
// also sets LUMTUB_HOME, which lib/app_directories.dart reads.
const std::wstring& DataRoot();

// One Lumtub runs per data folder. A second start posts this registered
// message to every top-level window with DataRootTag() as its WPARAM, and
// the running one whose tag matches shows its window.
constexpr const wchar_t kShowWindowMessage[] = L"Lumtub.ShowWindow";

// The same number for the same data folder, in every process.
inline unsigned long long DataRootTag() {
  unsigned long long hash = 1469598103934665603ULL;
  for (const wchar_t c : DataRoot()) {
    hash ^= static_cast<unsigned long long>(std::towlower(c));
    hash *= 1099511628211ULL;
  }
  return hash;
}

#endif  // RUNNER_DATA_ROOT_H_
