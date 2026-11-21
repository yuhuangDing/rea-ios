import Foundation

enum Intent: String, Codable { case idle, move, advance, attack, harvest, unload, engineer }
enum Outcome: String, Codable { case playing, won, lost, practiceEnded }
enum Support: String, Codable { case airborne, storm, missile }

final class Piece: Codable, Identifiable {
    let id: Int
    var type: String, owner: Int, pos: Point, hp: Double
    var direction = 0.85, cooldown = 0.0, nextRoute = 0.0, workClock = 0.0
    var intent: Intent = .idle, target: Int?, goal: Point?, lastContact: Point?, path: [Cell] = [], waypoint = 0
    var cargo = 0, repairing = false, entrenched = false
    var spec: Blueprint { Catalog.byID[type]! }
    var origin: Cell {
        let r = Double(spec.footprint)/2
        return Cell(Int((pos.x-r).rounded()), Int((pos.y-r).rounded()))
    }
    init(_ id: Int, _ type: String, _ owner: Int, _ pos: Point) {
        self.id = id; self.type = type; self.owner = owner; self.pos = pos
        hp = Double(Catalog.byID[type]!.stats.hp)
    }
    func stop() { intent = .idle; target = nil; goal = nil; lastContact = nil; path = []; waypoint = 0; nextRoute = 0 }
}
struct Job: Codable, Equatable {
    let type: String
    var remaining: Double
    private(set) var paid: Int
    var ready: Bool { remaining <= 0 }

    init(_ blueprint: Blueprint) {
        type = blueprint.id; remaining = blueprint.duration; paid = 0
    }

    private enum CodingKeys: String, CodingKey { case type, remaining, paid }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy:CodingKeys.self)
        type = try values.decode(String.self,forKey:.type)
        remaining = try values.decode(Double.self,forKey:.remaining)
        guard let b = Catalog.byID[type], remaining.isFinite, (0...b.duration).contains(remaining) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // Before progressive billing, even untouched copies were paid in full when ordered.
        paid = try values.decodeIfPresent(Int.self,forKey:.paid) ?? b.stats.cost
        guard (0...b.stats.cost).contains(paid), remaining + 1e-9 >= unfundedTime(b) else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    func fraction(of b: Blueprint) -> Double { min(1, max(0, 1 - remaining / b.duration)) }

    private func unfundedTime(_ b: Blueprint) -> Double {
        b.stats.cost == 0 ? 0 : b.duration * Double(b.stats.cost - paid) / Double(b.stats.cost)
    }

    func waitingForFunds(_ b: Blueprint, credits: Int) -> Bool {
        !ready && credits == 0 && paid < b.stats.cost && remaining <= unfundedTime(b) + 1e-9
    }

    mutating func advance(_ b: Blueprint, work: Double, credits: inout Int) {
        let target = max(0, remaining - work)
        let cost = b.stats.cost
        // Round cumulative cost, not each tick. Splitting a tick never charges an extra coin.
        let due = target == 0 ? cost : Int(ceil((b.duration - target) / b.duration * Double(cost) - 1e-9))
        let charge = min(credits, max(0, due - paid))
        credits -= charge; paid += charge
        remaining = max(target, unfundedTime(b))
    }
}

struct ProductWork: Equatable {
    let pending: Int
    let active: Job?
}

final class Commander: Codable {
    let nation: Nation
    // Keep the saved order lists grouped by catalogue tab. Each model consumes its own production time.
    var credits: Int, eliminated = false, queues: [Lane:[Job]] = [:], kills = 0, mined = 0
    // When a deposit runs out, the next deposit starts with the next model.
    var lastFundedType: String?
    var nextThink = 0.0, nextWave: Double, airReady = 65.0, superReady = 150.0
    init(_ nation: Nation, _ cash: Int, _ wave: Double) {
        self.nation = nation; credits = cash; nextWave = wave
    }
    func work(for b: Blueprint) -> ProductWork {
        let orders = queues[b.lane] ?? []
        let pending = orders.lazy.filter { $0.type == b.id && !$0.ready }.count
        return ProductWork(pending:pending,active:orders.first { $0.type == b.id })
    }
    func readyBuilding(in lane: Lane) -> Job? {
        queues[lane]?.first { $0.ready && Catalog.byID[$0.type]?.isBuilding == true }
    }
    var unfinishedCount: Int {
        queues.values.reduce(0) { $0 + $1.lazy.filter { !$0.ready }.count }
    }
}
struct Flash: Identifiable {
    var id: Int, from: Point, to: Point, style: String, until: Double
}

final class Battle: Codable {
    static let step = 0.125
    let version: Int, settings: MatchSettings
    var isPractice: Bool { players.count == 1 }
    var map: Battlefield, players: [Commander], pieces: [Int:Piece] = [:]
    var time = 0.0, outcome: Outcome = .playing, nextID = 1, random: RandomStream
    var explored: [UInt8]
    var occupied: [Int:Int] = [:], visible = [UInt8](), flash: [Flash] = [], revision = 0
    var timeForVision = 0.0, flashID = 0
    // The HUD interpolates between confirmed steps, including the final step before funds run out.
    var previousProductionFractions: [String:Double] = [:]
    var nearby: [Int:[Int]] = [:]
    enum CodingKeys: String, CodingKey {
        case version, settings, map, players, pieces, time, outcome, nextID, random, explored
    }
    init(_ proposed: MatchSettings) {
        var setup = proposed
        setup.opponents = Array(setup.opponents.prefix(MatchSettings.maxPlayers-1))
        setup.credits = min(30000,max(5000,setup.credits))
        version = 1; settings = setup; random = RandomStream(state: setup.seed)
        let countries = [setup.nation] + setup.opponents
        map = Battlefield(settings: setup,count: countries.count)
        players = countries.enumerated().map { i,n in Commander(n,setup.credits,setup.difficulty.wavePeriod + Double(i)*1.4) }
        explored = Array(repeating: 0,count: Battlefield.size*Battlefield.size)
        for (i,n) in countries.enumerated() {
            let start = map.seats[i]
            _ = spawn(Catalog.id(.mcv,n), i, start)
            for (x,y) in [(-2.4,1.8),(2.2,1.8)] { _ = spawn(Catalog.id(.tank,n),i,start.offset(x,y)) }
            for (x,y) in [(-1.8,-2.4),(0.0,-2.6),(1.8,-2.4)] { _ = spawn(Catalog.id(.soldier,n),i,start.offset(x,y)) }
        }
        refreshVision()
    }
    static func restore(_ data: Data) throws -> Battle {
        let b = try JSONDecoder().decode(Battle.self,from: data)
        let cells = Battlefield.size * Battlefield.size
        guard b.version == 1, (1...MatchSettings.maxPlayers).contains(b.players.count),
              b.settings.playerCount == b.players.count, b.map.theater == b.settings.theater, b.map.tiles.count == cells,
              b.map.ore.count == cells, b.map.seats.count == b.players.count, b.explored.count == cells,
              b.pieces.allSatisfy({ key, p in key == p.id && Catalog.byID[p.type] != nil && b.players.indices.contains(p.owner) && Battlefield.inside(p.pos.cell) }),
              b.players.allSatisfy({ player in
                  player.credits >= 0 && player.queues.allSatisfy { lane, jobs in
                      jobs.allSatisfy { Catalog.byID[$0.type]?.lane == lane }
                  }
              })
        else { throw CocoaError(.fileReadCorruptFile) }
        guard b.map.seats.allSatisfy({ Battlefield.inside($0.cell) }),
              b.map.ore.allSatisfy({ $0 >= 0 }),
              b.map.gems.allSatisfy({ b.map.ore.indices.contains($0) && b.map.ore[$0] > 0 }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        b.rebuildOccupancy()
        if b.map.oreMines.isEmpty {
            let mobile = b.pieces.values.filter { !$0.spec.isBuilding && !$0.spec.flies }.map { Battlefield.index($0.pos.cell) }
            b.map.installOreMines(avoiding:Set(b.occupied.keys).union(mobile))
        }
        guard b.map.oreMines.allSatisfy({ i in
            b.map.ore.indices.contains(i) && b.map.ore[i] == 0 && b.map.tiles[i].isLand && b.occupied[i] == nil
        }) else { throw CocoaError(.fileReadCorruptFile) }
        b.refreshVision(); b.reindex()
        return b
    }
    @discardableResult func spawn(_ type: String, _ owner: Int, _ pos: Point) -> Piece {
        let p = Piece(nextID,type,owner,pos); nextID += 1; pieces[p.id] = p
        if p.spec.isBuilding { mark(p) }; return p
    }
    func owned(_ owner: Int, _ role: Role? = nil) -> [Piece] {
        pieces.values.filter { $0.owner == owner && $0.hp > 0 && (role == nil || $0.spec.role == role) }.sorted { $0.id < $1.id }
    }
    func mark(_ p: Piece) {
        for c in Battlefield.footprint(p.origin,size:p.spec.footprint) where Battlefield.inside(c) {
            occupied[Battlefield.index(c)] = p.id
        }
    }
    func rebuildOccupancy() {
        occupied.removeAll(keepingCapacity: true)
        for p in pieces.values where p.spec.isBuilding && p.hp > 0 { mark(p) }
    }
    func energy(_ owner: Int) -> (made: Int, used: Int) {
        var produced = 0, consumed = 0
        for p in pieces.values where p.owner == owner && p.hp > 0 && p.spec.isBuilding {
            let v = p.spec.stats.power; if v > 0 { produced += v } else { consumed -= v }
        }
        return (produced,consumed)
    }
    func hasPower(_ owner: Int) -> Bool { let e = energy(owner); return e.made >= e.used }
    func productionRate(_ owner: Int) -> Double { hasPower(owner) ? 1 : 0.35 }
    func radarOnline(_ owner: Int) -> Bool { !owned(owner,.radar).isEmpty && hasPower(owner) }
    func missing(_ b: Blueprint, owner: Int) -> [Role] {
        let roles = Set(owned(owner).map { $0.spec.role })
        return b.requires.filter { !roles.contains($0) }
    }
    func reason(_ b: Blueprint, owner: Int) -> String? {
        let player = players[owner]
        if b.role == .yard || !Catalog.options(player.nation,b.lane).contains(where: { $0.id == b.id }) { return "该国无法生产" }
        if let role = missing(b,owner: owner).first {
            return "需要" + Catalog.byID[Catalog.id(role,player.nation)]!.name
        }
        if b.role == .dock && !settings.theater.allowsShipyards { return "需要可建船坞的海战地图" }
        return nil
    }
    @discardableResult func enqueue(_ type: String, owner: Int) -> Bool {
        guard outcome == .playing, players.indices.contains(owner), !players[owner].eliminated,
              let b = Catalog.byID[type], reason(b,owner:owner) == nil else { return false }
        players[owner].queues[b.lane,default:[]].append(Job(b))
        return true
    }
    @discardableResult func cancelProduction(_ type: String, owner: Int, current: Bool = false) -> Int? {
        guard outcome == .playing, players.indices.contains(owner), let b = Catalog.byID[type] else { return nil }
        let player = players[owner]
        guard let orders = player.queues[b.lane] else { return nil }
        let matches: (Job) -> Bool = { $0.type == type }
        guard let index = current ? orders.firstIndex(where:matches) : orders.lastIndex(where:matches) else { return nil }
        let refund = orders[index].paid
        player.queues[b.lane]?.remove(at:index)
        player.credits += refund
        if owner == 0 && index == orders.firstIndex(where:matches) { previousProductionFractions[type] = nil }
        return refund
    }
    func placement(_ b: Blueprint, owner: Int, origin: Cell, deploying: Bool = false) -> Bool {
        let area = Battlefield.footprint(origin,size:b.footprint)
        guard area.allSatisfy({ cell in
            let index = Battlefield.index(cell)
            return Battlefield.inside(cell) && map.tile(cell) != .ridge && occupied[index] == nil &&
                map.ore[index] == 0 && !map.oreMines.contains(index)
        }) else { return false }
        if b.role == .dock {
            guard settings.theater.allowsShipyards else { return false }
            let wet = area.filter { map.tile($0) == .water }.count
            guard wet > 0, (wet < area.count || area.contains { c in Self.directions.contains { map.tile(Cell(c.x+$0.x,c.y+$0.y)).isLand } }) else { return false }
        } else if area.contains(where: { map.tile($0) == .water }) { return false }
        if pieces.values.contains(where: { $0.owner != owner && $0.hp > 0 && !$0.spec.flies && area.contains($0.pos.cell) }) { return false }
        if deploying { return true }
        let mid = Point(Double(origin.x)+Double(b.footprint)/2,Double(origin.y)+Double(b.footprint)/2)
        if owner == 0 && settings.fog && !isVisible(mid) { return false }
        return owned(owner).contains { $0.spec.isBuilding && $0.pos.distance(mid) <= 8.2 }
    }
    @discardableResult func deploy(_ id: Int) -> Bool {
        guard let p = pieces[id], p.spec.role == .mcv, outcome == .playing else { return false }
        let yard = Catalog.byID[Catalog.id(.yard,players[p.owner].nation)]!
        let origin = Cell(p.pos.cell.x-1,p.pos.cell.y-1)
        guard placement(yard,owner:p.owner,origin:origin,deploying:true) else { return false }
        p.type = yard.id; p.pos = origin.center.offset(1,1); p.stop(); mark(p)
        clearFootprint(p); refreshVision()
        return true
    }
    func clearFootprint(_ building: Piece) {
        for mobile in owned(building.owner) where !mobile.spec.isBuilding && !mobile.spec.flies && occupied[Battlefield.index(mobile.pos.cell)] == building.id {
            if let free = nearestOpen(mobile.pos.cell, for: mobile.spec, excluding: nil) {
                mobile.pos = free.center; mobile.stop()
            }
        }
    }
    @discardableResult func place(_ type: String, owner: Int, origin: Cell) -> Bool {
        guard outcome == .playing, players.indices.contains(owner), let b = Catalog.byID[type], b.isBuilding,
              let index = players[owner].queues[b.lane]?.firstIndex(where:{ $0.type == type && $0.ready }),
              !owned(owner,.yard).isEmpty, placement(b,owner:owner,origin:origin) else { return false }
        let r = Double(b.footprint)/2
        let built = spawn(b.id,owner,Point(Double(origin.x)+r,Double(origin.y)+r))
        players[owner].queues[b.lane]?.remove(at:index); clearFootprint(built)
        if b.role == .refinery { _ = launch(Catalog.byID[Catalog.id(.miner,players[owner].nation)]!, producer:built) }
        if b.role == .strategic { players[owner].superReady = max(players[owner].superReady,time+130) }
        if b.role == .radar && players[owner].nation == .usa { players[owner].airReady = max(players[owner].airReady,time+45) }
        refreshVision(); return true
    }
    @discardableResult func launch(_ b: Blueprint, producer: Piece) -> Piece? {
        let exit = producer.pos.offset(Double(producer.spec.footprint)/2+0.6, 0.5).cell
        let occupiedExits = Set(pieces.values.lazy.filter {
            $0.hp > 0 && !$0.spec.isBuilding && $0.spec.flies == b.flies
        }.map { $0.pos.cell })
        guard let c = nearestOpen(exit,for:b,excluding:nil,avoiding:occupiedExits) else { return nil }
        return spawn(b.id,producer.owner,c.center)
    }

    func processJobs(_ owner: Int, dt: Double) {
        let player = players[owner]
        guard dt > 0, player.queues.values.contains(where:{ !$0.isEmpty }) else { return }
        let buildings = owned(owner).filter { $0.spec.isBuilding }
        let roles = Set(buildings.map { $0.spec.role })
        let elapsedWork = dt * productionRate(owner)

        // Indices keep repeat orders in booking order, even when other models run between them.
        var indicesByType = [String:[Int]]()
        for orders in player.queues.values {
            for (index,job) in orders.enumerated() { indicesByType[job.type,default:[]].append(index) }
        }
        let types = indicesByType.keys.sorted()
        let start = player.lastFundedType.flatMap { last in types.firstIndex { $0 > last } } ?? 0
        var launched = [Lane:IndexSet]()
        if owner == 0 { previousProductionFractions.removeAll(keepingCapacity:true) }
        for offset in types.indices {
            let id = types[(start+offset) % types.count]
            guard let b = Catalog.byID[id], b.requires.allSatisfy(roles.contains),
                  let indices = indicesByType[id] else { continue }
            var work = elapsedWork
            for index in indices {
                guard work > 0, var job = player.queues[b.lane]?[index] else { break }
                let before = job.remaining, cash = player.credits
                if owner == 0 { previousProductionFractions[id] = job.fraction(of:b) }
                job.advance(b,work:work,credits:&player.credits)
                player.queues[b.lane]?[index] = job
                if cash > 0 && player.credits == 0 { player.lastFundedType = id }
                guard job.ready, !b.isBuilding else { break }
                let producer: Role
                switch b.lane {
                case .infantry: producer = .barracks
                case .naval: producer = .dock
                case .air: producer = b.id == "ZEP" ? .factory : .radar
                default: producer = .factory
                }
                guard let factory = buildings.first(where:{ $0.spec.role == producer }),
                      launch(b,producer:factory) != nil else { break }
                launched[b.lane,default:IndexSet()].insert(index)
                work -= before
                if owner == 0 { previousProductionFractions[id] = nil }
            }
        }
        for (lane,indices) in launched {
            for range in indices.rangeView.reversed() { player.queues[lane]?.removeSubrange(range) }
        }
    }
    func isVisible(_ pos: Point) -> Bool {
        guard Battlefield.inside(pos.cell) else { return false }
        return !settings.fog || visible[Battlefield.index(pos.cell)] > 0
    }
    func sighted(_ spot: Point, by owner: Int) -> Bool {
        if !settings.fog { return true }
        if owner == 0 { return isVisible(spot) }
        return pieces.values.contains { p in
            guard p.owner == owner, p.hp > 0 else { return false }
            let r = max(p.spec.stats.sight,p.spec.role == .yard ? 8 : 4)
            let dx = p.pos.cell.x-spot.cell.x, dy = p.pos.cell.y-spot.cell.y
            return dx*dx+dy*dy <= r*r
        }
    }
    func refreshVision() {
        let n = Battlefield.size
        visible = [UInt8](repeating: settings.fog ? 0 : 1,count:n*n)
        if settings.fog {
            for p in owned(0) {
                let c = p.pos.cell, r = max(p.spec.stats.sight, p.spec.role == .yard ? 8 : 4)
                for y in max(0,c.y-r)...min(n-1,c.y+r) {
                    for x in max(0,c.x-r)...min(n-1,c.x+r) where (x-c.x)*(x-c.x)+(y-c.y)*(y-c.y) <= r*r {
                        visible[y*n+x] = 1
                    }
                }
            }
        }
        for i in visible.indices where visible[i] != 0 { explored[i] = 1 }; revision += 1
    }
    func effect(_ a: Point, _ b: Point, _ style: String) {
        flashID += 1; flash.append(Flash(id:flashID,from:a,to:b,style:style,until:time+0.35))
    }
    func retire(_ p: Piece, defeatedBy owner: Int? = nil) {
        guard pieces.removeValue(forKey:p.id) != nil else { return }
        if p.spec.isBuilding { rebuildOccupancy() }
        if let owner, owner != p.owner { players[owner].kills += 1 }
        effect(p.pos,p.pos,"burst")
    }
    func sell(_ id: Int, owner: Int) -> Bool {
        guard let p = pieces[id], p.owner == owner, p.spec.isBuilding, outcome == .playing else { return false }
        players[owner].credits += Int(Double(p.spec.stats.cost) * 0.5 * max(0,p.hp)/Double(p.spec.stats.hp))
        retire(p); checkOutcome(); return true
    }
    func checkOutcome() {
        for i in players.indices where !players[i].eliminated {
            if !owned(i).contains(where: { $0.spec.isBuilding || $0.spec.role == .mcv }) {
                players[i].eliminated = true; players[i].queues.removeAll()
                for p in owned(i) { retire(p) }
            }
        }
        if players[0].eliminated { outcome = isPractice ? .practiceEnded : .lost }
        else if !isPractice && players.dropFirst().allSatisfy(\.eliminated) { outcome = .won }
    }
}
