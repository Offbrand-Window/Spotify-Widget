import AppKit
let image=NSImage(size:NSSize(width:1024,height:1024));image.lockFocus()
let tile=NSBezierPath(roundedRect:NSRect(x:48,y:48,width:928,height:928),xRadius:206,yRadius:206)
NSGradient(starting:NSColor(red:0.17,green:0.24,blue:0.21,alpha:1),ending:NSColor(red:0.035,green:0.055,blue:0.045,alpha:1))!.draw(in:tile,angle:135)
NSColor.white.withAlphaComponent(0.24).setStroke();tile.lineWidth=3;tile.stroke()
let disc=NSBezierPath(ovalIn:NSRect(x:206,y:206,width:612,height:612))
NSGradient(starting:NSColor(red:0.34,green:0.72,blue:0.52,alpha:1),ending:NSColor(red:0.03,green:0.10,blue:0.07,alpha:1))!.draw(in:disc,angle:145)
for radius:CGFloat in [292,266,240,213] { let ring=NSBezierPath(ovalIn:NSRect(x:512-radius,y:512-radius,width:2*radius,height:2*radius));NSColor.white.withAlphaComponent(0.12).setStroke();ring.lineWidth=2;ring.stroke() }
let center=NSBezierPath(ovalIn:NSRect(x:385,y:385,width:254,height:254));NSColor.black.withAlphaComponent(0.25).setFill();center.fill()
NSColor.white.withAlphaComponent(0.22).setStroke();center.lineWidth=2;center.stroke()
let play=NSBezierPath();play.move(to:NSPoint(x:473,y:416));play.line(to:NSPoint(x:473,y:608));play.line(to:NSPoint(x:630,y:512));play.close();NSColor.white.setFill();play.fill()
let glint=NSBezierPath();glint.move(to:NSPoint(x:260,y:850));glint.curve(to:NSPoint(x:765,y:850),controlPoint1:NSPoint(x:400,y:890),controlPoint2:NSPoint(x:630,y:890));NSColor.white.withAlphaComponent(0.17).setStroke();glint.lineWidth=3;glint.stroke()
image.unlockFocus()
let png=NSBitmapImageRep(data:image.tiffRepresentation!)!.representation(using:.png,properties:[:])!
try png.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
