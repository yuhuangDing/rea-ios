import SwiftUI

final class GameSession: ObservableObject {
    @Published var game: Battle?
    @Published var setup: MatchSettings
    @Published var paused = false
    @Published var boxSelect = false
    @Published var advance = false
    @Published var hasSave = false
    @Published var selection = [Int]()
    @Published var lane: Lane = .construction
    @Published var epoch = 0
    @Published var placementBlueprint: Blueprint?
    @Published var site: Cell?
    @Published var support: Support?
    @Published var notice = ""
    @Published var setupMessage = ""
    @Published var sound: Bool { didSet { UserDefaults.standard.set(sound,forKey:"sound"); GameAudio.shared.enabled = sound } }
    weak var scene: BattleScene?
    private var nextSave = 15.0, nextHUD = 0.0, noticeUntil = 0.0
    private var groups = [Int]()
    private let saveURL: URL
    init() {
        let folder = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
        saveURL = folder.appendingPathComponent("IronFront/Skirmish-v1.json")
        var saved = UserDefaults.standard.data(forKey:"match-settings").flatMap { try? JSONDecoder().decode(MatchSettings.self,from:$0) } ?? MatchSettings()
        saved.opponents = Array(saved.opponents.prefix(MatchSettings.maxPlayers-1)); setup = saved
        sound = UserDefaults.standard.object(forKey:"sound") as? Bool ?? true
        GameAudio.shared.enabled = sound
        hasSave = FileManager.default.fileExists(atPath:saveURL.path)
    }
    func start() {
        setup.seed = UInt64.random(in:1...UInt64(Int32.max))
        UserDefaults.standard.set(try? JSONEncoder().encode(setup),forKey:"match-settings")
        enter(Battle(setup)); _ = save()
    }
    private func enter(_ b: Battle) {
        game = b; paused = false; boxSelect = false; advance = false; lane = .construction; groups = []
        site = nil; placementBlueprint = nil; support = nil; setupMessage = ""
        selection = b.owned(0,.mcv).prefix(1).map(\.id); notice = ""
        nextHUD = b.time; nextSave = b.time+15
        if !selection.isEmpty { say("基地车已就位，点「展开基地」开始建设") }
    }
    func resumeSave() {
        do { let battle = try Battle.restore(Data(contentsOf:saveURL)); enter(battle) }
        catch { setupMessage = "存档无法读取，可开始新对战。"; hasSave = false }
    }
    @discardableResult func save() -> Bool {
        guard let game, game.outcome == .playing else { return false }
        do {
            try FileManager.default.createDirectory(at:saveURL.deletingLastPathComponent(),withIntermediateDirectories:true)
            try JSONEncoder().encode(game).write(to:saveURL,options:.atomic); hasSave = true; return true
        } catch { say("存档写入失败：\(error.localizedDescription)"); return false }
    }
    func leave() {
        if game?.outcome == .playing && !save() { return }
        if game?.outcome != .playing { clearSave() }
        game = nil; paused = false; scene = nil
    }
    private func clearSave() {
        if FileManager.default.fileExists(atPath:saveURL.path) { try? FileManager.default.removeItem(at:saveURL) }
        hasSave = false
    }
    func step() {
        guard let game, game.outcome == .playing, !paused else { return }
        let previousCount = game.players[0].unfinishedCount
        let hadFunds = game.players[0].credits > 0
        game.tick()
        if game.outcome != .playing { epoch += 1; clearSave(); GameAudio.shared.play("complete"); return }
        if game.time >= nextHUD || game.players[0].unfinishedCount != previousCount || hadFunds != (game.players[0].credits > 0) {
            nextHUD = game.time+0.35
            let clean = selection.filter { game.pieces[$0]?.owner == 0 }
            if clean != selection { selection = clean }
            if !notice.isEmpty && game.time > noticeUntil { notice = "" }
            epoch += 1
        }
        if game.time >= nextSave { nextSave = game.time+15; _ = save() }
    }
    func background() {
        if let game {
            if game.outcome == .playing { paused = true; _ = save() } else { clearSave() }
        }
    }
    func say(_ text: String) { notice = text; noticeUntil = (game?.time ?? 0)+4.8 }
    func select(_ ids: [Int]) {
        selection = ids.sorted(); advance = false; cancelTarget(); GameAudio.shared.play("select")
    }
    var selected: Piece? { selection.first.flatMap { game?.pieces[$0] } }
    func cancelTarget() { placementBlueprint = nil; support = nil; site = nil }
    func product(_ b: Blueprint, addCopy: Bool = false) {
        guard let g = game else { return }
        if !addCopy, b.isBuilding, g.players[0].work(for:b).active?.ready == true {
            guard !g.owned(0,.yard).isEmpty else { say("需要建造厂才能放置建筑"); return }
            placementBlueprint = b; support = nil; boxSelect = false
            site = g.buildSite(b,owner:0)
            if let site { scene?.focus(site.center) }
            say("点地面调整建筑位置，再确认放置"); return
        }
        if let reason = g.reason(b,owner:0) { say(reason); return }
        if g.enqueue(b.id,owner:0) { GameAudio.shared.play("order"); epoch += 1 }
    }
    func cancelProduct(_ b: Blueprint, current: Bool = false) {
        guard let g = game, let refund = g.cancelProduction(b.id,owner:0,current:current) else { return }
        if placementBlueprint?.id == b.id && g.players[0].work(for:b).active?.ready != true { cancelTarget() }
        let message = "已取消 1 件\(b.panelName)"
        say(refund > 0 ? message + "，返还 $\(String(refund))" : message)
        GameAudio.shared.play("select"); epoch += 1
    }
    func confirmPlacement() {
        guard let g = game, let b = placementBlueprint, let site else { say("点地面选择位置"); return }
        if g.place(b.id,owner:0,origin:site) {
            cancelTarget(); epoch += 1; say("建筑就绪"); GameAudio.shared.play("complete")
        } else { say("此处无法建造，请选择基地附近的空地") }
    }
    func deploy() {
        guard let g = game, let p = selected else { return }
        if g.deploy(p.id) { GameAudio.shared.play("complete"); say("建造厂就绪，可以建造发电厂"); epoch += 1 }
        else { say("周围空间不足，移动基地车后再展开") }
    }
    func selectArmy() {
        guard let g = game else { return }
        select(g.owned(0).filter { !$0.spec.isBuilding && $0.spec.weapon != nil && $0.spec.role != .miner }.map(\.id))
        say("已选择 \(selection.count) 个作战单位")
    }
    func group(record: Bool) {
        guard let g = game else { return }
        if record {
            groups = selection.filter { g.pieces[$0]?.spec.isBuilding == false }
            say("已编入 \(groups.count) 个单位")
        } else {
            let live = groups.filter { g.pieces[$0]?.owner == 0 }
            guard !live.isEmpty else { say("编队为空"); return }
            select(live); if let p = selected { scene?.focus(p.pos) }
        }
    }
    func surrender() {
        guard let game else { return }
        game.outcome = game.isPractice ? .practiceEnded : .lost
        paused = false; clearSave(); epoch += 1
        GameAudio.shared.play("complete")
    }
    func tap(_ point: Point, hit: Int?, double: Bool = false) {
        guard let g = game, !paused, g.outcome == .playing, Battlefield.inside(point.cell) else { return }
        if let b = placementBlueprint {
            let offset = (b.footprint-1)/2
            site = Cell(point.cell.x-offset,point.cell.y-offset); return
        }
        if let support {
            if g.useSupport(support,owner:0,at:point) { cancelTarget(); say("支援已抵达"); GameAudio.shared.play("complete") }
            else { say("请选择可见的有效目标") }; return
        }
        let unit = hit.flatMap { g.pieces[$0] }
        if let p = unit, p.owner == 0 {
            if selection.count == 1, selected?.spec.role == .engineer, p.spec.isBuilding && p.hp < Double(p.spec.stats.hp) {
                g.order(selection,owner:0,to:p.pos,target:p.id); say("工程师前往维修"); return
            }
            if double && !p.spec.isBuilding { select(g.owned(0).filter { $0.type == p.type && $0.pos.distance(p.pos) < 12 }.map(\.id)) }
            else { select([p.id]) }
        } else if selection.contains(where:{ g.pieces[$0]?.spec.isBuilding == false }) {
            g.order(selection,owner:0,to:point,target:hit,advance:advance)
            advance = false
            scene?.ping(point,hostile:unit != nil); GameAudio.shared.play("order")
        } else if unit == nil { select([]) }
    }
    func centerBase() {
        guard let g = game else { return }
        scene?.focus(g.owned(0,.yard).first?.pos ?? g.owned(0,.mcv).first?.pos ?? g.map.seats[0])
    }
}
