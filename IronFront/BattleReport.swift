import SwiftUI

struct BattleReport: View {
    @ObservedObject var session: GameSession
    let game: Battle
    @State private var help = false
    @State private var surrender = false
    private var playing: Bool { game.outcome == .playing }
    private var title: String {
        switch game.outcome {
        case .playing: return game.isPractice ? "演练暂停" : "对战暂停"
        case .practiceEnded: return "演练结束"
        case .won: return "战斗胜利"
        case .lost: return "战斗失利"
        }
    }

    var body: some View {
        GeometryReader { g in
            let width = min(545,g.size.width-26)
            ZStack {
                Color.black.opacity(0.65).ignoresSafeArea()
                ViewThatFits(in:.vertical) {
                    content(width).fixedSize(horizontal:false,vertical:true)
                    ScrollView {content(width)}
                }.frame(width:width).padding(.vertical,8)
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
        }
        .accessibilityAddTraits(.isModal)
        .confirmationDialog(game.isPractice ? "结束这次演练？" : "确认结束本局并认输？",isPresented:$surrender,titleVisibility:.visible) {
            Button(game.isPractice ? "确认结束演练" : "确认认输",role:.destructive){session.surrender()}; Button("取消",role:.cancel){}
        }
    }
    private func content(_ width: CGFloat) -> some View {
        VStack(alignment:.leading,spacing:8) {
            HStack(spacing:9) {
                FrontInsignia().frame(width:27,height:30)
                Text(title).font(.system(size:25,weight:.black)).tracking(1)
                    .foregroundStyle(game.outcome == .lost ? Palette.warning : Palette.text)
                Spacer(); Text(String(format:"%02d:%02d",Int(game.time)/60,Int(game.time)%60)).font(Palette.mono(15,.bold)).foregroundStyle(Palette.brass)
            }
            Rectangle().fill(Palette.line).frame(height:1)
            HStack(alignment:.center,spacing:14) {
                VStack(alignment:.leading,spacing:5) {
                    MapThumbnail(map:game.map)
                        .frame(height:50).clipShape(ArmorOutline(cut:6))
                    Text(game.settings.theater.rawValue).font(.system(size:15,weight:.heavy))
                    Text("\(game.players[0].nation.flag) \(game.players[0].nation.name) · \(game.isPractice ? "自由演练" : game.settings.difficulty.rawValue)")
                        .font(.caption).foregroundStyle(Palette.muted)
                }.frame(width:min(width*0.31,142),alignment:.leading)
                VStack(alignment:.leading,spacing:0) {
                    if playing {
                        Button {session.paused = false} label:{
                            HStack {Image(systemName:"play.fill"); Text("继续战斗"); Spacer(); Louver()}
                        }.buttonStyle(PanelButton(primary:true))
                        HStack(spacing:6) {
                            Button {help.toggle()} label:{Label("操作说明",systemImage:"hand.tap")}
                                .buttonStyle(PanelButton())
                            Button {session.sound.toggle()} label:{Label(session.sound ? "声音开" : "声音关",systemImage:session.sound ? "speaker.wave.2" : "speaker.slash")}
                                .buttonStyle(PanelButton())
                        }
                        HStack(spacing:5) {
                            Button("保存并返回大厅"){session.leave()}.font(.system(size:12,weight:.semibold)).frame(minHeight:44)
                            Spacer(); Button(game.isPractice ? "结束演练" : "认输"){surrender = true}.font(.system(size:12)).frame(minWidth:44,minHeight:44).foregroundStyle(Palette.warning)
                        }.buttonStyle(.plain)
                    } else {
                        HStack(spacing:15) {
                            statistic("消灭目标",String(game.players[0].kills))
                            statistic("采矿收入","$\(String(game.players[0].mined))")
                        }.padding(.bottom,8)
                        Button {session.leave()} label:{
                            HStack {Text("返回对战大厅"); Spacer(); Image(systemName:"arrow.right")}
                        }.buttonStyle(PanelButton(primary:true))
                    }
                }.frame(maxWidth:.infinity)
            }
            if help && playing {
                Text("拖动战场平移，双指缩放。点己方单位后点地面移动，点敌方攻击，双击选择附近同型单位。左下角可框选或选择全军，点单位铭牌可维修、变卖和编队。右下打开生产栏。点图标或「+」生产，右上是待产数。不同型号同时生产，同型号逐件完成。费用随进度扣除，资金用完时遮罩停住，到账后继续。「−」先减未开工的一件，长按图标取消当前一件，退回已付金额。就绪建筑点图标选址并确认。点右上雷达查看视野。")
                    .font(.caption).foregroundStyle(Palette.muted).fixedSize(horizontal:false,vertical:true)
            }
        }.padding(17).frame(maxWidth:.infinity,alignment:.leading)
            .background(SteelPlate(cut:15,bolted:true)).foregroundStyle(Palette.text)
    }
    private func statistic(_ name: String,_ value: String) -> some View {
        VStack(alignment:.leading,spacing:2) {
            Text(name).font(.caption).foregroundStyle(Palette.muted)
            Text(value).font(Palette.mono(20,.heavy)).foregroundStyle(Palette.amber)
        }
    }
}
