import SwiftUI
import WidgetKit
import AppKit
import CoreText

struct CrispWidgetText: View {
 let text: String
 let size: CGFloat
 var strong = false
 var lines = 1
 var color = ArtworkTint.neutral
 var boxed = false
 private var lineHeight: CGFloat { GlyphArtwork.lineHeight(size: size, strong: strong) }
 private var naturalWidth: CGFloat { GlyphArtwork.width(text, size: size, strong: strong) }
 var body: some View {
  ViewThatFits(in: .horizontal) {
   picture(width: naturalWidth, lines: 1).fixedSize()
   GeometryReader { geometry in
    picture(width: max(2, geometry.size.width), lines: lines)
     .frame(maxWidth: .infinity, alignment: .leading)
   }.frame(height: lineHeight * CGFloat(lines))
  }.accessibilityElement(children: .ignore).accessibilityLabel(text).help(text)
 }
 @ViewBuilder private func picture(width: CGFloat, lines: Int) -> some View {
  if let image = GlyphArtwork.render(text, width: width, size: size, strong: strong, lines: lines, color: color, boxed: boxed) {
   Image(decorative: image, scale: 2).widgetAccentedRenderingMode(.fullColor)
    .frame(width: ceil(width * 2) / 2, height: lineHeight * CGFloat(lines), alignment: .leading)
  }
 }
}

private enum GlyphArtwork {
 private static func attributes(size: CGFloat, strong: Bool, color: ArtworkTint, stroke: Bool = true) -> [NSAttributedString.Key: Any] {
  let system = NSFont.systemFont(ofSize: size, weight: strong ? .semibold : .regular)
  let font = CTFontCreateWithName(system.fontName as CFString, size, nil)
  return [
   NSAttributedString.Key(kCTFontAttributeName as String): font,
   NSAttributedString.Key(kCTForegroundColorAttributeName as String): stroke ? CGColor(gray: 0, alpha: 0.94) : CGColor(red: color.red, green: color.green, blue: color.blue, alpha: 1),
   NSAttributedString.Key(kCTStrokeColorAttributeName as String): CGColor(gray: 0, alpha: 0.94),
   NSAttributedString.Key(kCTStrokeWidthAttributeName as String): stroke ? -120 / size : 0
  ]
 }
 static func lineHeight(size: CGFloat, strong: Bool) -> CGFloat {
  let attrs = attributes(size: size, strong: strong, color: .neutral)
  let font = attrs[NSAttributedString.Key(kCTFontAttributeName as String)] as! CTFont
  return ceil(CTFontGetAscent(font) + CTFontGetDescent(font) + 1.5)
 }
 static func width(_ text: String, size: CGFloat, strong: Bool) -> CGFloat {
  let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes(size: size, strong: strong, color: .neutral)))
  return ceil(CTLineGetTypographicBounds(line, nil, nil, nil)) + 2
 }
 static func render(_ text: String, width: CGFloat, size: CGFloat, strong: Bool, lines maximumLines: Int, color: ArtworkTint, boxed: Bool = false) -> CGImage? {
  guard width > 1 else { return nil }
  let attrs = attributes(size: size, strong: strong, color: color)
  let value = NSAttributedString(string: text, attributes: attrs)
  let fillValue = NSAttributedString(string: text, attributes: attributes(size: size, strong: strong, color: color, stroke: false))
  let setter = CTFramesetterCreateWithAttributedString(value)
  let path = CGPath(rect: CGRect(x: 0, y: 0, width: max(1, width - 2), height: 10000), transform: nil)
  let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil)
  let textLines = CTFrameGetLines(frame) as! [CTLine]
  let count = min(maximumLines, textLines.count)
  let lineHeight = self.lineHeight(size: size, strong: strong)
  let height = lineHeight * CGFloat(maximumLines)
  guard let context = CGContext(data: nil, width: max(1, Int(ceil(width * 2))), height: max(1, Int(ceil(height * 2))), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
  context.scaleBy(x: 2, y: 2); context.setLineJoin(.round); context.setShouldAntialias(true)
  if boxed {
   context.setFillColor(CGColor(gray: 0, alpha: 0.92))
   context.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: width, height: height), cornerWidth: 3, cornerHeight: 3, transform: nil)); context.fillPath()
  }
  let font = attrs[NSAttributedString.Key(kCTFontAttributeName as String)] as! CTFont
  let ascent = CTFontGetAscent(font)
  let descent = CTFontGetDescent(font)
  let inset = (lineHeight - ascent - descent) / 2
  for index in 0..<count {
   let range = CTLineGetStringRange(textLines[index])
   let truncated = index == maximumLines - 1 && textLines.count > maximumLines
   let length = truncated ? value.length - range.location : range.length
   let part = NSRange(location: range.location, length: length)
   let fillAttrs = attributes(size: size, strong: strong, color: color, stroke: false)
   let passes: [(NSAttributedString, [NSAttributedString.Key: Any])] = boxed ? [(fillValue, fillAttrs)] : [(value, attrs), (fillValue, fillAttrs)]
   for (source, passAttrs) in passes {
    var line = CTLineCreateWithAttributedString(source.attributedSubstring(from: part))
    if truncated {
     let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: passAttrs))
     line = CTLineCreateTruncatedLine(line, max(1, width - 2), .end, ellipsis) ?? line
    }
    context.textPosition = CGPoint(x: 1, y: height - ascent - CGFloat(index) * lineHeight - inset)
    CTLineDraw(line, context)
   }
  }
  return context.makeImage()
 }
}
