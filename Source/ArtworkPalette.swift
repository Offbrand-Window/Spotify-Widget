import AppKit

enum ArtworkPalette {
 static func textTint(from image: NSImage) -> ArtworkTint {
  guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 128, bitsPerPixel: 32), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return .neutral }
  NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
  image.draw(in: NSRect(x: 0, y: 0, width: 32, height: 32)); NSGraphicsContext.restoreGraphicsState()
  var buckets = Array(repeating: (weight: 0.0, r: 0.0, g: 0.0, b: 0.0), count: 16)
  for y in 0..<32 { for x in 0..<32 {
   guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
   let saturation = Double(color.saturationComponent), brightness = Double(color.brightnessComponent)
   guard saturation > 0.16, brightness > 0.16, color.alphaComponent > 0.5 else { continue }
   let index = min(15, Int(color.hueComponent * 16))
   let weight = saturation * saturation * (0.4 + brightness)
   buckets[index].weight += weight; buckets[index].r += Double(color.redComponent) * weight; buckets[index].g += Double(color.greenComponent) * weight; buckets[index].b += Double(color.blueComponent) * weight
  } }
  guard let strongest = buckets.max(by: { $0.weight < $1.weight }), strongest.weight > 0 else { return .neutral }
  let base = NSColor(red: strongest.r / strongest.weight, green: strongest.g / strongest.weight, blue: strongest.b / strongest.weight, alpha: 1)
  let vivid = NSColor(calibratedHue: base.hueComponent, saturation: min(1, max(0.75, base.saturationComponent * 1.3)), brightness: min(0.82, max(0.48, base.brightnessComponent * 0.88)), alpha: 1).usingColorSpace(.deviceRGB)!
  let tone = ArtworkTint(red: vivid.redComponent, green: vivid.greenComponent, blue: vivid.blueComponent)
  for step in 0...40 {
   let mix = Double(step) * 0.01
   let result = ArtworkTint(red: tone.red + (1-tone.red)*mix, green: tone.green + (1-tone.green)*mix, blue: tone.blue + (1-tone.blue)*mix)
   if result.luminance >= 0.14 { return result }
  }
  return tone
 }
}
