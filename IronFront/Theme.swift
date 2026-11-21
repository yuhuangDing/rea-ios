import SwiftUI
import UIKit
import AVFAudio

enum Palette {
    static let ink = Color(red:0.063,green:0.085,blue:0.082)
    static let panel = Color(red:0.096,green:0.125,blue:0.119)
    static let raised = Color(red:0.147,green:0.177,blue:0.163)
    static let line = Color(red:0.68,green:0.70,blue:0.57).opacity(0.34)
    static let phosphor = Color(red:0.62,green:0.89,blue:0.65)
    static let brass = Color(red:0.78,green:0.65,blue:0.40)
    static let warning = Color(red:1,green:0.49,blue:0.32)
    static let text = Color(red:0.94,green:0.935,blue:0.86)
    static let muted = Color(red:0.65,green:0.70,blue:0.64)
    static let amber = Color(red:0.99,green:0.71,blue:0.29)
    static let team: [UIColor] = [.init(red:0.42,green:0.91,blue:0.69,alpha:1),.systemRed,.systemBlue,.systemOrange,.systemPurple,.systemYellow,.systemPink,.systemCyan]
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font { .system(size:size,weight:weight,design:.monospaced) }
}

enum Pictures {
    private static let cache = NSCache<NSString,UIImage>()
    static func get(_ name: String, folder: String = "Sprites", ext: String = "png") -> UIImage? {
        let key = "\(folder)/\(name).\(ext)" as NSString
        if let image = cache.object(forKey:key) { return image }
        let dir = folder.isEmpty ? "Art" : "Art/\(folder)"
        guard let url = Bundle.main.url(forResource:name,withExtension:ext,subdirectory:dir),
              let img = UIImage(contentsOfFile:url.path) else { return nil }
        cache.setObject(img,forKey:key); return img
    }
}
struct ArtImage: View {
    let name: String; var folder = "Sprites"; var ext = "png"
    var body: some View {
        if let image = Pictures.get(name,folder:folder,ext:ext) { Image(uiImage:image).resizable() }
    }
}
final class GameAudio {
    static let shared = GameAudio()
    private var players: [String:AVAudioPlayer] = [:]
    var enabled = true
    func play(_ cue: String) {
        guard enabled else { return }
        if players[cue] == nil, let url = Bundle.main.url(forResource:cue,withExtension:"wav",subdirectory:"Art/Audio") {
            players[cue] = try? AVAudioPlayer(contentsOf:url); players[cue]?.volume = cue == "contact" ? 0.17 : 0.30
        }
        guard let voice = players[cue] else { return }
        if !voice.isPlaying { voice.currentTime = 0; voice.play() }
    }
}
/// The two opposing clipped corners are shared by stamped labels, cast housings and action levers.
struct ArmorOutline: InsettableShape {
    var cut: CGFloat = 9
    private var insetAmount: CGFloat = 0
    init(cut: CGFloat = 9) { self.cut = cut }
    func path(in bounds: CGRect) -> Path {
        let r = bounds.insetBy(dx:insetAmount,dy:insetAmount)
        let c = max(0,min(cut-insetAmount,r.width/3,r.height/3)), small = min(2,c)
        var p = Path()
        p.move(to:CGPoint(x:r.minX+c,y:r.minY)); p.addLine(to:CGPoint(x:r.maxX-small,y:r.minY))
        p.addLine(to:CGPoint(x:r.maxX,y:r.minY+small)); p.addLine(to:CGPoint(x:r.maxX,y:r.maxY-c))
        p.addLine(to:CGPoint(x:r.maxX-c,y:r.maxY)); p.addLine(to:CGPoint(x:r.minX+small,y:r.maxY))
        p.addLine(to:CGPoint(x:r.minX,y:r.maxY-small)); p.addLine(to:CGPoint(x:r.minX,y:r.minY+c))
        p.closeSubpath(); return p
    }
    func inset(by amount: CGFloat) -> Self {
        var result = self; result.insetAmount += amount; return result
    }
}

struct SteelPlate: View {
    var cut: CGFloat = 9
    var bolted = false
    var body: some View {
        let shape = ArmorOutline(cut:cut)
        ZStack {
            shape.fill(Palette.ink)
            if let texture = Pictures.get("field-steel",folder:"",ext:"jpg") {
                Image(uiImage:texture).resizable(resizingMode:.tile).opacity(bolted ? 0.78 : 0.53).clipShape(shape)
            }
            shape.fill(LinearGradient(colors:[.white.opacity(0.065),.clear,.black.opacity(0.44)],startPoint:.topLeading,endPoint:.bottomTrailing))
            shape.strokeBorder(LinearGradient(colors:[Color(white:0.62).opacity(0.72),Palette.line,.black.opacity(0.92)],startPoint:.top,endPoint:.bottom),lineWidth:1)
            shape.inset(by:2).strokeBorder(.black.opacity(0.46),lineWidth:0.8)
            if bolted {
                VStack {
                    HStack { Rivet(); Spacer(); Rivet() }; Spacer(); HStack { Rivet(); Spacer(); Rivet() }
                }.padding(8)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
private struct Rivet: View {
    var body: some View {
        Circle().fill(LinearGradient(colors:[Color(white:0.53),Color(white:0.15)],startPoint:.topLeading,endPoint:.bottomTrailing))
            .overlay { Capsule().fill(.black.opacity(0.85)).frame(width:3.5,height:1).rotationEffect(.degrees(-35)) }
            .overlay(Circle().stroke(.black.opacity(0.75),lineWidth:0.6)).frame(width:5,height:5)
    }
}
struct Louver: View {
    var color: Color = Palette.ink.opacity(0.68)
    var body: some View {
        Canvas { ctx,s in
            for n in 0..<3 {
                let x = CGFloat(n)*s.width/3
                var p = Path(); p.move(to:CGPoint(x:x,y:s.height)); p.addLine(to:CGPoint(x:x+4,y:0))
                ctx.stroke(p,with:.color(color),lineWidth:2.2)
            }
        }.frame(width:15,height:11).accessibilityHidden(true)
    }
}
struct SignalLamp: View {
    let color: Color
    var body: some View {
        Circle().fill(color).frame(width:5,height:5).overlay(Circle().stroke(.white.opacity(0.4),lineWidth:0.55))
            .padding(2).background(Circle().fill(.black.opacity(0.65))).accessibilityHidden(true)
    }
}
struct FrontInsignia: View {
    var body: some View {
        Canvas { ctx,s in
            let w = s.width, h = s.height
            var shield = Path()
            shield.move(to:CGPoint(x:0.10*w,y:0.10*h)); shield.addLine(to:CGPoint(x:0.90*w,y:0.10*h))
            shield.addLine(to:CGPoint(x:0.84*w,y:0.68*h)); shield.addLine(to:CGPoint(x:0.50*w,y:0.94*h))
            shield.addLine(to:CGPoint(x:0.16*w,y:0.68*h)); shield.closeSubpath()
            ctx.stroke(shield,with:.color(Palette.brass),lineWidth:1.4)
            for baseline in [0.35,0.52] {
                var chevron = Path()
                chevron.move(to:CGPoint(x:w*0.25,y:h*(baseline+0.14)))
                chevron.addLine(to:CGPoint(x:w*0.50,y:h*baseline))
                chevron.addLine(to:CGPoint(x:w*0.75,y:h*(baseline+0.14)))
                ctx.stroke(chevron,with:.color(Palette.amber),style:StrokeStyle(lineWidth:w*0.095,lineCap:.square,lineJoin:.miter))
            }
        }.accessibilityHidden(true)
    }
}

struct PanelButton: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        let shape = ArmorOutline(cut:7)
        configuration.label.font(.system(size:13,weight:.bold)).lineLimit(1)
            .foregroundStyle(primary ? Palette.ink : Palette.text)
            .padding(.horizontal,12).frame(minHeight:34)
            .background {
                if primary {
                    shape.fill(LinearGradient(colors:[Color(red:1,green:0.80,blue:0.45),Palette.amber,Color(red:0.79,green:0.52,blue:0.20)],startPoint:.top,endPoint:.bottom))
                        .overlay(shape.inset(by:2).strokeBorder(.black.opacity(0.28),lineWidth:0.75))
                } else { SteelPlate(cut:7) }
            }.opacity(configuration.isPressed ? 0.72 : 1)
            .frame(minHeight:44).contentShape(Rectangle())
    }
}

extension Blueprint {
    var panelName: String {
        for prefix in ["盟军","苏军"] where name.hasPrefix(prefix) { return String(name.dropFirst(prefix.count)) }
        return name
    }
}
extension Nation {
    var signatureArt: String {
        switch self {
        case .usa: return "E1"; case .uk: return "SNIPE"; case .france: return "GTGCAN"
        case .germany: return "TNKD"; case .korea: return "BEAG"; case .russia: return "TTNK"
        case .iraq: return "DESO"; case .cuba: return "TERROR"; case .libya: return "DTRUCK"
        }
    }
    var sideName: String { side == .allied ? "盟军" : "苏军" }
}
