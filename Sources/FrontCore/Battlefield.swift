import Foundation

struct Point: Codable, Equatable {
    var x: Double, y: Double
    init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    func distance(_ other: Point) -> Double { hypot(x - other.x, y - other.y) }
    func offset(_ dx: Double, _ dy: Double) -> Point { Point(x + dx, y + dy) }
    var cell: Cell { Cell(Int(floor(x)), Int(floor(y))) }
}
struct Cell: Hashable, Codable {
    var x: Int, y: Int
    init(_ x: Int, _ y: Int) { self.x = x; self.y = y }
    var center: Point { Point(Double(x) + 0.5, Double(y) + 0.5) }
}
enum Theater: String, Codable, CaseIterable, Identifiable {
    case frontier = "边境平原", gulf = "灰湾海岸", frost = "霜线高地", rivers = "双河渡口", basin = "赤岩盆地"
    case pass = "黑松山口", lakes = "盐湖走廊", isles = "潮汐群岛", junction = "钢铁枢纽", strait = "裂岸海峡"
    var id: Self { self }
    var layout: SkirmishMap { SkirmishMap.catalog[self]! }
    var code: String { layout.code }
    var detail: String { layout.detail }
    var allowsShipyards: Bool { layout.naval }
}
enum Difficulty: String, Codable, CaseIterable, Identifiable {
    case relaxed = "简单", regular = "标准", hard = "困难"
    var id: Self { self }
    var wavePeriod: Double { switch self { case .relaxed: return 95; case .regular: return 68; case .hard: return 46 } }
    var thinkPeriod: Double { switch self { case .relaxed: return 4; case .regular: return 2.4; case .hard: return 1.5 } }
}
struct MatchSettings: Codable, Equatable {
    static let maxPlayers = 8
    var playerCount: Int { opponents.count + 1 }
    var nation: Nation = .usa
    var opponents: [Nation] = [.russia, .germany]
    var theater: Theater = .frontier
    var difficulty: Difficulty = .regular
    var credits = 10000
    var fog = true
    var seed: UInt64 = 1877
}
struct RandomStream: Codable {
    var state: UInt64
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / 9007199254740992
    }
}
enum Ground: UInt8, Codable {
    case grass, dirt, gravel, water, road, ridge
    var isLand: Bool { self != .water && self != .ridge }
}
struct Battlefield: Codable {
    static let size = 52
    let theater: Theater
    let seed: UInt64
    var tiles: [Ground], ore: [Int], seats: [Point]
    var oreMines = Set<Int>(), gems = Set<Int>()
    static let growthInterval = 3, growthAmount = 180, goldCapacity = 1750
    static func cell(_ index: Int) -> Cell { Cell(index % size,index / size) }
    static func inside(_ c: Cell) -> Bool { (0..<size).contains(c.x) && (0..<size).contains(c.y) }
    static func index(_ c: Cell) -> Int { c.y * size + c.x }
    static func footprint(_ origin: Cell, size: Int) -> [Cell] {
        (0..<size).flatMap { y in (0..<size).map { x in Cell(origin.x + x, origin.y + y) } }
    }
    func tile(_ c: Cell) -> Ground { Self.inside(c) ? tiles[Self.index(c)] : .water }

    private enum CodingKeys: String, CodingKey { case theater, seed, tiles, ore, seats, oreMines, gems }
    init(from decoder: Decoder) throws {
        let data = try decoder.container(keyedBy:CodingKeys.self)
        theater = try data.decode(Theater.self,forKey:.theater); seed = try data.decode(UInt64.self,forKey:.seed)
        tiles = try data.decode([Ground].self,forKey:.tiles); ore = try data.decode([Int].self,forKey:.ore)
        seats = try data.decode([Point].self,forKey:.seats)
        oreMines = try data.decodeIfPresent(Set<Int>.self,forKey:.oreMines) ?? []
        if let saved = try data.decodeIfPresent(Set<Int>.self,forKey:.gems) { gems = saved }
        else {
            // The previous renderer identified the initial central gems by distance.
            let center = Point(Double(Self.size/2),Double(Self.size/2))
            gems = Set(ore.indices.filter { ore[$0] > 0 && Self.cell($0).center.distance(center) < 5 })
        }
    }

    private static func deposit(near seat: Point) -> Cell {
        let mid = Double(size)/2, heading = atan2(seat.y-mid,seat.x-mid)
        return seat.offset(-sin(heading)*5.8,cos(heading)*5.8).cell
    }

    static func mineralField(around site: Int) -> [Int] {
        let center = cell(site)
        var cells = [Int]()
        for dy in -2...2 { for dx in -2...2 where (1...5).contains(dx*dx+dy*dy) {
            let c = Cell(center.x+dx,center.y+dy)
            if inside(c) { cells.append(index(c)) }
        }}
        return cells
    }

    // A loaded pre-mine map may already have a building or vehicle on the intended site.
    mutating func installOreMines(avoiding blocked: Set<Int> = []) {
        let centers = seats.map(Self.deposit(near:)) + [Cell(Self.size/2,Self.size/2)]
        for center in centers {
            func available(_ i: Int) -> Bool { tiles[i].isLand && !blocked.contains(i) && !oreMines.contains(i) }
            func outlet(_ site: Int) -> Int? {
                Self.mineralField(around:site).first {
                    available($0) && (ore[site] == 0 || ore[$0] == 0 || gems.contains($0) == gems.contains(site))
                        && ore[$0] <= Int.max - ore[site]
                }
            }
            let preferred = Self.index(center)
            let site: Int
            if Self.inside(center), available(preferred), outlet(preferred) != nil { site = preferred }
            else {
                guard let nearby = tiles.indices.filter({ available($0) && outlet($0) != nil }).min(by:{
                    Self.cell($0).center.distance(center.center) < Self.cell($1).center.distance(center.center)
                }) else { continue }
                site = nearby
            }
            if ore[site] > 0, let neighbor = outlet(site) {
                // Move the stock under the concrete footing into the surrounding deposit.
                ore[neighbor] += ore[site]; ore[site] = 0
                if gems.remove(site) != nil { gems.insert(neighbor) }
            }
            oreMines.insert(site)
        }
    }

    mutating func replenish(at site: Int, cycle: Int, occupied: [Int:Int]) -> Int? {
        let field = Self.mineralField(around:site)
        guard !field.isEmpty else { return nil }
        let start = (site + cycle) % field.count
        var chosen: Int?, lowestStock = Self.goldCapacity
        for offset in field.indices {
            let i = field[(start+offset) % field.count]
            guard tiles[i].isLand, occupied[i] == nil, !oreMines.contains(i), !gems.contains(i),
                  ore[i] < lowestStock else { continue }
            chosen = i; lowestStock = ore[i]
        }
        if let i = chosen { ore[i] = min(Self.goldCapacity,ore[i]+Self.growthAmount) }
        return chosen
    }

    init(settings: MatchSettings, count: Int) {
        let layout = settings.theater.layout
        theater = settings.theater; seed = layout.seed
        tiles = layout.tiles; seats = layout.seats(for:count)
        ore = layout.ore; oreMines = layout.oreMines; gems = layout.gems
    }
}
