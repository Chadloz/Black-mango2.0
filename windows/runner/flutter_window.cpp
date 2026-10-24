#include "flutter_window.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <cstdint>
#include <memory>
#include <optional>
#include <utility>
#include <vector>

#include "flutter/generated_plugin_registrant.h"

namespace {

// Skin editor eyedropper: a copy of the screen Black Mango is on, as top-down BGRA pixels.
// Dart shows it full screen with a magnifier, and reads the color where you click.
void CaptureScreen(HWND window,
                   std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  HMONITOR monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info;
  info.cbSize = sizeof(info);
  if (!GetMonitorInfo(monitor, &info)) {
    result->Error("capture", "Could not find the screen.");
    return;
  }
  const RECT area = info.rcMonitor;
  const int width = area.right - area.left;
  const int height = area.bottom - area.top;

  HDC screen = GetDC(nullptr);
  HDC memory = CreateCompatibleDC(screen);
  BITMAPINFO bmi = {};
  bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bmi.bmiHeader.biWidth = width;
  bmi.bmiHeader.biHeight = -height;  // negative: rows run top to bottom
  bmi.bmiHeader.biPlanes = 1;
  bmi.bmiHeader.biBitCount = 32;
  bmi.bmiHeader.biCompression = BI_RGB;
  void* bits = nullptr;
  HBITMAP bitmap = CreateDIBSection(screen, &bmi, DIB_RGB_COLORS, &bits, nullptr, 0);
  bool ok = bitmap != nullptr && bits != nullptr;
  std::vector<uint8_t> pixels;
  if (ok) {
    HGDIOBJ old = SelectObject(memory, bitmap);
    ok = BitBlt(memory, 0, 0, width, height, screen, area.left, area.top, SRCCOPY | CAPTUREBLT) != 0;
    if (ok) {
      const uint8_t* p = static_cast<const uint8_t*>(bits);
      pixels.assign(p, p + static_cast<size_t>(width) * height * 4);
      for (size_t i = 3; i < pixels.size(); i += 4) pixels[i] = 255;  // the copy has no alpha
    }
    SelectObject(memory, old);
    DeleteObject(bitmap);
  }
  DeleteDC(memory);
  ReleaseDC(nullptr, screen);
  if (!ok) {
    result->Error("capture", "Could not copy the screen.");
    return;
  }
  flutter::EncodableMap map;
  map[flutter::EncodableValue("width")] = flutter::EncodableValue(width);
  map[flutter::EncodableValue("height")] = flutter::EncodableValue(height);
  map[flutter::EncodableValue("bytes")] = flutter::EncodableValue(pixels);
  result->Success(flutter::EncodableValue(map));
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter::MethodChannel<flutter::EncodableValue> eyedropper(
      flutter_controller_->engine()->messenger(), "blackmango/eyedropper",
      &flutter::StandardMethodCodec::GetInstance());
  eyedropper.SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "capture") {
          CaptureScreen(GetHandle(), std::move(result));
        } else {
          result->NotImplemented();
        }
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
