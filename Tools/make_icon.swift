// Generates the ProMe app icon set (iOS + macOS) into the asset catalog.
// Run: swift Tools/make_icon.swift
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let catalogPath = "App/ProMe/Resources/Assets.xcassets/AppIcon.appiconset"

func png(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let size = CGFloat(1024)

// Load the bundled Shabnam Bold face for the monogram.
func shabnamBold() -> CGFont {
    let candidates = [
        URL(fileURLWithPath: "Packages/ProMeDesignSystem/Sources/ProMeDesignSystem/Resources/Fonts/Shabnam-Bold.ttf"),
        URL(fileURLWithPath: "App/ProMe/Resources/Shabnam-Bold.ttf"),
    ]
    for url in candidates where FileManager.default.fileExists(atPath: url.path) {
        if let provider = CGDataProvider(url: url as CFURL), let font = CGFont(provider) {
            return font
        }
    }
    // Fall back to Helvetica Neue Bold if Shabnam is not found.
    return CGFont("Helvetica-Bold" as CFString)!
}

func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func drawSpark(_ ctx: CGContext, center: CGPoint, radius: CGFloat) {
    // Four-point "sparkle" star used as the ProMe signature mark.
    let path = CGMutablePath()
    let thin = radius * 0.22
    path.move(to: CGPoint(x: center.x, y: center.y + radius))
    path.addQuadCurve(to: CGPoint(x: center.x + radius, y: center.y), control: CGPoint(x: center.x + thin, y: center.y + thin))
    path.addQuadCurve(to: CGPoint(x: center.x, y: center.y - radius), control: CGPoint(x: center.x + thin, y: center.y - thin))
    path.addQuadCurve(to: CGPoint(x: center.x - radius, y: center.y), control: CGPoint(x: center.x - thin, y: center.y - thin))
    path.addQuadCurve(to: CGPoint(x: center.x, y: center.y + radius), control: CGPoint(x: center.x - thin, y: center.y + thin))
    ctx.setFillColor(CGColor(srgbRed: 1.0, green: 0.78, blue: 0.28, alpha: 1))
    ctx.addPath(path)
    ctx.fillPath()
}

func render(macOSStyle: Bool, scale: CGFloat = 1) -> CGImage {
    let canvas = CGSize(width: size * scale, height: size * scale)
    let ctx = CGContext(data: nil, width: Int(canvas.width), height: Int(canvas.height),
                        bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: scale, y: scale)

    let inset = macOSStyle ? CGFloat(100) : 0
    let tile = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = macOSStyle ? tile.width * 0.225 : 0

    ctx.saveGState()
    if macOSStyle {
        ctx.addPath(roundedPath(tile, radius: radius))
        ctx.clip()
    }

    // Diagonal gradient: indigo -> cyan.
    let colors = [
        CGColor(srgbRed: 0.36, green: 0.40, blue: 0.95, alpha: 1),   // indigo
        CGColor(srgbRed: 0.16, green: 0.50, blue: 0.87, alpha: 1),   // blue
        CGColor(srgbRed: 0.03, green: 0.60, blue: 0.72, alpha: 1),   // cyan
    ]
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: colors as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: tile.minX, y: tile.maxY),
                           end: CGPoint(x: tile.maxX, y: tile.minY), options: [])

    // Soft radial highlight from the top.
    let highlight = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                               colors: [CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.22),
                                        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0)] as CFArray,
                               locations: [0, 1])!
    ctx.drawRadialGradient(highlight,
                           startCenter: CGPoint(x: tile.midX, y: tile.maxY * 0.9), startRadius: 0,
                           endCenter: CGPoint(x: tile.midX, y: tile.maxY * 0.9), endRadius: tile.width * 0.8,
                           options: [])

    // The "P" monogram as a geometric vector mark: a rounded stem plus a
    // ring bowl. Constructed from paths so the icon is fully deterministic
    // (no font metric surprises) and scales crisply.
    let stemW: CGFloat = 0.115
    let stem = CGPath(roundedRect: CGRect(x: tile.minX + tile.width * 0.30,
                                          y: tile.minY + tile.height * 0.24,
                                          width: tile.width * stemW,
                                          height: tile.height * 0.52),
                      cornerWidth: tile.width * stemW * 0.45,
                      cornerHeight: tile.width * stemW * 0.45, transform: nil)
    let bowlCenter = CGPoint(x: tile.minX + tile.width * 0.545, y: tile.minY + tile.height * 0.575)
    let bowlOuter = CGPath(ellipseIn: CGRect(x: bowlCenter.x - tile.width * 0.165,
                                             y: bowlCenter.y - tile.height * 0.165,
                                             width: tile.width * 0.33, height: tile.height * 0.33), transform: nil)
    let bowlInner = CGPath(ellipseIn: CGRect(x: bowlCenter.x - tile.width * 0.088,
                                             y: bowlCenter.y - tile.height * 0.088,
                                             width: tile.width * 0.176, height: tile.height * 0.176), transform: nil)
    ctx.setFillColor(CGColor.white)
    ctx.addPath(stem)
    ctx.fillPath()
    ctx.addPath(bowlOuter)
    ctx.addPath(bowlInner)
    ctx.fillPath(using: .evenOdd)

    ctx.restoreGState()

    // Amber spark at the upper right of the monogram.
    drawSpark(ctx, center: CGPoint(x: tile.minX + tile.width * 0.74, y: tile.minY + tile.height * 0.74),
              radius: tile.width * 0.075)

    return ctx.makeImage()!
}

try? FileManager.default.createDirectory(atPath: catalogPath, withIntermediateDirectories: true)

// iOS: single full-bleed 1024 icon.
png(render(macOSStyle: false), to: "\(catalogPath)/icon-ios-1024.png")
// macOS: rounded-rect artwork on a transparent canvas (single-size icon).
png(render(macOSStyle: true), to: "\(catalogPath)/icon-mac-1024.png")

let contents = """
{
  "images" : [
    {
      "filename" : "icon-mac-1024.png",
      "idiom" : "mac",
      "platform" : "macos",
      "size" : "1024x1024"
    },
    {
      "filename" : "icon-ios-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
try! contents.write(toFile: "\(catalogPath)/Contents.json", atomically: true, encoding: .utf8)
print("Icons generated in \(catalogPath)")
