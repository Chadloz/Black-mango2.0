import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  // Kept alive while the eyedropper is open (NSColorSampler; the app needs macOS 12 anyway).
  private var sampler: AnyObject?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Skin editor eyedropper: Apple's own screen sampler, which picks a color from anything on
    // screen without asking for screen-recording permission. Returns 0xRRGGBB, or nil if cancelled.
    let eyedropper = FlutterMethodChannel(
      name: "blackmango/eyedropper",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    eyedropper.setMethodCallHandler { [weak self] call, result in
      guard call.method == "pick" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let sampler = NSColorSampler()
      self?.sampler = sampler
      sampler.show { color in
        self?.sampler = nil
        guard let c = color?.usingColorSpace(.sRGB) else {
          result(nil)
          return
        }
        func byte(_ v: CGFloat) -> Int { return Int((min(max(v, 0), 1) * 255).rounded()) }
        result((byte(c.redComponent) << 16) | (byte(c.greenComponent) << 8) | byte(c.blueComponent))
      }
    }

    super.awakeFromNib()
  }
}
