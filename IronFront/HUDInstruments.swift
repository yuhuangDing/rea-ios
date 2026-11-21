import SwiftUI

struct ResourceConsole: View {
    let game: Battle, pause: () -> Void
    var body: some View {
        let e = game.energy(0), low = e.used > e.made
        HStack(spacing:0) {
            Button(action:pause) {
                Image(systemName:"pause.fill").font(.system(size:12,weight:.heavy))
                    .frame(width:26,height:26).background(Circle().fill(.black.opacity(0.52)))
                    .overlay(Circle().stroke(Palette.line,lineWidth:1)).frame(width:44,height:44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("暂停对战")
            HStack(spacing:5) {
                Image(systemName:"banknote.fill").font(.system(size:12)).foregroundStyle(Palette.amber)
                Text(String(game.players[0].credits)).font(Palette.mono(13,.bold))
            }.accessibilityElement(children:.ignore).accessibilityLabel("资金 \(game.players[0].credits)")
            Rectangle().fill(Palette.line).frame(width:1,height:15).padding(.horizontal,9)
            HStack(spacing:4) {
                Image(systemName:low ? "bolt.trianglebadge.exclamationmark.fill" : "bolt.fill")
                    .font(.system(size:12)).foregroundStyle(low ? Palette.warning : Palette.phosphor)
                Text("\(e.used)/\(e.made)").font(Palette.mono(12))
            }.accessibilityElement(children:.ignore).accessibilityLabel("用电 \(e.used)，发电 \(e.made)")
            .padding(.trailing,12)
        }.fixedSize().background { SteelPlate(cut:8).padding(.vertical,5) }
    }
}

struct SensorConsole: View {
    @ObservedObject var session: GameSession
    let game: Battle, compact: Bool
    @Binding var open: Bool
    var body: some View {
        let online = game.radarOnline(0)
        VStack(alignment:.trailing,spacing:1) {
            HStack(spacing:5) {
                VStack(alignment:.trailing,spacing:0) {
                    Text(String(format:"%02d:%02d",Int(game.time)/60,Int(game.time)%60)).font(Palette.mono(12,.bold))
                    Text(game.isPractice ? "自由演练" : "\(game.players.filter { !$0.eliminated }.count) 国存活").font(.system(size:9,weight:.semibold)).foregroundStyle(Palette.muted)
                }.padding(.leading,11)
                Button { open.toggle() } label: {
                    RadarDial(online:online,open:open).frame(width:27,height:27).frame(width:44,height:44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(open ? "收起雷达" : "展开雷达")
                    .accessibilityValue(online ? "在线" : "离线")
            }.fixedSize().background { SteelPlate(cut:8).padding(.vertical,5) }
            if open {
                if online {
                    radarMap.frame(width:compact ? 112 : 155,height:compact ? 112 : 155)
                        .padding(5).background(SteelPlate(cut:8))
                } else {
                    let built = !game.owned(0,.radar).isEmpty
                    VStack(alignment:.leading,spacing:4) {
                        Label("雷达离线",systemImage:"antenna.radiowaves.left.and.right.slash").font(.caption.bold())
                        Text(built ? "恢复供电以接入雷达" : "需要"+Catalog.byID[Catalog.id(.radar,game.players[0].nation)]!.name)
                            .font(.system(size:11)).foregroundStyle(Palette.muted)
                    }.padding(.horizontal,10).padding(.vertical,8).background(SteelPlate(cut:6))
                }
            }
        }
    }
    private var viewportDescription: String {
        guard let edges = session.scene?.radarViewport, edges.count == 4 else { return "" }
        let x = Int(((edges[0].x + edges[2].x)/2).rounded()), y = Int(((edges[0].y + edges[2].y)/2).rounded())
        return "地图中心 \(x)，\(y)，横向视野 \(Int(edges[0].distance(edges[1]).rounded())) 格"
    }
    private var radarMap: some View {
        GeometryReader { g in
            Canvas { ctx,s in
                let n = Battlefield.size
                var bytes = [UInt8](repeating:255,count:n*n*4)
                for i in game.map.tiles.indices {
                    let rgb = Cartography.color(game.map.tiles[i],game.map.theater)
                    let light = game.visible[i] != 0 ? 1.0 : (game.explored[i] != 0 ? 0.51 : 0.13)
                    bytes[i*4] = UInt8(Double(rgb.0)*light*0.84)
                    bytes[i*4+1] = UInt8(Double(rgb.1)*light); bytes[i*4+2] = UInt8(Double(rgb.2)*light*0.87)
                }
                ctx.draw(Image(decorative:Cartography.pixels(bytes,side:n),scale:1,orientation:.up),in:CGRect(origin:.zero,size:s))
                func onMap(_ p: Point) -> CGPoint { CGPoint(x:p.x*s.width/CGFloat(n),y:p.y*s.height/CGFloat(n)) }
                for site in game.map.oreMines where game.explored[site] != 0 {
                    let p = onMap(Battlefield.cell(site).center)
                    ctx.fill(Path(ellipseIn:CGRect(x:p.x-1.5,y:p.y-1.5,width:3,height:3)),with:.color(Palette.amber))
                }
                for p in game.pieces.values where p.owner == 0 || game.isVisible(p.pos) {
                    let center = onMap(p.pos), diameter: CGFloat = p.spec.isBuilding ? 3.5 : 2
                    ctx.fill(Path(CGRect(x:center.x-diameter/2,y:center.y-diameter/2,width:diameter,height:diameter)),
                             with:.color(Color(uiColor:Palette.team[p.owner])))
                }
                let corners = session.scene?.radarViewport.map(onMap) ?? []
                if let a = corners.first {
                    var outline = Path(); outline.move(to:a); corners.dropFirst().forEach { outline.addLine(to:$0) }; outline.closeSubpath()
                    ctx.stroke(outline,with:.color(Palette.phosphor),lineWidth:1)
                }
            }.clipShape(ArmorOutline(cut:4)).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance:0).onChanged { v in
                let n = Double(Battlefield.size)
                session.scene?.focus(Point(max(0.5,min(n-0.5,v.location.x/g.size.width*n)),
                                           max(0.5,min(n-0.5,v.location.y/g.size.height*n))))
            }).accessibilityElement(children:.ignore).accessibilityLabel("战场雷达")
                .accessibilityValue(viewportDescription).accessibilityIdentifier("radarMap")
        }
    }
}
private struct RadarDial: View {
    let online: Bool, open: Bool
    var body: some View {
        Canvas { ctx,s in
            let length = min(s.width,s.height), center = CGPoint(x:length/2,y:length/2)
            let rect = CGRect(x:1,y:1,width:length-2,height:length-2)
            let trace = online ? Palette.phosphor : Palette.brass
            ctx.fill(Path(ellipseIn:rect),with:.color(Color(red:0.065,green:0.12,blue:0.085)))
            ctx.stroke(Path(ellipseIn:rect),with:.color(trace.opacity(0.85)),lineWidth:1)
            ctx.stroke(Path(ellipseIn:rect.insetBy(dx:4,dy:4)),with:.color(trace.opacity(0.46)),lineWidth:0.7)
            var cross = Path()
            cross.move(to:.init(x:center.x,y:2)); cross.addLine(to:.init(x:center.x,y:length-2))
            cross.move(to:.init(x:2,y:center.y)); cross.addLine(to:.init(x:length-2,y:center.y))
            ctx.stroke(cross,with:.color(trace.opacity(0.36)),lineWidth:0.6)
            var ray = Path(); ray.move(to:center); ray.addLine(to:.init(x:length*0.78,y:length*0.19))
            ctx.stroke(ray,with:.color(trace),lineWidth:1.5)
            ctx.fill(Path(ellipseIn:CGRect(x:length*0.68,y:length*0.37,width:2.4,height:2.4)),with:.color(trace))
            if open { ctx.stroke(Path(ellipseIn:rect.insetBy(dx:1,dy:1)),with:.color(trace),lineWidth:1.2) }
        }.accessibilityHidden(true)
    }
}
