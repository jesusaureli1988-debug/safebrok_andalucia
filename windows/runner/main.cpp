#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <string>

#include "flutter_window.h"
#include "utils.h"

namespace {
// Repara solo el acceso directo privado existente de SafeBrok. No borra
// instaladores descargados, documentos, datos ni accesos de otras aplicaciones.
// El instalador crea el acceso público; un enlace privado antiguo puede ocultarlo.
void RepairLegacyDesktopShortcut() {
  constexpr DWORD kPathCapacity = 32768;
  wchar_t executable[kPathCapacity] = {};
  const DWORD length = GetModuleFileNameW(nullptr, executable, kPathCapacity);
  if (length == 0 || length >= kPathCapacity) return;
  const std::wstring app_path(executable, length);
  const auto separator = app_path.find_last_of(L"\\/");
  if (separator == std::wstring::npos) return;
  const std::wstring app_dir = app_path.substr(0, separator);
  if (GetFileAttributesW((app_dir + L"\\unins000.exe").c_str()) ==
      INVALID_FILE_ATTRIBUTES) return;  // Nunca altera el escritorio al desarrollar.

  PWSTR desktop = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_Desktop, 0, nullptr, &desktop))) return;
  const std::wstring shortcut_path = std::wstring(desktop) + L"\\SafeBrok.lnk";
  CoTaskMemFree(desktop);
  if (GetFileAttributesW(shortcut_path.c_str()) == INVALID_FILE_ATTRIBUTES) return;

  IShellLinkW* link = nullptr;
  if (FAILED(CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                             IID_IShellLinkW, reinterpret_cast<void**>(&link)))) return;
  IPersistFile* file = nullptr;
  if (SUCCEEDED(link->QueryInterface(IID_IPersistFile,
                                    reinterpret_cast<void**>(&file)))) {
    if (SUCCEEDED(file->Load(shortcut_path.c_str(), STGM_READ))) {
      wchar_t old_target[kPathCapacity] = {};
      if (SUCCEEDED(link->GetPath(old_target, static_cast<int>(kPathCapacity),
                                  nullptr, SLGP_RAWPATH)) &&
          _wcsicmp(old_target, executable) != 0) {
        if (SUCCEEDED(link->SetPath(executable)) &&
            SUCCEEDED(link->SetWorkingDirectory(app_dir.c_str())) &&
            SUCCEEDED(link->SetArguments(L"")) &&
            SUCCEEDED(link->SetIconLocation(executable, 0))) {
          file->Save(shortcut_path.c_str(), TRUE);
        }
      }
    }
    file->Release();
  }
  link->Release();
}
}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  RepairLegacyDesktopShortcut();

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"SafeBrok", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
