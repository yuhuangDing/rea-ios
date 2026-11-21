import SwiftUI

private enum DeploymentSheet: Identifiable {
    case theater, country(Int?)
    var id: String {
        switch self { case .theater: return "theater"; case .country(let seat): return "seat-\(seat ?? -1)" }
    }
}

struct Lobby: View {
    @ObservedObject var session: GameSession
    @State private var sheet: DeploymentSheet?
    @State private var replace = false

    var body: some View {
        GeometryReader { g in
            let tall = g.size.height > 500
            let margin: CGFloat = tall ? 26 : 10
            let rightWidth = min(505, (g.size.width - 2*margin) * (tall ? 0.49 : 0.54))
            HStack(spacing:tall ? 30 : 12) {
                VStack(alignment:.leading,spacing:0) {
                    HStack(spacing:7) {
                        FrontInsignia().frame(width:tall ? 36 : 29,height:tall ? 40 : 33)
                        Text("IRON FRONT").font(Palette.mono(tall ? 15 : 12,.heavy)).tracking(2.7)
                    }.padding(.top,3)
                    Spacer()
                    HStack(spacing:7) { Louver(color:Palette.amber); Text(session.setup.opponents.isEmpty ? "单人演练" : "单人遭遇战").font(.system(size:12,weight:.bold)).tracking(1) }
                    Text("铁幕前线").font(.system(size:tall ? 65 : 41,weight:.black)).tracking(-1.7)
                        .lineLimit(1).minimumScaleFactor(0.75).shadow(color:.black.opacity(0.68),radius:3,y:2)
                    mapKey.padding(.top,tall ? 20 : 7)
                }.padding(.leading,tall ? 12 : 3).padding(.bottom,tall ? 6 : 0)
                    .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.leading)
                roster(width:rightWidth,tall:tall)
                    .frame(width:rightWidth)
                    .frame(maxHeight:.infinity,alignment:.center)
            }
            .padding(.horizontal,margin).padding(.vertical,tall ? 27 : 7)
            .foregroundStyle(Palette.text)
        }
        .background {
            GeometryReader { g in
                ZStack(alignment:.leading) {
                    Color(red:0.075,green:0.086,blue:0.075)
                    if let metal = Pictures.get("field-steel",folder:"",ext:"jpg") { Image(uiImage:metal).resizable(resizingMode:.tile).opacity(0.5) }
                    ArtImage(name:"frontline",folder:"",ext:"jpg").scaledToFill()
                        .frame(width:g.size.width*0.72,height:g.size.height).clipped()
                        .mask(LinearGradient(stops:[.init(color:.white,location:0.65),.init(color:.clear,location:1)],startPoint:.leading,endPoint:.trailing))
                    LinearGradient(stops:[.init(color:.black.opacity(0.34),location:0),.init(color:.clear,location:0.34),
                                          .init(color:.black.opacity(0.14),location:0.57),.init(color:.black.opacity(0.83),location:1)],
                                   startPoint:.top,endPoint:.bottom)
                }
            }.ignoresSafeArea()
        }
        .sheet(item:$sheet) { item in
            switch item {
            case .theater: BattleSettings(setup:$session.setup)
            case .country(let slot):
                let country = slot.map { session.setup.opponents[$0] } ?? session.setup.nation
                CountryPicker(current:country) { n in
                    if let slot { session.setup.opponents[slot] = n } else { session.setup.nation = n }
                    sheet = nil
                }
            }
        }
        .confirmationDialog("新对战将替换已有存档",isPresented:$replace,titleVisibility:.visible) {
            Button("开始新对战",role:.destructive){session.start()}; Button("取消",role:.cancel){}
        }
    }

    private var mapKey: some View {
        Button { sheet = .theater } label: {
            HStack(spacing:9) {
                MapThumbnail(theater:session.setup.theater,seats:session.setup.playerCount)
                    .frame(width:59,height:36).clipShape(ArmorOutline(cut:4))
                VStack(alignment:.leading,spacing:2) {
                    Text(session.setup.theater.rawValue).font(.system(size:14,weight:.bold))
                    Text("\(session.setup.opponents.isEmpty ? "自由演练" : session.setup.difficulty.rawValue) · $\(String(session.setup.credits))")
                        .font(Palette.mono(10)).foregroundStyle(Palette.muted)
                }
                Spacer(minLength:3); Image(systemName:"slider.horizontal.3").foregroundStyle(Palette.amber)
            }.padding(.horizontal,9).frame(height:48).background(SteelPlate(cut:9))
        }.buttonStyle(.plain).accessibilityLabel("战场设置").accessibilityValue(session.setup.theater.rawValue).accessibilityIdentifier("mapSettings")
    }

    private func roster(width: CGFloat, tall: Bool) -> some View {
        let columns = width >= 317 && session.setup.opponents.count > 4 ? 3 : 2
        let margin: CGFloat = tall ? 18 : 12
        return ViewThatFits(in:.vertical) {
            VStack(alignment:.leading,spacing:0) {
                rosterHeading(tall)
                playerSeat(tall).padding(.top,tall ? 10 : 4)
                opponentCount
                opponentGrid(columns)
                footer.padding(.top,tall ? 10 : 4)
            }.padding(.horizontal,margin).padding(.vertical,tall ? 18 : 11).fixedSize(horizontal:false,vertical:true)
            VStack(alignment:.leading,spacing:0) {
                rosterHeading(false)
                ScrollView { VStack(spacing:0) { playerSeat(false); opponentCount; opponentGrid(columns) } }
                footer
            }.padding(.horizontal,margin).padding(.vertical,9)
        }
        .background(SteelPlate(cut:tall ? 20 : 13,bolted:true))
        .shadow(color:.black.opacity(0.62),radius:7,x:0,y:4)
    }
    private func rosterHeading(_ tall: Bool) -> some View {
        HStack(spacing:6) {
            Text("作战部署").font(.system(size:tall ? 29 : 23,weight:.black)).tracking(1)
            Spacer()
            HStack(spacing:2) {
                ForEach(0..<8,id:\.self) { i in
                    Capsule().fill(i <= session.setup.opponents.count ? Color(uiColor:Palette.team[i]) : Color.white.opacity(0.16))
                        .frame(width:3,height:10)
                }
            }.accessibilityHidden(true)
            Text("\(session.setup.playerCount)/\(MatchSettings.maxPlayers)").font(Palette.mono(11)).foregroundStyle(Palette.muted)
                .accessibilityLabel("参战席位").accessibilityValue("\(session.setup.playerCount)").accessibilityIdentifier("seatCount")
        }.padding(.horizontal,3)
    }
    private func playerSeat(_ tall: Bool) -> some View {
        let n = session.setup.nation
        return Button { sheet = .country(nil) } label: {
            HStack(spacing:7) {
                Rectangle().fill(Palette.phosphor).frame(width:2,height:25)
                Text(n.flag).font(.system(size:23))
                VStack(alignment:.leading,spacing:1) {
                    Text("我的国家").font(.system(size:9,weight:.bold)).foregroundStyle(Palette.phosphor)
                    Text(n.name).font(.system(size:tall ? 20 : 17,weight:.heavy))
                }
                Spacer(minLength:3)
                Text(n.signature).font(.system(size:11,weight:.semibold)).foregroundStyle(Palette.muted).lineLimit(1)
                ArtImage(name:n.signatureArt).scaledToFit().frame(width:tall ? 66 : 46,height:tall ? 50 : 39)
                Image(systemName:"chevron.up.chevron.down").font(.system(size:9,weight:.bold)).foregroundStyle(Palette.brass)
            }.padding(.horizontal,9).frame(height:tall ? 64 : 49)
                .background {
                    let shape = ArmorOutline(cut:8)
                    shape.fill(LinearGradient(colors:[Color(red:0.13,green:0.19,blue:0.14),Palette.ink],startPoint:.leading,endPoint:.trailing))
                    shape.strokeBorder(Palette.phosphor.opacity(0.32))
                }
        }.buttonStyle(.plain).accessibilityLabel("玩家国家，\(n.name)")
    }
    private var opponentCount: some View {
        HStack(spacing:0) {
            Image(systemName:"person.2.fill").font(.caption).foregroundStyle(Palette.brass).padding(.trailing,5)
            Text("电脑对手").font(.system(size:12,weight:.bold)); Spacer()
            Button { _ = session.setup.opponents.popLast() } label:{ counterGlyph("minus") }
                .disabled(session.setup.opponents.isEmpty).accessibilityLabel("减少电脑")
            Text("\(session.setup.opponents.count)").font(Palette.mono(14,.bold)).foregroundStyle(Palette.amber)
            Button {
                let used = Set([session.setup.nation]+session.setup.opponents)
                session.setup.opponents.append(Nation.allCases.first { !used.contains($0) } ?? .russia)
            } label: { counterGlyph("plus") }
                .disabled(session.setup.playerCount >= MatchSettings.maxPlayers).accessibilityLabel("增加电脑")
        }.buttonStyle(.plain).padding(.leading,2)
    }
    private func counterGlyph(_ name: String) -> some View {
        Image(systemName:name).font(.system(size:11,weight:.bold))
            .frame(width:24,height:23).background(ArmorOutline(cut:5).fill(.black.opacity(0.43)))
            .overlay(ArmorOutline(cut:5).strokeBorder(Palette.line))
            .frame(width:44,height:44).contentShape(Rectangle())
    }
    private func opponentGrid(_ columns: Int) -> some View {
        LazyVGrid(columns:Array(repeating:GridItem(.flexible(minimum:0),spacing:5),count:columns),spacing:0) {
            ForEach(session.setup.opponents.indices,id:\.self) { i in
                let n = session.setup.opponents[i]
                Button { sheet = .country(i) } label: {
                    HStack(spacing:4) {
                        Text(String(format:"%02d",i+1)).font(Palette.mono(9,.bold)).foregroundStyle(Color(uiColor:Palette.team[i+1]))
                        Text(n.flag).font(.system(size:16))
                        Text(n.name).font(.system(size:12,weight:.bold)).lineLimit(1).minimumScaleFactor(0.80)
                        Spacer(minLength:0)
                        Image(systemName:"chevron.down").font(.system(size:7,weight:.bold)).foregroundStyle(Palette.muted)
                    }.padding(.horizontal,7).frame(height:33)
                        .background(ArmorOutline(cut:5).fill(.black.opacity(0.34)))
                        .overlay(alignment:.bottom){Capsule().fill(Palette.line).frame(height:0.65).padding(.horizontal,5)}
                        .frame(maxWidth:.infinity,minHeight:44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("电脑 \(i+1)，\(n.name)")
            }
        }
    }
    @ViewBuilder private var footer: some View {
        if !session.setupMessage.isEmpty { Text(session.setupMessage).font(.caption).foregroundStyle(Palette.amber) }
        HStack(spacing:6) {
            if session.hasSave {
                Button {session.resumeSave()} label:{Label("继续对战",systemImage:"play.circle.fill")}
                    .buttonStyle(PanelButton()).accessibilityIdentifier("resumeMatch")
            }
            Button { if session.hasSave { replace = true } else { session.start() } } label: {
                HStack(spacing:7) { Louver(); Text(session.setup.opponents.isEmpty ? "开始演练" : "开始对战"); Spacer(minLength:3); Image(systemName:"arrow.right") }
            }.buttonStyle(PanelButton(primary:true)).accessibilityIdentifier("startMatch")
        }
    }
}
