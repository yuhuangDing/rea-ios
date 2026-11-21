import SwiftUI

extension Commander {
    func indicatedLane(current: Lane) -> Lane? {
        let active = Lane.allCases.filter { queues[$0]?.isEmpty == false }
        return active.first { readyBuilding(in:$0) != nil } ?? (active.contains(current) ? current : active.first)
    }
}

struct ProductionTray: View {
    @ObservedObject var session: GameSession
    let game: Battle, width: CGFloat, spacious: Bool
    let close: () -> Void
    private var player: Commander { game.players[0] }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let lane = session.lane
        let products = Catalog.options(player.nation,lane)
        let twoRows = spacious && products.count > 7
        VStack(alignment:.leading,spacing:0) {
            HStack(spacing:2) {
                if width >= 600 {
                    Louver(color:Palette.brass).padding(.leading,6)
                    Text("生产").font(.system(size:13,weight:.heavy)).padding(.trailing,4)
                }
                ForEach(Lane.allCases) { l in laneKey(l) }
                Spacer(minLength:0)
                Button(action:close) {
                    Image(systemName:"chevron.down").font(.system(size:13,weight:.heavy))
                        .frame(width:44,height:44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("收起生产栏").accessibilityIdentifier("hideProduction")
            }
            Rectangle().fill(Palette.line).frame(height:0.6)
            ScrollView(.horizontal,showsIndicators:true) {
                LazyHGrid(rows:Array(repeating:GridItem(.fixed(60),spacing:3),count:twoRows ? 2 : 1),spacing:5) {
                    ForEach(products) { b in
                        let lockReason = game.missing(b,owner:0).first.map { "需要" + Catalog.byID[Catalog.id($0,player.nation)]!.panelName }
                        productKey(b,locked:lockReason ?? (b.role == .dock && !game.settings.theater.allowsShipyards ? "需要海战地图" : nil))
                    }
                    ForEach([Support.airborne,.storm,.missile],id:\.self) { kind in
                        if let wait = game.readySupport(0,kind) {
                            Button {
                                session.cancelTarget(); session.support = kind; session.say("点可见地面指定支援位置")
                            } label: {
                                VStack(alignment:.leading,spacing:3) {
                                    Label(kind.panelName,systemImage:"scope").font(.system(size:12,weight:.bold))
                                    Text(wait == 0 ? "支援就绪" : "\(Int(ceil(wait)))s").font(Palette.mono(10))
                                }.frame(width:101,height:44).foregroundStyle(wait == 0 ? Palette.phosphor : Palette.muted)
                                    .background(ArmorOutline(cut:5).fill(.black.opacity(0.43)))
                            }.buttonStyle(.plain).disabled(wait > 0)
                        }
                    }
                }.padding(.horizontal,5)
            }.id(lane).frame(height:twoRows ? 127 : 62)
        }
        .padding(.horizontal,5).padding(.bottom,2).frame(width:width)
        .background(SteelPlate(cut:11)).shadow(color:.black.opacity(0.55),radius:3,y:2)
        .accessibilityElement(children:.contain).accessibilityIdentifier("productionTray")
    }

    private func laneKey(_ lane: Lane) -> some View {
        let selected = session.lane == lane, ready = player.readyBuilding(in:lane) != nil
        return Button { session.lane = lane } label: {
            HStack(spacing:3) {
                Image(systemName:lane.symbol).font(.system(size:12,weight:.semibold))
                if width >= 565 { Text(lane.rawValue).font(.system(size:11,weight:.bold)) }
            }.frame(minWidth:width >= 565 ? 45 : 41,minHeight:26)
                .foregroundStyle(selected ? Palette.ink : Palette.muted)
                .background { if selected { ArmorOutline(cut:5).fill(Palette.amber) } }
                .overlay(alignment:.topTrailing) {
                    if ready { Circle().fill(Palette.phosphor).frame(width:5,height:5).padding(1) }
                }
                .frame(minWidth:44,minHeight:44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(lane.rawValue+"生产").accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func productKey(_ b: Blueprint, locked: String?) -> some View {
        let work = player.work(for:b), ready = work.active?.ready == true
        let percent = min(99,Int(((work.active?.fraction(of:b) ?? 0)*100 + 1e-8).rounded(.down)))
        let working = work.active != nil && !ready
        let waiting = work.active?.waitingForFunds(b,credits:player.credits) == true
        let tint = ready ? Palette.phosphor : (waiting ? Palette.warning : Palette.amber)
        let state: String
        if ready { state = b.isBuilding ? "点按部署" : "待出厂" }
        else if working && locked != nil { state = "停工 \(percent)%" }
        else if waiting { state = "待资金 \(percent)%" }
        else if working { state = "\(percent)%" }
        else { state = "$\(String(b.stats.cost))" }
        let status: String
        if ready { status = (b.isBuilding ? "可部署" : "待出厂")+"，待产 \(work.pending)" }
        else if working {
            let phase = locked != nil ? "停工" : (waiting ? "等待资金" : "生产中")
            status = "待产 \(work.pending)，\(phase) \(percent)%"
        } else { status = locked ?? "价格 \(b.stats.cost)" }

        let artWidth: CGFloat = width < 565 ? 70 : 78
        let tapOrCancel = LongPressGesture(minimumDuration:0.5,maximumDistance:9).exclusively(before:TapGesture())
            .onEnded { event in
                switch event {
                case .first(true): session.cancelProduct(b,current:true)
                case .second: session.product(b)
                default: break
                }
            }
        return ZStack(alignment:.bottomLeading) {
            HStack(spacing:6) {
                ArtImage(name:b.stats.cameo,folder:"Cameos").aspectRatio(contentMode:.fill)
                    .frame(width:artWidth,height:58).clipped()
                    .saturation(locked != nil && !ready ? 0.15 : 1)
                    .opacity(locked != nil && !ready ? 0.6 : 1)
                    .overlay {
                        if let job = work.active, working {
                            if !reduceMotion && !session.paused && locked == nil && !waiting && game.outcome == .playing {
                                TimelineView(.animation(minimumInterval:1.0/30.0)) { _ in
                                    if let live = player.queues[b.lane]?.first(where:{ $0.type == b.id }), !live.ready {
                                        let end = live.fraction(of:b)
                                        let start = min(end,game.previousProductionFractions[b.id] ?? end)
                                        let alpha = (session.scene?.substepTime ?? Battle.step) / Battle.step
                                        ClockShade(fraction:start + (end-start)*alpha)
                                    }
                                }
                            } else { ClockShade(fraction:job.fraction(of:b)) }
                        }
                    }
                VStack(alignment:.leading,spacing:3) {
                    Text(b.panelName).font(.system(size:12,weight:.bold)).lineLimit(2).minimumScaleFactor(0.8)
                    HStack(spacing:2) {
                        if locked != nil && !working && !ready { Image(systemName:"lock.fill").font(.system(size:8)) }
                        Text(state).font(Palette.mono(10)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                    }.foregroundStyle(locked != nil && !ready ? Palette.muted : tint)
                }.frame(maxWidth:.infinity,alignment:.leading).padding(.top,10)
            }
            .padding(.leading,1).padding(.trailing,4).frame(width:width < 565 ? 138 : 153,height:60)
            .background(ArmorOutline(cut:5).fill(Palette.ink))
            .overlay(alignment:.topTrailing) {
                if work.pending > 0 {
                    Text("×\(work.pending)").font(Palette.mono(10,.heavy)).monospacedDigit()
                        .foregroundStyle(Palette.ink).padding(.horizontal,4).frame(minHeight:14)
                        .background(ArmorOutline(cut:2).fill(Palette.amber)).padding(2)
                }
            }.clipShape(ArmorOutline(cut:5))
            .overlay(ArmorOutline(cut:5).strokeBorder(work.active != nil ? tint.opacity(0.82) : Palette.line,lineWidth:0.8))
            .contentShape(Rectangle()).gesture(tapOrCancel)
            .accessibilityElement(children:.ignore).accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("build-"+b.id)
            .accessibilityLabel(ready && b.isBuilding ? "部署"+b.name : b.name).accessibilityValue(status)
            .accessibilityActivationPoint(UnitPoint(x:0.76,y:0.50))
            .accessibilityHint(ready && b.isBuilding ? "点按选择建筑位置，长按取消这座建筑。" : "点按生产一件，长按取消当前一件并退回已付资金。")
            .accessibilityAction { session.product(b) }
            .accessibilityActions {
                if work.active != nil { Button("取消当前一件并退款") { session.cancelProduct(b,current:true) } }
            }

            HStack(spacing:0) {
                quantityKey(b,adding:false,enabled:work.active != nil,width:artWidth/2)
                quantityKey(b,adding:true,enabled:locked == nil,width:artWidth/2)
            }.padding(.leading,1)
        }
    }

    private func quantityKey(_ b: Blueprint, adding: Bool, enabled: Bool, width: CGFloat) -> some View {
        Button {
            if adding { session.product(b,addCopy:true) } else { session.cancelProduct(b) }
        } label: {
            Image(systemName:adding ? "plus" : "minus").font(.system(size:12,weight:.heavy))
                .foregroundStyle(enabled ? (adding ? Palette.amber : Palette.text) : Palette.muted.opacity(0.82))
                .frame(width:width-2,height:19)
                .background(ArmorOutline(cut:3).fill(Palette.ink.opacity(0.94)))
                .overlay(ArmorOutline(cut:3).strokeBorder(Palette.brass.opacity(enabled ? 0.7 : 0.38),lineWidth:0.7))
                .padding(.bottom,2).frame(width:width,height:29,alignment:.bottom).contentShape(Rectangle())
        }.buttonStyle(QuantityButtonStyle()).disabled(!enabled)
        .accessibilityLabel((adding ? "增加一件" : "减少一件")+b.panelName)
        .accessibilityIdentifier((adding ? "plus-" : "minus-")+b.id)
    }
}

private struct QuantityButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.72 : 1)
    }
}

private struct ClockShade: View {
    let fraction: Double
    var body: some View {
        Canvas { ctx,size in
            let p = min(1,max(0,fraction)), rect = CGRect(origin:.zero,size:size)
            guard p < 1 else { return }
            let shade = Color(red:0.035,green:0.06,blue:0.07).opacity(0.78)
            guard p > 0 else { ctx.fill(Path(rect),with:.color(shade)); return }
            let center = CGPoint(x:rect.midX,y:rect.midY), radius = hypot(rect.midX,rect.midY)+1
            let angle = Angle.degrees(-90+360*p)
            var sector = Path()
            sector.move(to:center)
            sector.addArc(center:center,radius:radius,startAngle:angle,endAngle:.degrees(270),clockwise:false)
            sector.closeSubpath()
            ctx.fill(sector,with:.color(shade))
            var edge = Path(); edge.move(to:center)
            edge.addLine(to:CGPoint(x:center.x+cos(angle.radians)*radius,y:center.y+sin(angle.radians)*radius))
            ctx.stroke(edge,with:.color(Palette.amber.opacity(0.85)),lineWidth:0.85)
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
extension Support {
    var panelName: String {
        switch self { case .airborne:return "空降伞兵"; case .storm:return "闪电风暴"; case .missile:return "战略打击" }
    }
}
