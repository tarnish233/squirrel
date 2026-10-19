// Lays out screenshots in a grid with captions, for comparing preview variants.
//   contact-sheet <output.png> <columns> <caption=image.png>...
import AppKit

let args = CommandLine.arguments
guard args.count > 3, let columns = Int(args[2]) else {
  FileHandle.standardError.write("usage: contact-sheet <output.png> <columns> <caption=image.png>...\n".data(using: .utf8)!)
  exit(2)
}
let items: [(String, NSImage)] = args[3...].compactMap { item in
  let parts = item.split(separator: "=", maxSplits: 1).map(String.init)
  guard parts.count == 2, let image = NSImage(contentsOfFile: parts[1]) else { return nil }
  // screenshots are at 2x; draw them at their point size
  if let rep = image.representations.first { image.size = NSSize(width: rep.pixelsWide / 2, height: rep.pixelsHigh / 2) }
  return (parts[0], image)
}
let cellWidth = items.map(\.1.size.width).max() ?? 0
let imageHeight = items.map(\.1.size.height).max() ?? 0
let captionHeight: CGFloat = 24, gap: CGFloat = 12
let rows = (items.count + columns - 1) / columns
let size = NSSize(width: CGFloat(columns) * (cellWidth + gap) + gap, height: CGFloat(rows) * (imageHeight + captionHeight + gap) + gap)
let sheet = NSImage(size: size, flipped: true) { _ in
  NSColor(white: 0.5, alpha: 1).setFill()
  NSRect(origin: .zero, size: size).fill()
  for (i, (caption, image)) in items.enumerated() {
    let x = gap + CGFloat(i % columns) * (cellWidth + gap)
    let y = gap + CGFloat(i / columns) * (imageHeight + captionHeight + gap)
    NSAttributedString(string: caption, attributes: [.font: NSFont.boldSystemFont(ofSize: 14), .foregroundColor: NSColor.white])
      .draw(at: NSPoint(x: x, y: y + 2))
    image.draw(in: NSRect(x: x, y: y + captionHeight, width: image.size.width, height: image.size.height),
               from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
  }
  return true
}
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
sheet.draw(in: NSRect(origin: .zero, size: size))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[1]))
print("\(args[1]) \(Int(size.width))×\(Int(size.height))")
