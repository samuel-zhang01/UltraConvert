import AppKit

// The app icon is repo-native vector artwork; render at 1024px with real alpha.
let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                             isPlanar: false, colorSpaceName: .deviceRGB,
                             bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let context = NSGraphicsContext.current!.cgContext
context.translateBy(x: 0, y: 1024)
context.scaleBy(x: 1, y: -1)
let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 202, yRadius: 202)
NSGradient(starting: NSColor(srgbRed: 0.941, green: 0.973, blue: 1, alpha: 1), ending: NSColor(srgbRed: 0.863, green: 0.914, blue: 1, alpha: 1))!.draw(in: tile, angle: 45)
let p = NSBezierPath()
func m(_ x: CGFloat, _ y: CGFloat) { p.move(to: NSPoint(x: x, y: y)) }
func l(_ x: CGFloat, _ y: CGFloat) { p.line(to: NSPoint(x: x, y: y)) }
func c(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ x: CGFloat, _ y: CGFloat) {
    p.curve(to: NSPoint(x: x, y: y), controlPoint1: NSPoint(x: x1, y: y1), controlPoint2: NSPoint(x: x2, y: y2))
}
let gradient = NSGradient(colors: [NSColor(srgbRed: 0, green: 0.616, blue: 1, alpha: 1),
                                  NSColor(srgbRed: 0.157, green: 0.451, blue: 1, alpha: 1),
                                  NSColor(srgbRed: 0.455, green: 0.333, blue: 0.937, alpha: 1)])!
func paint() {
    NSGraphicsContext.saveGraphicsState()
    p.addClip()
    gradient.draw(from: NSPoint(x: 200, y: 260), to: NSPoint(x: 820, y: 830), options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation])
    NSGraphicsContext.restoreGraphicsState()
    p.removeAllPoints()
}
// U base and independent arrow paths overlap without self-intersecting geometry.
m(264,440); l(360,440); l(360,600); c(360,690,405,734,512,734)
c(619,734,664,690,664,600); l(664,390); l(760,390); l(760,600)
c(760,755,666,830,512,830); c(358,830,264,755,264,600); p.close(); paint()
m(280,260); c(264,260,264,260,264,276); l(264,440); l(212,440)
c(195,440,195,440,206,454); l(300,557); c(312,571,312,571,324,557)
l(418,454); c(429,440,429,440,412,440); l(360,440); l(360,276)
c(360,260,360,260,344,260); p.close(); paint()
m(664,390); l(612,390); c(595,390,595,390,606,376); l(700,273)
c(712,259,712,259,724,273); l(818,376); c(829,390,829,390,812,390)
l(760,390); p.close(); paint()
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
