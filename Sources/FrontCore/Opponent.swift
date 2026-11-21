import Foundation

extension Battle {
    func buildSite(_ b: Blueprint, owner: Int) -> Cell? {
        let bases = owned(owner).filter(\.spec.isBuilding)
        guard !bases.isEmpty else { return nil }
        let anchor = bases.first(where: { $0.spec.role == .yard })?.pos ?? bases[0].pos
        let center = Point(Double(Battlefield.size)/2,Double(Battlefield.size)/2)
        let front = Point((center.x-anchor.x)/18,(center.y-anchor.y)/18)
        let aim = b.lane == .defense ? anchor.offset(front.x*5,front.y*5) : anchor
        var choices: [(Cell,Double)] = []
        for base in bases {
            for dy in -7...7 { for dx in -7...7 {
                let c = Cell(base.pos.cell.x+dx,base.pos.cell.y+dy)
                let middle = c.center.offset(Double(b.footprint-1)/2,Double(b.footprint-1)/2)
                if middle.distance(base.pos) <= 8 && Battlefield.inside(c) {
                    let jitter = Double(abs((c.x*37+c.y*23+owner*17)%19))/40
                    choices.append((c,middle.distance(aim)+jitter))
                }
            }}
        }
        var checked = Set<Cell>()
        for (c,_) in choices.sorted(by: { $0.1 < $1.1 }) where checked.insert(c).inserted {
            guard placement(b,owner:owner,origin:c) else { continue }
            // Keep a one-cell alley between buildings so newly launched units can leave.
            let cells = Battlefield.footprint(Cell(c.x-1,c.y-1),size:b.footprint+2)
            if cells.allSatisfy({ !Battlefield.inside($0) || occupied[Battlefield.index($0)] == nil }) { return c }
        }
        return nil
    }
    func think(_ i: Int) {
        let player = players[i], nation = player.nation
        let initial = owned(i)
        if !initial.contains(where: { $0.spec.role == .yard }), let mcv = initial.first(where: { $0.spec.role == .mcv }) {
            _ = deploy(mcv.id); return
        }
        for lane in [Lane.construction,.defense] {
            for job in player.queues[lane] ?? [] where job.ready {
                if let b = Catalog.byID[job.type], let c = buildSite(b,owner:i) { _ = place(b.id,owner:i,origin:c) }
            }
        }
        let own = owned(i), roles = Set(own.map(\.spec.role))
        let committed = player.queues.values.joined().reduce(0) { sum, job in
            sum + (Catalog.byID[job.type]!.stats.cost - job.paid)
        }
        var available = player.credits - committed
        func plan(_ id: String) {
            guard let b = Catalog.byID[id], b.stats.cost <= available, enqueue(id,owner:i) else { return }
            available -= b.stats.cost
        }
        let energy = energy(i)
        let infrastructure: [Role] = [.power,.refinery,.barracks,.factory,.radar,.lab]
        if player.queues[.construction,default:[]].isEmpty && roles.contains(.yard) {
            var wanted = infrastructure.first(where:{ !roles.contains($0) })
            if energy.used > 0 && energy.made-energy.used < 70 { wanted = .power }
            if wanted == nil && !roles.contains(.strategic) && available > 8500 {
                plan(Catalog.id(.strategic,nation))
            }
            if wanted == nil && settings.theater.allowsShipyards && !roles.contains(.dock) && available > 3000 {
                let b = Catalog.byID[Catalog.id(.dock,nation)]!
                if buildSite(b,owner:i) != nil { wanted = .dock }
            }
            if wanted == nil && own.filter({$0.spec.role == .refinery}).count < 2 && available > 4800 { wanted = .refinery }
            if let wanted { plan(Catalog.id(wanted,nation)) }
        }
        if roles.contains(.barracks) && !roles.contains(.turret) && player.queues[.defense,default:[]].isEmpty && available > 1350 {
            plan(Catalog.id(.turret,nation))
        }
        if nation == .france && roles.contains(.radar) && !own.contains(where: { $0.type == "GTGCAN" }) &&
            player.queues[.defense,default:[]].isEmpty && available > 3200 {
            plan("GTGCAN")
        }
        let reserve = roles.contains(.factory) ? 520 : 2600
        if available > reserve, own.filter({ !$0.spec.isBuilding }).count < 31 {
            let miner = Catalog.id(.miner,nation)
            if roles.contains(.factory) && !roles.contains(.miner) && player.queues[.vehicle]?.contains(where:{ $0.type == miner }) != true {
                plan(miner)
            }
            for lane in [Lane.vehicle,.infantry,.air,.naval] where available > reserve {
                let booked = player.queues[lane] ?? []
                let typesInProduction = Set(booked.map(\.type))
                let options = Catalog.options(nation,lane).filter { b in
                    b.weapon != nil && b.role != .miner && b.role != .dog &&
                        b.stats.cost <= available && !typesInProduction.contains(b.id) && reason(b,owner:i) == nil
                }
                guard !options.isEmpty else { continue }
                if lane == .infantry && own.filter({$0.spec.lane == .infantry}).count + booked.count >= 12 { continue }
                let chosen = options[Int(random.next()*Double(options.count))]
                plan(chosen.id)
            }
        }
        for p in own where p.spec.isBuilding && p.hp < Double(p.spec.stats.hp)*0.6 && available > 700 { p.repairing = true }
        guard time >= player.nextWave else { return }
        let rivals = players.indices.filter { $0 != i && !players[$0].eliminated }
        guard let rival = rivals.min(by: { map.seats[i].distance(map.seats[$0]) < map.seats[i].distance(map.seats[$1]) }) else { return }
        let contacts = pieces.values.filter { $0.owner != i && ($0.spec.isBuilding || $0.spec.role == .mcv) && sighted($0.pos,by:i) }
        let enemy = contacts.min { map.seats[i].distance($0.pos) < map.seats[i].distance($1.pos) }
        let destination = enemy?.pos ?? map.seats[rival]
        let units = own.filter { !$0.spec.isBuilding && $0.spec.role != .miner && $0.spec.weapon != nil }
        guard units.count >= 3 || time > 150 else { player.nextWave = time+8; return }
        for p in units {
            if let enemy, canHit(p,enemy) { order([p.id],owner:i,to:destination,target:enemy.id) }
            else { order([p.id],owner:i,to:destination,advance:true) }
        }
        if let enemy {
            for s in [Support.airborne,.storm,.missile] where readySupport(i,s) == 0 { _ = useSupport(s,owner:i,at:enemy.pos) }
        }
        player.nextWave = time + settings.difficulty.wavePeriod * (0.75+random.next()*0.38)
    }
}
