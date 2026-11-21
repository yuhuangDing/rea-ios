import SwiftUI

private enum CommandDock { case field, production, orders }

struct CommandView: View {
    @ObservedObject var session: GameSession
    let game: Battle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dock: CommandDock = .field
    @State private var radarOpen = false
    @State private var sellID: Int?

    private var targeting: Bool { session.placementBlueprint != nil || session.support != nil }
    private var modal: Bool { session.paused || game.outcome != .playing }

    var body: some View {
        ZStack {
            FieldView(session:session).ignoresSafeArea()
                .allowsHitTesting(!modal).accessibilityHidden(modal)
            GeometryReader { g in
                let landscape = g.size.width, spacious = g.size.height > 510
                let margin: CGFloat = spacious ? 13 : 6
                ZStack {
                    VStack(alignment:.leading,spacing:0) {
                        ResourceConsole(game:game){session.paused = true}
                        if !session.notice.isEmpty {
                            HStack(spacing:5) {
                                Image(systemName:"waveform").font(.system(size:10,weight:.bold)).foregroundStyle(Palette.brass)
                                Text(session.notice).font(.system(size:11,weight:.semibold)).lineLimit(2)
                            }.padding(.horizontal,8).padding(.vertical,4)
                                .background(ArmorOutline(cut:4).fill(Palette.ink.opacity(0.90)))
                                .frame(maxWidth:min(landscape*0.49,302),alignment:.leading).allowsHitTesting(false)
                        }
                    }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
                    SensorConsole(session:session,game:game,compact:!spacious,open:$radarOpen)
                        .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topTrailing)
                    VStack(spacing:0) {
                        if targeting {
                            targetingDock.transition(.opacity)
                        } else {
                            switch dock {
                            case .field: fieldDock(room:landscape-2*margin)
                            case .production:
                                ProductionTray(session:session,game:game,width:min(landscape-2*margin,spacious ? 810 : 675),spacious:spacious) {
                                    show(.field)
                                }.transition(.opacity)
                            case .orders: ordersDock(room:min(landscape-2*margin,630)).transition(.opacity)
                            }
                        }
                    }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.bottom)
                }.padding(.horizontal,margin).padding(.vertical,spacious ? 6 : 2)
            }.allowsHitTesting(!modal).accessibilityHidden(modal)
            if modal { BattleReport(session:session,game:game) }
        }.foregroundStyle(Palette.text).background(Palette.ink.ignoresSafeArea()).preferredColorScheme(.dark)
        .confirmationDialog("变卖选中的建筑？",isPresented:Binding(get:{sellID != nil},set:{if !$0 {sellID = nil}}),titleVisibility:.visible) {
            if let id = sellID {
                Button("确认变卖",role:.destructive) {
                    if game.sell(id,owner:0) { session.select([]); session.epoch += 1 }
                }
            }
            Button("取消",role:.cancel){}
        }
    }

    private func show(_ mode: CommandDock) {
        withAnimation(reduceMotion ? nil : .easeOut(duration:0.14)) { dock = mode }
    }
    private func fieldDock(room: CGFloat) -> some View {
        HStack(spacing:room < 550 ? 2 : 6) {
            HStack(spacing:0) {
                key("scope","基地定位") {session.centerBase()}
                key("viewfinder","框选",active:session.boxSelect) {
                    session.cancelTarget(); session.boxSelect.toggle()
                    if session.boxSelect {session.say("拖动框选己方部队")}
                }
                key("person.3.fill","全军") {session.selectArmy()}
            }.background { SteelPlate(cut:8).padding(.vertical,5) }
            Spacer(minLength:1)
            HStack(spacing:0) {
                unitMenu(compact:room < 540)
                if let selected = session.selected {
                    if selected.spec.role == .mcv {
                        Button {
                            session.deploy()
                            if selected.spec.role == .yard { session.lane = .construction; show(.production) }
                        } label:{Label("展开基地",systemImage:"arrow.down.left.and.arrow.up.right")}
                            .buttonStyle(PanelButton(primary:true)).accessibilityLabel("展开基地")
                    } else if !selected.spec.isBuilding {
                        key("arrow.up.forward","进攻移动",active:session.advance,caption:"进攻") {
                            session.advance.toggle(); if session.advance {session.say("点地面行进，沿途遇敌时交战")}
                        }
                        key("stop.fill","停止") {
                            for id in session.selection {game.pieces[id]?.stop()}
                            session.advance = false; session.say("部队已停止")
                        }
                    }
                }
            }.background { SteelPlate(cut:8).padding(.vertical,4) }
            productionKey
        }
    }
    private func key(_ icon: String,_ name: String,active: Bool = false,caption: String? = nil,action: @escaping ()->Void) -> some View {
        Button(action:action) {
            HStack(spacing:3) {
                Image(systemName:icon).font(.system(size:15,weight:.bold))
                if let caption { Text(caption).font(.system(size:10,weight:.bold)) }
            }
                .foregroundStyle(active ? Palette.amber : Palette.text)
                .frame(minWidth:32,minHeight:26)
                .overlay(alignment:.bottom){ if active { Capsule().fill(Palette.amber).frame(width:13,height:2) } }
                .frame(width:44,height:44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(name).accessibilityAddTraits(active ? .isSelected : [])
    }
    private func ordersDock(room: CGFloat) -> some View {
        HStack(spacing:4) {
            Image(systemName:"chevron.right.2").font(.caption.bold()).foregroundStyle(Palette.brass).accessibilityHidden(true)
            ScrollView(.horizontal,showsIndicators:false) {
                HStack(spacing:4) {
                    if let p = session.selected, p.spec.isBuilding {
                        orderKey(p.repairing ? "停止维修" : "维修","wrench.adjustable") {
                            p.repairing.toggle(); session.say(p.repairing ? "建筑将消耗资金维修" : "已停止维修"); session.epoch += 1
                        }
                        orderKey("变卖","dollarsign.circle",tone:Palette.warning) {sellID = p.id}
                    } else if let p = session.selected, p.type == "E1" && session.selection.count == 1 {
                        orderKey(p.entrenched ? "收起阵地" : "部署","shield") {p.stop(); p.entrenched.toggle(); session.epoch += 1}
                    }
                    orderKey("记录当前所选","flag"){session.group(record:true)}
                    orderKey("召回编队","flag.fill"){session.group(record:false)}
                    ForEach([Support.airborne,.storm,.missile],id:\.self) { kind in
                        if let wait = game.readySupport(0,kind) {
                            orderKey(wait == 0 ? kind.panelName : "\(kind.panelName) · \(Int(ceil(wait)))s","scope",tone:Palette.phosphor) {
                                session.cancelTarget(); session.support = kind; session.say("点可见地面指定支援位置")
                            }.disabled(wait > 0)
                        }
                    }
                }
            }
            key("chevron.down","收起单位指令"){show(.field)}
        }.padding(.horizontal,7).frame(width:room,height:46)
            .background(SteelPlate(cut:9)).accessibilityElement(children:.contain).accessibilityIdentifier("ordersTray")
    }
    private func orderKey(_ title: String,_ symbol: String,tone: Color = Palette.text,_ action: @escaping () -> Void) -> some View {
        Button {action(); show(.field)} label: {
            Label(title,systemImage:symbol).font(.system(size:12,weight:.semibold)).foregroundStyle(tone)
                .padding(.horizontal,7).frame(minHeight:28).background(ArmorOutline(cut:4).fill(.black.opacity(0.38)))
                .frame(minWidth:44,minHeight:44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(title)
    }
    private func unitMenu(compact: Bool) -> some View {
        Button {show(.orders)} label: {
            HStack(spacing:5) {
                if let p = session.selected {
                    ArtImage(name:p.type).scaledToFit().frame(width:compact ? 22 : 34,height:28)
                    if !compact {
                        VStack(alignment:.leading,spacing:3) {
                            Text(session.selection.count == 1 ? p.spec.panelName : "\(session.selection.count) 个单位")
                                .font(.system(size:11,weight:.bold)).lineLimit(1).fixedSize(horizontal:true,vertical:false)
                            if session.selection.count == 1 {
                                let fraction = max(0,min(1,p.hp/Double(p.spec.stats.hp)))
                                HStack(spacing:1) {
                                    ForEach(0..<6,id:\.self) { i in
                                        Rectangle().fill(Double(i) < fraction*6 ? (fraction < 0.35 ? Palette.warning : Palette.phosphor) : .white.opacity(0.22))
                                            .frame(width:5,height:2)
                                    }
                                }
                            }
                        }
                    }
                } else { Image(systemName:"command"); if !compact { Text("指令").font(.caption.bold()) } }
                Image(systemName:"chevron.down").font(.system(size:8,weight:.bold)).foregroundStyle(Palette.brass)
            }.padding(.horizontal,8).frame(minWidth:44,minHeight:44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("单位指令").accessibilityIdentifier("unitOrders")
            .accessibilityValue(session.selection.count > 1 ? "\(session.selection.count) 个单位" : (session.selected?.spec.name ?? "未选单位"))
    }

    private var productionKey: some View {
        let player = game.players[0], lane = player.indicatedLane(current:session.lane)
        let canPlace = lane.flatMap {player.readyBuilding(in:$0)} != nil
        return Button {
            if let lane, canPlace || player.queues[session.lane]?.isEmpty != false {session.lane = lane}
            show(.production)
        } label: {
            HStack(spacing:6) {
                Image(systemName:"wrench.and.screwdriver.fill").font(.system(size:13,weight:.bold))
                Text(canPlace ? "待部署" : "生产").font(.system(size:13,weight:.heavy))
                Image(systemName:"chevron.up").font(.system(size:9,weight:.bold))
            }.padding(.horizontal,9).frame(height:33).foregroundStyle(canPlace ? Palette.phosphor : Palette.amber)
                .background(SteelPlate(cut:8))
                .overlay(ArmorOutline(cut:8).strokeBorder((canPlace ? Palette.phosphor : Palette.brass).opacity(0.85)))
                .frame(minHeight:44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("打开生产栏").accessibilityIdentifier("showProduction")
            .accessibilityValue(canPlace ? "建筑已就绪" : (lane == nil ? "空闲" : "生产中"))
    }

    private var targetingDock: some View {
        let spec = session.placementBlueprint
        let valid = spec.flatMap { b in session.site.map { game.placement(b,owner:0,origin:$0) } } ?? false
        return HStack(spacing:6) {
            if let spec {
                ArtImage(name:spec.id).scaledToFit().frame(width:34,height:28)
                Text(spec.panelName).font(.system(size:12,weight:.bold))
                SignalLamp(color:valid ? Palette.phosphor : Palette.warning)
                Text(session.site == nil ? "点地面选址" : (valid ? "可放置" : "位置受阻"))
                    .font(.system(size:10,weight:.semibold)).foregroundStyle(valid ? Palette.phosphor : Palette.warning)
            } else if let kind = session.support {
                Label(kind.panelName,systemImage:"scope").font(.subheadline.bold())
            }
            Button {session.cancelTarget()} label:{Text("取消").font(.caption.bold()).frame(minWidth:44,minHeight:44).contentShape(Rectangle())}
                .buttonStyle(.plain)
            if spec != nil {
                Button {session.confirmPlacement()} label:{Label("确认放置",systemImage:"checkmark")}
                    .buttonStyle(PanelButton(primary:true)).disabled(!valid).opacity(valid ? 1 : 0.55).accessibilityLabel("确认放置")
            }
        }.padding(.leading,9).padding(.trailing,4).background {SteelPlate(cut:9).padding(.vertical,2)}
    }
}
