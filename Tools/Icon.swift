import AppKit
MainActor.assumeIsolated {
    let size = 1024
    let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
    let shape = NSBezierPath(roundedRect:NSRect(x:64,y:64,width:896,height:896),xRadius:205,yRadius:205)
    NSGradient(starting:NSColor(calibratedRed:1,green:0.63,blue:0.20,alpha:1),ending:NSColor(calibratedRed:0.98,green:0.32,blue:0.12,alpha:1))!.draw(in:shape,angle:-90)
    // Original vector paths; no third-party symbol assets.
    let flame=NSBezierPath()
    flame.move(to:NSPoint(x:508,y:220))
    flame.curve(to:NSPoint(x:715,y:420),controlPoint1:NSPoint(x:645,y:215),controlPoint2:NSPoint(x:744,y:320))
    flame.curve(to:NSPoint(x:560,y:820),controlPoint1:NSPoint(x:708,y:585),controlPoint2:NSPoint(x:605,y:695))
    flame.curve(to:NSPoint(x:488,y:592),controlPoint1:NSPoint(x:580,y:708),controlPoint2:NSPoint(x:535,y:650))
    flame.curve(to:NSPoint(x:393,y:688),controlPoint1:NSPoint(x:444,y:620),controlPoint2:NSPoint(x:412,y:661))
    flame.curve(to:NSPoint(x:307,y:425),controlPoint1:NSPoint(x:390,y:570),controlPoint2:NSPoint(x:300,y:545))
    flame.curve(to:NSPoint(x:508,y:220),controlPoint1:NSPoint(x:308,y:303),controlPoint2:NSPoint(x:394,y:218))
    flame.close(); NSColor.white.setFill(); flame.fill()
    let core=NSBezierPath()
    core.move(to:NSPoint(x:515,y:286))
    core.curve(to:NSPoint(x:597,y:390),controlPoint1:NSPoint(x:570,y:285),controlPoint2:NSPoint(x:614,y:333))
    core.curve(to:NSPoint(x:518,y:520),controlPoint1:NSPoint(x:590,y:443),controlPoint2:NSPoint(x:539,y:479))
    core.curve(to:NSPoint(x:443,y:387),controlPoint1:NSPoint(x:520,y:453),controlPoint2:NSPoint(x:446,y:444))
    core.curve(to:NSPoint(x:515,y:286),controlPoint1:NSPoint(x:429,y:332),controlPoint2:NSPoint(x:465,y:286))
    core.close(); NSColor(calibratedRed:1,green:0.44,blue:0.16,alpha:1).setFill();core.fill()
    NSGraphicsContext.restoreGraphicsState()
    try! bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
}
