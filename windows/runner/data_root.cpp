#include "data_root.h"

#include <windows.h>

namespace {

std::wstring ExecutableDirectory() {
  std::wstring path(MAX_PATH, L'\0');
  for (;;) {
    const DWORD length = ::GetModuleFileNameW(nullptr, path.data(), static_cast<DWORD>(path.size()));
    if (length == 0) return L"";
    if (length < path.size()) {
      path.resize(length);
      break;
    }
    path.resize(path.size() * 2);
  }
  const size_t slash = path.find_last_of(L"\\/");
  return slash == std::wstring::npos ? L"" : path.substr(0, slash);
}

bool Exists(const std::wstring& path) {
  return ::GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES;
}

// Whether files can be created in [directory], creating it first.
bool Writable(const std::wstring& directory) {
  ::CreateDirectoryW(directory.c_str(), nullptr);
  const std::wstring probe = directory + L"\\.write-test";
  const HANDLE file = ::CreateFileW(probe.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
                                    FILE_ATTRIBUTE_TEMPORARY | FILE_FLAG_DELETE_ON_CLOSE, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  ::CloseHandle(file);
  return true;
}

std::wstring LocalAppDataRoot() {
  const DWORD required = ::GetEnvironmentVariableW(L"LOCALAPPDATA", nullptr, 0);
  if (required == 0) return L"";
  std::wstring value(required, L'\0');
  const DWORD length = ::GetEnvironmentVariableW(L"LOCALAPPDATA", value.data(), required);
  if (length == 0 || length >= required) return L"";
  value.resize(length);
  return value + L"\\YTPlus";
}

std::wstring FindDataRoot() {
  const std::wstring executable = ExecutableDirectory();
  if (!executable.empty() && Exists(executable + L"\\portable.txt")) {
    const std::wstring portable = executable + L"\\userdata";
    if (Writable(portable)) return portable;
  }
  const std::wstring local = LocalAppDataRoot();
  if (!local.empty()) ::CreateDirectoryW(local.c_str(), nullptr);
  return local;
}

}  // namespace

const std::wstring& DataRoot() {
  static const std::wstring root = [] {
    std::wstring found = FindDataRoot();
    if (!found.empty()) ::SetEnvironmentVariableW(L"YTPLUS_HOME", found.c_str());
    return found;
  }();
  return root;
}
