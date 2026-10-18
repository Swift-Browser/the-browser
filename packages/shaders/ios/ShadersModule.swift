import ExpoModulesCore

public class AreaLightModule: Module {
  public func definition() -> ModuleDefinition {
    Name("MedusaAreaLight")

    AsyncFunction("debugSetWindowActive") { (value: Bool?) in WindowActivity.override = value }.runOnQueue(.main)
    AsyncFunction("debugSetReduceMotion") { (value: Bool?) in WindowActivity.reduceMotionOverride = value }.runOnQueue(.main)
    AsyncFunction("debugSnapshot") { (dir: String) -> [[String: Any]] in
      try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
      return MetalSurface.instances.enumerated().compactMap { index, view in
        guard let window = view.window, let content = window.contentView else { return nil }
        let name = String(describing: type(of: view))
        let path = (dir as NSString).appendingPathComponent("\(index)-\(name).png")
        let r = view.convert(view.bounds, to: nil)
        let top = content.bounds.height - r.maxY
        return [
          "file": path, "class": name, "ok": view.writeSnapshot(to: path), "window": window.windowNumber,
          "frame": [r.minX, top, r.width, r.height], "key": window.isKeyWindow, "main": window.isMainWindow,
          "hidden": view.isHiddenOrHasHiddenAncestor, "alpha": view.alphaValue,
        ]
      }
    }.runOnQueue(.main)
  }
}

public class WindowBackdropModule: Module {
  public func definition() -> ModuleDefinition {
    Name("MedusaWindowBackdrop")

    View(WindowBackdropView.self) {
      Prop("colors") { (view: WindowBackdropView, colors: [String]) in view.setColors(colors) }
      Prop("vibrancy") { (view: WindowBackdropView, on: Bool) in view.setVibrancy(on) }
      Prop("tintColor") { (view: WindowBackdropView, hex: String) in
        if let c = SIMD4<Float>(hex: hex) {
          view.setTint { $0.color = NSColor(displayP3Red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1) }
        }
      }
      Prop("tintAlpha") { (view: WindowBackdropView, v: Double) in view.setTint { $0.alpha = v } }
      Prop("tintLightness") { (view: WindowBackdropView, v: Double) in view.setTint { $0.lightness = v } }
      Prop("angle") { (view: WindowBackdropView, deg: Double) in view.setAngle(deg) }
      Prop("grainOpacity") { (view: WindowBackdropView, v: Double) in view.set(\.grainOpacity, Float(v)) }
      Prop("grainScale") { (view: WindowBackdropView, v: Double) in view.set(\.grainScale, Float(v)) }
    }
  }
}

public class PowerUpModule: Module {
  public func definition() -> ModuleDefinition {
    Name("MedusaPowerUp")

    View(PowerUpView.self) {
      Prop("palette") { (view: PowerUpView, v: [String]) in view.setPalette(v) }
      Prop("speed") { (view: PowerUpView, v: Double) in view.speed = Float(v) }
      Prop("origin") { (view: PowerUpView, v: Double) in view.origin = Float(v) }
      Prop("cornerRadius") { (view: PowerUpView, v: Double) in view.cornerRadius = Float(v) }
      Prop("haloFrame") { (view: PowerUpView, v: [Double]) in
        view.setHaloFrame(v.count == 4 && v[2] > 0 && v[3] > 0 ? CGRect(x: v[0], y: v[1], width: v[2], height: v[3]) : nil)
      }
    }
  }
}
