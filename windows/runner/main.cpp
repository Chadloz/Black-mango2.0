#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>

#include "flutter_window.h"
#include "utils.h"

namespace {

// Settings > Windows > "Use the older drawing engine" leaves a small marker file here:
//   %APPDATA%\Black Mango\classic-renderer.txt
// The drawing engine has to be chosen before the window exists, which is before the app's own
// settings can be read, so the marker is checked right here. (lib/core/renderer_switch.dart)
bool ClassicRendererChosen() {
  wchar_t base[MAX_PATH];
  const DWORD length = ::GetEnvironmentVariableW(L"APPDATA", base, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) {
    return false;
  }
  const std::wstring marker =
      std::wstring(base, length) + L"\\Black Mango\\classic-renderer.txt";
  const DWORD attributes = ::GetFileAttributesW(marker.c_str());
  return attributes != INVALID_FILE_ATTRIBUTES &&
         (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
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

  flutter::DartProject project(L"data");
  if (ClassicRendererChosen()) {
    // Flutter's newer engine (Impeller) off, the older one on. A troubleshooting switch.
    project.set_impeller_switch(flutter::ImpellerSwitch::Disabled);
  }

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Black Mango", origin, size)) {
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
