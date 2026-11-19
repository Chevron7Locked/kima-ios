#!/usr/bin/env swift
// glyph-centroids — measure and eyeball SF Symbol optical centering.
// Not wired to any gate on purpose: this is the provenance tool for the nudge table
// shipping in PlaybackController+Audible.swift — re-run it whenever a glyph changes.
//
// Reproduces the numbers behind PlaybackController.TransportDisplayState.opticalNudgeWeight
// (ticket 19): where a glyph's ink mass sits vs its layout-box center, which is what reads
// off-center inside a disc. Run from anywhere:
//
//   swift scripts/glyph-centroids.swift measure [glyph ...]     # default play.fill pause.fill arrow.clockwise
//   swift scripts/glyph-centroids.swift sheet <out.png> [nudge ...]  # default nudges 0 1.5 2
//
// measure prints each glyph's centroid offset as a % of box width (negative = mass left of
// center); multiply by the rendered glyph's layout width for the pt nudge that centers it.
// sheet renders both transport discs (mini 40pt/16pt, player 72pt/28pt) with each glyph at
// each nudge against a center guide line — view the PNG to judge honestly.
//
// Why 512pt: centroids of small renders are dominated by pixel quantization — pause.fill,
// symmetric by design, reads ±0.6 px off-center at 16 pt. A big render averages that out;
// the fraction is size-independent and scales down.

import AppKit

let config = NSImage.SymbolConfiguration(pointSize: 512, weight: .semibold)

func symbol(_ name: String) -> NSBitmapImageRep? {
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil),
          let img = base.withSymbolConfiguration(config),
          let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return nil }
    return rep
}

/// Ink centroid vs layout-box center, as a fraction of box width (negative = mass left).
func centroidOffset(_ rep: NSBitmapImageRep) -> Double? {
    var sumX = 0.0, total = 0.0
    let w = rep.pixelsWide, h = rep.pixelsHigh
    for y in stride(from: 0, to: h, by: 2) { for x in stride(from: 0, to: w, by: 2) {
        guard let a = rep.colorAt(x: x, y: y)?.alphaComponent else { continue }
        sumX += Double(x) * Double(a); total += Double(a)
    }}
    guard total > 0 else { return nil }
    return (sumX / total - Double(w - 1) / 2.0) / Double(w)
}

func measure(_ glyphs: [String]) {
    for name in glyphs {
        guard let rep = symbol(name), let off = centroidOffset(rep) else { print("\(name): nil"); continue }
        print(String(format: "%@: mass %+0.2f%% of box width %@",
                     name, off * 100, off < -0.005 ? "(needs a rightward nudge)" : ""))
    }
}

func sheet(outPath: String, nudges: [CGFloat]) {
    let scale: CGFloat = 4
    let discs: [(name: String, discPt: CGFloat, glyphPt: CGFloat)] = [
        ("mini 40pt disc / 16pt glyph", 40, 16),
        ("player 72pt disc / 28pt glyph", 72, 28),
    ]
    let glyphs = ["play.fill", "arrow.clockwise"]
    let gap: CGFloat = 10 * scale
    let labelH: CGFloat = 26 * scale
    let maxDisc: CGFloat = 72
    let cols = nudges.count
    let width = (maxDisc * scale + gap) * CGFloat(cols) + gap
    let height = (labelH + maxDisc * scale + gap) * CGFloat(discs.count * glyphs.count)
    let img = NSImage(size: NSSize(width: width, height: height))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    NSColor(calibratedWhite: 0.07, alpha: 1).setFill()
    CGRect(x: 0, y: 0, width: width, height: height).fill()
    var y = height
    for disc in discs {
        for glyph in glyphs {
            y -= labelH
            NSAttributedString(string: "\(disc.name) — \(glyph)", attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 13 * scale / 2),
            ]).draw(at: CGPoint(x: gap, y: y + 4))
            y -= maxDisc * scale
            for (i, nudge) in nudges.enumerated() {
                let cell = maxDisc * scale
                let ox = gap + CGFloat(i) * (cell + gap)
                let cx = ox + cell / 2, cy = y + cell / 2
                ctx.setFillColor(NSColor(calibratedWhite: 0.16, alpha: 1).cgColor)
                ctx.fillEllipse(in: CGRect(x: cx - disc.discPt * scale / 2 + 2 * scale,
                                           y: cy - disc.discPt * scale / 2 + 2 * scale,
                                           width: (disc.discPt - 4) * scale, height: (disc.discPt - 4) * scale))
                ctx.setStrokeColor(NSColor(calibratedWhite: 1.0, alpha: 0.35).cgColor)
                ctx.setLineWidth(1)
                ctx.move(to: CGPoint(x: cx, y: cy - disc.discPt * scale / 2 + 4 * scale))
                ctx.addLine(to: CGPoint(x: cx, y: cy + disc.discPt * scale / 2 - 4 * scale))
                ctx.strokePath()
                if let base = NSImage(systemSymbolName: glyph, accessibilityDescription: nil),
                   let sym = base.withSymbolConfiguration(config) {
                    let f = disc.glyphPt / 512 * scale   // symbol layout size scales linearly with pointSize
                    let r = sym.size
                    sym.draw(in: CGRect(x: cx - r.width * f / 2 + nudge * scale,
                                        y: cy - r.height * f / 2,
                                        width: r.width * f, height: r.height * f))
                }
                NSAttributedString(string: String(format: "+%g pt", Double(nudge)), attributes: [
                    .foregroundColor: NSColor(calibratedWhite: 0.8, alpha: 1),
                    .font: NSFont.monospacedSystemFont(ofSize: 11 * scale / 2, weight: .regular),
                ]).draw(at: CGPoint(x: ox + 6, y: y - 18))
            }
            y -= gap
        }
    }
    img.unlockFocus()
    guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("sheet: render failed\n".data(using: .utf8)!); exit(1)
    }
    try! png.write(to: URL(fileURLWithPath: outPath))
    print("wrote \(outPath)")
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "measure": measure(args.count > 1 ? Array(args.dropFirst()) : ["play.fill", "pause.fill", "arrow.clockwise"])
case "sheet":
    guard args.count >= 2 else { print("usage: sheet <out.png> [nudge ...]"); exit(2) }
    sheet(outPath: args[1], nudges: args.count > 2
          ? args.dropFirst(2).compactMap { Double($0) }.map { CGFloat($0) } : [0, 1.5, 2])
default: print("usage: measure [glyph ...] | sheet <out.png> [nudge ...]")
}
