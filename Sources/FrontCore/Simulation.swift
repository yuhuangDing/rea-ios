import Foundation

extension Battle {
    func reindex() {
        nearby.removeAll(keepingCapacity:true)
        for p in pieces.values where p.hp > 0 {
            nearby[(p.pos.cell.y/5)*16 + p.pos.cell.x/5,default:[]].append(p.id)
        }
    }
    func canHit(_ p: Piece, _ victim: Piece) -> Bool {
        guard let w = p.spec.weapon, victim.owner != p.owner, victim.hp > 0 else { return false }
        if p.spec.role == .dog || p.type == "SNIPE" { return victim.spec.lane == .infantry && !victim.spec.flies }
        if p.type == "SUB" { return victim.spec.lane == .naval || victim.spec.role == .dock }
        return victim.spec.flies ? w.air : w.ground
    }
    func acquire(_ p: Piece, radius: Double) -> Piece? {
        let c = p.pos.cell, rad = Int(ceil((radius+2)/5)), x = c.x/5, y = c.y/5
        var best: Piece?, minDist = radius+0.001
        for by in max(0,y-rad)...min(10,y+rad) { for bx in max(0,x-rad)...min(10,x+rad) {
            for id in nearby[by*16+bx] ?? [] {
                guard let enemy = pieces[id], canHit(p,enemy) else { continue }
                let d = edgeDistance(p.pos,enemy)
                if d < minDist || (d == minDist && id < (best?.id ?? .max)) { minDist = d; best = enemy }
            }
        }}
        return best
    }
    func fire(_ p: Piece, _ enemy: Piece, _ w: Weapon) {
        guard p.cooldown <= 0 else { return }
        p.cooldown = w.reload; p.direction = atan2(enemy.pos.y-p.pos.y,enemy.pos.x-p.pos.x)
        let scale = p.entrenched ? 1.6 : 1
        var amount = w.damage*scale
        if p.type == "TNKD" && enemy.spec.lane == .infantry { amount *= 0.22 }
        if p.type == "TNKD" && enemy.spec.lane == .vehicle { amount *= 1.45 }
        effect(p.pos,enemy.pos,w.color); hit(enemy,amount,by:p.owner)
        if w.splash > 0 {
            for other in Array(pieces.values) where other.id != enemy.id && other.owner != p.owner && other.hp > 0 &&
                other.pos.distance(enemy.pos) <= w.splash && (w.air || !other.spec.flies) { hit(other,w.damage*0.53,by:p.owner) }
        }
        if w.suicide { retire(p) }
    }
    func hit(_ piece: Piece, _ damage: Double, by owner: Int) {
        piece.hp -= damage
        if piece.hp <= 0 { retire(piece,defeatedBy:owner) }
    }
    func mine(_ p: Piece, dt: Double) {
        let capacity = p.type == "CMIN" ? 340 : 520
        if p.cargo >= capacity || p.intent == .unload {
            if p.intent != .unload { p.stop(); p.intent = .unload }
            let refineries = owned(p.owner,.refinery)
            guard !refineries.isEmpty else { p.goal = nil; return }
            func canUnload(at pos: Point) -> Bool { refineries.contains { edgeDistance(pos,$0) <= 1.25 } }

            if !canUnload(at:p.pos) {
                if p.type == "CMIN" {
                    guard let dock = refineries.sorted(by:{ p.pos.distance($0.pos) < p.pos.distance($1.pos) })
                        .lazy.map({ self.approach(p,$0) }).first(where:{ self.passable($0.cell,for:p.spec) })
                    else { return }
                    p.pos = dock
                } else {
                    if let dock = p.goal, canUnload(at:dock), passable(dock.cell,for:p.spec) {
                        if !walk(p,toward:dock,dt:dt) || canUnload(at:p.pos) { return }
                    }
                    guard time >= p.workClock else { return }
                    guard let dock = nearestMiningCell(from:p.pos.cell,for:p.spec,matching:{
                        canUnload(at:Battlefield.cell($0).center)
                    }) else { p.goal = nil; p.workClock = time+2; return }
                    p.goal = nil; _ = walk(p,toward:dock.center,dt:dt); return
                }
            }
            players[p.owner].credits += p.cargo; players[p.owner].mined += p.cargo
            p.cargo = 0; p.stop()
            return
        }

        if p.intent == .harvest, let i = p.target, map.ore.indices.contains(i), map.ore[i] > 0 {
            let cell = Battlefield.cell(i)
            if passable(cell,for:p.spec) {
                if p.pos.distance(cell.center) <= 0.8 {
                    let load = min(map.ore[i],capacity-p.cargo,Int(ceil(72*dt)))
                    map.ore[i] -= load; p.cargo += load
                    if map.ore[i] == 0 {
                        map.gems.remove(i); revision += 1; p.stop()
                        if p.cargo > 0 { p.intent = .unload }
                    }
                    return
                }
                if !walk(p,toward:cell.center,dt:dt) || p.pos.distance(cell.center) <= 0.8 { return }
            }
        }
        guard time >= p.workClock else { return }
        p.stop()
        if map.ore.contains(where:{ $0 > 0 }),
           let next = nearestMiningCell(from:p.pos.cell,for:p.spec,matching:{ map.ore[$0] > 0 }) {
            p.intent = .harvest; p.target = Battlefield.index(next)
            _ = walk(p,toward:next.center,dt:dt)
        } else if p.cargo > 0 { p.intent = .unload }
        else { p.workClock = time+2 }
    }
    func readySupport(_ owner: Int, _ kind: Support) -> Double? {
        let player = players[owner]
        if kind == .airborne {
            guard player.nation == .usa, radarOnline(owner) else { return nil }; return max(0,player.airReady-time)
        }
        guard !owned(owner,.strategic).isEmpty, hasPower(owner),
              (kind == .storm) == (player.nation.side == .allied) else { return nil }
        return max(0,player.superReady-time)
    }
    @discardableResult func useSupport(_ kind: Support, owner: Int, at spot: Point) -> Bool {
        guard outcome == .playing, Battlefield.inside(spot.cell), readySupport(owner,kind) == 0,
              sighted(spot,by:owner) else { return false }
        if kind == .airborne {
            let b = Catalog.byID["E1"]!
            guard map.tile(spot.cell).isLand else { return false }
            for i in 0..<5 {
                if let c = nearestOpen(spot.offset(Double(i%3)-1,Double(i/3)).cell,for:b,excluding:nil) { _ = spawn(b.id,owner,c.center) }
            }
            players[owner].airReady = time+85; effect(spot,spot,"drop")
        } else {
            let radius = kind == .storm ? 4.4 : 4.0
            for other in Array(pieces.values) where other.owner != owner {
                let d = edgeDistance(spot,other)
                if d < radius { hit(other,(kind == .storm ? 770 : 920)*(1-0.55*d/radius),by:owner) }
            }
            players[owner].superReady = time+150; effect(spot,spot,kind == .storm ? "storm" : "blast")
        }
        checkOutcome(); return true
    }
    func updateUnit(_ p: Piece, dt: Double) {
        let b = p.spec
        p.cooldown = max(0,p.cooldown-dt)
        if b.isBuilding {
            if p.repairing && p.workClock <= time {
                let missing = Double(b.stats.hp)-p.hp
                if missing <= 0 { p.repairing = false } else if players[p.owner].credits >= 6 {
                    p.hp += min(18,missing); players[p.owner].credits -= 6; p.workClock = time+0.5
                }
            }
            if b.role == .depot && p.cooldown == 0 && hasPower(p.owner), let unit = owned(p.owner).first(where: {
                $0.spec.lane == .vehicle && $0.hp < Double($0.spec.stats.hp) && edgeDistance($0.pos,p) <= 2.5
            }), players[p.owner].credits >= 4 {
                unit.hp = min(Double(unit.spec.stats.hp),unit.hp+32); players[p.owner].credits -= 4; p.cooldown = 0.75
            }
            if b.stats.power < 0 && b.role == .turret && !hasPower(p.owner) { return }
        }
        if p.intent == .engineer {
            guard let id = p.target, let target = pieces[id], target.spec.isBuilding else { p.stop(); return }
            if edgeDistance(p.pos,target) <= 1.25 {
                if target.owner == p.owner && target.hp >= Double(target.spec.stats.hp) { p.stop(); return }
                if target.owner != p.owner { target.owner = p.owner; target.repairing = false; target.hp = max(target.hp,Double(target.spec.stats.hp)*0.5) }
                else { target.hp = Double(target.spec.stats.hp) }
                retire(p); refreshVision()
            } else { walk(p,toward:approach(p,target),dt:dt) }
            return
        }
        if (p.intent == .move || p.intent == .advance), let goal = p.goal {
            if p.intent == .advance, let w = b.weapon, let contact = acquire(p,radius:w.range) {
                fire(p,contact,w); return
            }
            if walk(p,toward:goal,dt:dt) { p.stop() }
            return
        }
        let explicit = p.intent == .attack ? p.target.flatMap { pieces[$0] } : nil
        if p.intent == .attack && (explicit == nil || explicit?.owner == p.owner) { p.stop() }
        if let w = b.weapon {
            let reach = w.range+(p.entrenched ? 1.4 : 0)
            if let target = explicit, canHit(p,target) {
                guard sighted(target.pos,by:p.owner) else {
                    let last = p.lastContact ?? p.pos; p.stop(); p.intent = .advance; p.goal = last; return
                }
                p.lastContact = target.pos
                if edgeDistance(p.pos,target) <= reach { fire(p,target,w); return }
                if !b.isBuilding && !p.entrenched {
                    if p.cooldown <= 0, let contact = acquire(p,radius:reach) { fire(p,contact,w) }
                    if pieces[p.id] != nil { walk(p,toward:approach(p,target),dt:dt) }
                    return
                }
            } else if p.cooldown <= 0, let contact = acquire(p,radius:reach) {
                fire(p,contact,w)
                if b.role != .miner { return }
            }
        }
        if b.role == .miner { mine(p,dt:dt) }
    }
    func tick() {
        guard outcome == .playing else { return }
        let dt = Self.step
        time += dt; flash.removeAll { $0.until < time }
        let interval = Double(Battlefield.growthInterval)
        let cycle = Int(time / interval)
        if cycle != Int((time-dt) / interval) {
            for site in map.oreMines.sorted() {
                if let i = map.replenish(at:site,cycle:cycle,occupied:occupied) {
                    effect(Battlefield.cell(site).center,Battlefield.cell(i).center,"ore")
                    revision += 1
                }
            }
        }
        for i in players.indices where !players[i].eliminated {
            processJobs(i,dt:dt)
            if i > 0 && players[i].nextThink <= time {
                players[i].nextThink = time + settings.difficulty.thinkPeriod; think(i)
            }
        }
        reindex()
        for id in pieces.keys.sorted() { if let p = pieces[id] { updateUnit(p,dt:dt) } }
        if time >= timeForVision { refreshVision(); checkOutcome(); timeForVision = time+0.5 }
    }
}
