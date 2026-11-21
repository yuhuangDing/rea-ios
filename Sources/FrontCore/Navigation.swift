import Foundation

private struct Frontier {
    var nodes: [(Int,Int)] = []
    mutating func push(_ cell: Int, _ cost: Int) {
        var i = nodes.count
        nodes.append((cell,cost))
        while i > 0 {
            let parent = (i-1)/2
            if nodes[parent].1 <= cost { break }
            nodes[i] = nodes[parent]; i = parent
        }
        nodes[i] = (cell,cost)
    }
    mutating func pop() -> Int? {
        guard let first = nodes.first else { return nil }
        let end = nodes.removeLast()
        if !nodes.isEmpty {
            var i = 0
            while i*2+1 < nodes.count {
                var child = i*2+1
                if child+1 < nodes.count && nodes[child+1].1 < nodes[child].1 { child += 1 }
                if end.1 <= nodes[child].1 { break }
                nodes[i] = nodes[child]; i = child
            }
            nodes[i] = end
        }
        return first.0
    }
}

extension Battle {
    static let directions = [Cell(-1,0),Cell(1,0),Cell(0,-1),Cell(0,1),Cell(-1,-1),Cell(1,-1),Cell(1,1),Cell(-1,1)]
    func passable(_ c: Cell, for b: Blueprint, excluding: Int? = nil) -> Bool {
        guard Battlefield.inside(c) else { return false }
        if b.flies { return true }
        let ground = map.tile(c)
        guard (b.lane == .naval ? ground == .water : ground.isLand), !map.oreMines.contains(Battlefield.index(c)) else { return false }
        if let blocker = occupied[Battlefield.index(c)], blocker != excluding { return false }
        return true
    }
    private func canStep(from cell: Cell, by d: Cell, for unit: Blueprint) -> Bool {
        guard passable(Cell(cell.x+d.x,cell.y+d.y),for:unit) else { return false }
        return d.x == 0 || d.y == 0 ||
            (passable(Cell(cell.x+d.x,cell.y),for:unit) && passable(Cell(cell.x,cell.y+d.y),for:unit))
    }

    // Search only reachable ground, using the same corner and blocker rules as the movement path.
    func nearestMiningCell(from start: Cell, for unit: Blueprint, matching accepts: (Int) -> Bool) -> Cell? {
        guard Battlefield.inside(start) else { return nil }
        var cells = [start], cursor = 0, visited = Set([start])
        while cursor < cells.count {
            let cell = cells[cursor]; cursor += 1
            if accepts(Battlefield.index(cell)) && passable(cell,for:unit) { return cell }
            for d in Self.directions {
                let next = Cell(cell.x+d.x,cell.y+d.y)
                if !visited.contains(next), canStep(from:cell,by:d,for:unit) {
                    cells.append(next); visited.insert(next)
                }
            }
        }
        return nil
    }

    func nearestOpen(_ c: Cell, for b: Blueprint, excluding: Int?, avoiding reserved: Set<Cell> = []) -> Cell? {
        if !reserved.contains(c) && passable(c,for:b,excluding:excluding) { return c }
        for r in 1...9 {
            var candidate: Cell?, best = Int.max
            for dy in -r...r { for dx in -r...r where abs(dx) == r || abs(dy) == r {
                let n = Cell(c.x+dx,c.y+dy), distance = dx*dx+dy*dy
                if distance < best && !reserved.contains(n) && passable(n,for:b,excluding:excluding) { candidate = n; best = distance }
            }}
            if let candidate { return candidate }
        }
        return nil
    }
    func route(from start: Cell, to desired: Cell, for b: Blueprint) -> [Cell] {
        guard Battlefield.inside(start), let end = nearestOpen(desired,for:b,excluding:nil), end != start else { return [] }
        if b.flies { return [end] }
        let n = Battlefield.size, first = Battlefield.index(start), last = Battlefield.index(end)
        var open = Frontier(), parent = [Int:Int](), costs = [first:0], closed = Set<Int>()
        func estimate(_ x: Int, _ y: Int) -> Int {
            let dx = abs(x-end.x), dy = abs(y-end.y)
            return 10*max(dx,dy)+4*min(dx,dy)
        }
        open.push(first,estimate(start.x,start.y))
        while let idx = open.pop() {
            if idx == last {
                var result: [Cell] = [], cursor = last
                while cursor != first, let previous = parent[cursor] {
                    result.append(Cell(cursor % n,cursor / n)); cursor = previous
                }
                return result.reversed()
            }
            if !closed.insert(idx).inserted { continue }
            let x = idx % n, y = idx / n
            for d in Self.directions {
                let next = Cell(x+d.x,y+d.y)
                guard canStep(from:Cell(x,y),by:d,for:b) else { continue }
                let diag = d.x != 0 && d.y != 0
                let ni = Battlefield.index(next), price = costs[idx]! + (diag ? 14 : 10)
                if price < costs[ni,default:Int.max] {
                    costs[ni] = price; parent[ni] = idx; open.push(ni,price+estimate(next.x,next.y))
                }
            }
        }
        return []
    }
    @discardableResult func walk(_ p: Piece, toward point: Point, dt: Double) -> Bool {
        let goalChanged = p.goal?.cell != point.cell
        if goalChanged || p.nextRoute <= time && (p.waypoint >= p.path.count || !passable(p.path[p.waypoint],for:p.spec)) {
            p.goal = point; p.path = route(from:p.pos.cell,to:point.cell,for:p.spec)
            p.waypoint = 0; p.nextRoute = time + 1.35
        }
        guard p.waypoint < p.path.count else { return true }
        let cell = p.path[p.waypoint]
        if !passable(cell,for:p.spec) { p.path = []; p.waypoint = 0; p.nextRoute = 0; return false }
        let next = cell.center, dx = next.x-p.pos.x, dy = next.y-p.pos.y, dist = hypot(dx,dy)
        let step = p.spec.speed*dt
        if dist > 0.02 { p.direction = atan2(dy,dx) }
        if dist <= step {
            p.pos = next; p.waypoint += 1
            return p.waypoint == p.path.count
        }
        p.pos = p.pos.offset(dx/dist*step,dy/dist*step)
        return false
    }
    func edgeDistance(_ a: Point, _ b: Piece) -> Double {
        guard b.spec.isBuilding else { return a.distance(b.pos) }
        let r = Double(b.spec.footprint)/2
        return hypot(max(0,abs(a.x-b.pos.x)-r), max(0,abs(a.y-b.pos.y)-r))
    }
    func approach(_ p: Piece, _ b: Piece) -> Point {
        guard b.spec.isBuilding else { return b.pos }
        let o = b.origin, s = b.spec.footprint
        var best = b.pos, dist = Double.infinity
        for y in -1...s { for x in -1...s where x == -1 || y == -1 || x == s || y == s {
            let c = Cell(o.x+x,o.y+y), d = p.pos.distance(c.center)
            if d < dist && passable(c,for:p.spec) { dist = d; best = c.center }
        }}
        return best
    }
    func order(_ ids: [Int], owner: Int, to point: Point, target: Int? = nil, advance: Bool = false) {
        guard outcome == .playing, Battlefield.inside(point.cell) else { return }
        let hit = target.flatMap { pieces[$0] }
        let units = ids.compactMap { pieces[$0] }.filter { $0.owner == owner && !$0.spec.isBuilding }
        let wide = max(1,Int(ceil(sqrt(Double(units.count)))))
        for (i,p) in units.enumerated() {
            p.stop(); p.entrenched = false
            if let hit, sighted(hit.pos,by:owner), hit.hp > 0 {
                if p.spec.role == .engineer && hit.spec.isBuilding {
                    p.intent = .engineer; p.target = hit.id; continue
                }
                if hit.owner != owner && canHit(p,hit) {
                    p.intent = .attack; p.target = hit.id; p.lastContact = hit.pos; continue
                }
            }
            if p.spec.role == .miner && map.ore[Battlefield.index(point.cell)] > 0 {
                p.intent = .harvest; p.goal = nil; p.workClock = 0; p.path = []
                p.target = Battlefield.index(point.cell); continue
            }
            let dx = Double(i%wide)-Double(min(wide,units.count)-1)/2
            let dy = Double(i/wide)-Double((units.count-1)/wide)/2
            let dest = point.offset(dx*1.12,dy*1.12)
            if let c = nearestOpen(dest.cell,for:p.spec,excluding:nil) {
                p.intent = advance && p.spec.weapon != nil ? .advance : .move
                p.goal = c.center; p.path = route(from:p.pos.cell,to:c,for:p.spec); p.waypoint = 0
                p.nextRoute = time+1
            }
        }
    }
}
