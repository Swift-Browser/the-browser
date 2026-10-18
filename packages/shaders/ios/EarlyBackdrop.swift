import AppKit

@objc(MedusaEarlyBackdrop)
public final class EarlyBackdrop: NSObject {
  @objc public static func make(_ props: NSDictionary) -> NSView? {
    var tint = WindowTreatmentView.Tint()
    if let hex = props["tintColor"] as? String, let c = SIMD4<Float>(hex: hex) {
      tint.color = NSColor(displayP3Red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
    }
    if let alpha = (props["tintAlpha"] as? NSNumber)?.doubleValue { tint.alpha = alpha }
    if let lightness = (props["tintLightness"] as? NSNumber)?.doubleValue { tint.lightness = lightness }
    if (props["vibrancy"] as? NSNumber)?.boolValue ?? true {
      let view = WindowTreatmentView(frame: .zero)
      view.tint = tint
      return view
    }
    let view = WindowBackdropView(appContext: nil)
    if let colors = props["colors"] as? [String], !colors.isEmpty { view.setColors(colors) }
    view.setTint { $0 = tint }
    if let angle = (props["angle"] as? NSNumber)?.doubleValue { view.setAngle(angle) }
    if let grain = (props["grainOpacity"] as? NSNumber)?.floatValue { view.set(\.grainOpacity, grain) }
    if let scale = (props["grainScale"] as? NSNumber)?.floatValue { view.set(\.grainScale, scale) }
    return view
  }
}
