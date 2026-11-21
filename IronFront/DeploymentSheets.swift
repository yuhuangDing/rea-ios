import SwiftUI

struct SheetHeading: View {
    let title: String, symbol: String, close: String
    let action: () -> Void
    var body: some View {
        HStack(spacing:9) {
            Image(systemName:symbol).foregroundStyle(Palette.brass)
            Text(title).font(.system(size:23,weight:.black))
            Spacer()
            Button(action:action) {
                Label(close,systemImage:close == "关闭" ? "xmark" : "checkmark")
            }.buttonStyle(PanelButton(primary:close != "关闭"))
        }
    }
}

struct CountryPicker: View {
    @Environment(\.dismiss) private var dismiss
    let current: Nation, pick: (Nation) -> Void
    var body: some View {
        GeometryReader { g in
            let columns = Array(repeating:GridItem(.flexible(minimum:0),spacing:7),count:g.size.width > 440 ? 3 : 2)
            VStack(alignment:.leading,spacing:6) {
                SheetHeading(title:"选择国家",symbol:"flag.2.crossed",close:"关闭"){dismiss()}
                ScrollView {
                    LazyVGrid(columns:columns,spacing:5) {
                        ForEach(Nation.allCases) { n in
                            let chosen = n == current
                            Button {pick(n)} label: {
                                HStack(spacing:5) {
                                    Text(n.flag).font(.system(size:21))
                                    VStack(alignment:.leading,spacing:3) {
                                        Text(n.name).font(.system(size:14,weight:.bold))
                                        Text(n.signature).font(.system(size:10)).foregroundStyle(Palette.muted)
                                    }.lineLimit(1)
                                    Spacer(minLength:1)
                                    if chosen { Image(systemName:"checkmark").font(.caption.bold()).foregroundStyle(Palette.amber) }
                                }.padding(.horizontal,9).frame(maxWidth:.infinity,minHeight:46)
                                    .background(ArmorOutline(cut:7).fill(chosen ? Palette.amber.opacity(0.13) : .black.opacity(0.38)))
                                    .overlay(ArmorOutline(cut:7).strokeBorder(chosen ? Palette.amber : Palette.line))
                            }.buttonStyle(.plain).accessibilityLabel(n.name).accessibilityValue("\(n.sideName)，\(n.signature)")
                                .accessibilityAddTraits(chosen ? .isSelected : [])
                        }
                    }
                }
            }.padding(.horizontal,16).padding(.vertical,8)
        }.background(SteelPlate(cut:0).ignoresSafeArea()).foregroundStyle(Palette.text)
    }
}

struct BattleSettings: View {
    @Binding var setup: MatchSettings
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        GeometryReader { g in
            VStack(alignment:.leading,spacing:4) {
                SheetHeading(title:"战场设置",symbol:"map",close:"完成"){dismiss()}
                if g.size.width >= 485 {
                    HStack(alignment:.top,spacing:10) {
                        ScrollView { maps }.frame(maxWidth:.infinity).accessibilityIdentifier("mapList")
                        if g.size.width >= 615 {
                            deploymentPreview.frame(width:min(144,g.size.width*0.16))
                        }
                        ScrollView {
                            options
                            if g.size.width < 615 { deploymentPreview.padding(.top,5) }
                        }.frame(width:min(232,g.size.width*0.28))
                    }.frame(maxWidth:.infinity,alignment:.topLeading)
                } else {
                    ScrollView { VStack(alignment:.leading,spacing:10) { maps; options } }
                        .accessibilityIdentifier("mapList")
                }
            }.padding(.horizontal,14).padding(.vertical,7)
        }.background(SteelPlate(cut:0).ignoresSafeArea()).foregroundStyle(Palette.text)
    }

    private var maps: some View {
        LazyVGrid(columns:[GridItem(.adaptive(minimum:132),spacing:5)],spacing:4) {
            ForEach(Theater.allCases) { t in
                let chosen = setup.theater == t
                Button { setup.theater = t } label: {
                    HStack(spacing:6) {
                        MapThumbnail(theater:t,seats:setup.playerCount)
                            .frame(width:42,height:42).clipShape(ArmorOutline(cut:3))
                        VStack(alignment:.leading,spacing:3) {
                            Text(t.rawValue).font(.system(size:13,weight:.bold))
                            Text(t.detail).font(.system(size:10)).foregroundStyle(Palette.muted)
                        }.lineLimit(1).minimumScaleFactor(0.76)
                        Spacer(minLength:0)
                    }.padding(3).frame(maxWidth:.infinity,alignment:.leading)
                        .background(ArmorOutline(cut:5).fill(chosen ? Palette.amber.opacity(0.10) : .black.opacity(0.36)))
                        .overlay(ArmorOutline(cut:5).strokeBorder(chosen ? Palette.amber : Palette.line,lineWidth:chosen ? 1.5 : 0.7))
                }.buttonStyle(.plain).accessibilityLabel(t.rawValue).accessibilityValue(t.detail)
                    .accessibilityIdentifier("field-"+t.code).accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }.padding(1)
    }
    private var deploymentPreview: some View {
        VStack(alignment:.leading,spacing:5) {
            MapThumbnail(theater:setup.theater,seats:setup.playerCount)
                .aspectRatio(1,contentMode:.fit).clipShape(ArmorOutline(cut:5))
                .overlay(ArmorOutline(cut:5).strokeBorder(Palette.line))
            Text("\(setup.playerCount) / \(MatchSettings.maxPlayers) 席").font(Palette.mono(11,.bold))
            HStack(spacing:3) {
                Circle().fill(Palette.phosphor).frame(width:5,height:5); Text("你")
                if !setup.opponents.isEmpty {
                    Circle().fill(Palette.amber).frame(width:5,height:5).padding(.leading,3); Text("电脑")
                }
            }.font(.system(size:10,weight:.medium)).foregroundStyle(Palette.muted)
            Label(setup.theater.allowsShipyards ? "可建船坞" : "陆地作战",
                  systemImage:setup.theater.allowsShipyards ? "ferry" : "mountain.2")
                .font(.system(size:10,weight:.semibold)).foregroundStyle(Palette.brass)
        }.accessibilityElement(children:.combine)
    }

    private var options: some View {
        VStack(alignment:.leading,spacing:3) {
            Text("电脑难度").font(.caption.bold()).foregroundStyle(Palette.muted)
            HStack(spacing:0) {
                ForEach(Difficulty.allCases) { d in
                    Button { setup.difficulty = d } label:{settingKey(d.rawValue,selected:setup.difficulty == d)}
                        .accessibilityAddTraits(setup.difficulty == d ? .isSelected : [])
                }
            }
            Text("起始资金").font(.caption.bold()).foregroundStyle(Palette.muted)
            HStack(spacing:0) {
                ForEach([5000,10000,20000],id:\.self) { amount in
                    Button {setup.credits = amount} label:{settingKey("$\(String(amount))",selected:setup.credits == amount)}
                        .accessibilityAddTraits(setup.credits == amount ? .isSelected : [])
                }
            }
            Toggle("战争迷雾",isOn:$setup.fog).font(.subheadline.weight(.semibold)).tint(Palette.brass)
                .frame(minHeight:44)
        }.buttonStyle(.plain)
    }
    private func settingKey(_ label: String, selected: Bool) -> some View {
        Text(label).font(Palette.mono(12)).lineLimit(1).minimumScaleFactor(0.8)
            .foregroundStyle(selected ? Palette.ink : Palette.text)
            .frame(maxWidth:.infinity,minHeight:28)
            .background(ArmorOutline(cut:4).fill(selected ? Palette.amber : .black.opacity(0.40)))
            .padding(.horizontal,1).frame(minHeight:44).contentShape(Rectangle())
    }
}

struct MapThumbnail: View {
    private let terrain: CGImage, positions: [Point]
    private static let atlas: [Theater:CGImage] = Dictionary(uniqueKeysWithValues:Theater.allCases.map { theater in
        let map = theater.layout
        return (theater,render(theater,tiles:map.tiles) { map.ore[$0] > 0 })
    })

    init(theater: Theater, seats: Int) {
        terrain = Self.atlas[theater]!
        positions = theater.layout.seats(for:seats)
    }

    init(map: Battlefield) {
        // A legacy match keeps its saved terrain. The briefing shows fixed resource sites.
        if map.tiles == map.theater.layout.tiles { terrain = Self.atlas[map.theater]! }
        else { terrain = Self.render(map.theater,tiles:map.tiles,resourceAt:map.oreMines.contains) }
        positions = map.seats
    }

    private static func render(_ theater: Theater, tiles: [Ground], resourceAt: (Int) -> Bool) -> CGImage {
        var bytes = [UInt8](repeating:255,count:tiles.count*4)
        for (i,t) in tiles.enumerated() {
            let c = Cartography.color(t,theater), k = i*4, deposit = resourceAt(i)
            bytes[k] = deposit ? 174 : UInt8(c.0)
            bytes[k+1] = deposit ? 147 : UInt8(c.1)
            bytes[k+2] = deposit ? 70 : UInt8(c.2)
        }
        return Cartography.pixels(bytes,side:Battlefield.size)
    }

    var body: some View {
        Canvas { ctx,s in
            let bounds = CGRect(origin:.zero,size:s), n = CGFloat(Battlefield.size)
            ctx.draw(Image(decorative:terrain,scale:1,orientation:.up),in:bounds)
            var grid = Path()
            for i in 1..<6 {
                let x = CGFloat(i)*s.width/6, y = CGFloat(i)*s.height/6
                grid.move(to:.init(x:x,y:0)); grid.addLine(to:.init(x:x,y:s.height))
                grid.move(to:.init(x:0,y:y)); grid.addLine(to:.init(x:s.width,y:y))
            }
            ctx.stroke(grid,with:.color(.white.opacity(0.15)),lineWidth:0.5)
            for (i,point) in positions.enumerated() {
                let x = point.x*s.width/n, y = point.y*s.height/n
                let marker = Path(ellipseIn:CGRect(x:x-1.9,y:y-1.9,width:3.8,height:3.8))
                ctx.fill(marker,with:.color(i == 0 ? Palette.phosphor : Palette.amber))
                ctx.stroke(marker,with:.color(Palette.ink),lineWidth:0.7)
            }
        }.accessibilityHidden(true)
    }
}
