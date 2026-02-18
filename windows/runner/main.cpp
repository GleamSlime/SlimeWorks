#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Try to explicitly enable Per-Monitor V2 DPI awareness at process startup.
  // The application manifest already requests PerMonitorV2, but some
  // launch paths (debugger / older hosts) may ignore it. Calling the API
  // here ensures the process is DPI-aware before any windows are created.
  HMODULE user32 = ::GetModuleHandleA("user32.dll");
  if (user32) {
    typedef BOOL(WINAPI* SetProcessDpiAwarenessContextProc)(HANDLE);
    auto set_dpi_context = reinterpret_cast<SetProcessDpiAwarenessContextProc>(
        ::GetProcAddress(user32, "SetProcessDpiAwarenessContext"));
    if (set_dpi_context) {
      // DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 is defined as (DPI_AWARENESS_CONTEXT)-4
      set_dpi_context(reinterpret_cast<HANDLE>(-4));
    }
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"SlimeWorks", origin, size)) {
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
