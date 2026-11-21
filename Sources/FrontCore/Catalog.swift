import Foundation

enum Side: String, Codable { case allied, soviet }

enum Nation: String, CaseIterable, Codable, Identifiable {
    case usa, uk, france, germany, korea, russia, cuba, iraq, libya
    var id: Self { self }
    var name: String {
        switch self {
        case .usa: return "美国"; case .uk: return "英国"; case .france: return "法国"
        case .germany: return "德国"; case .korea: return "韩国"; case .russia: return "苏俄"
        case .cuba: return "古巴"; case .iraq: return "伊拉克"; case .libya: return "利比亚"
        }
    }
    var flag: String {
        switch self {
        case .usa: return "🇺🇸"; case .uk: return "🇬🇧"; case .france: return "🇫🇷"
        case .germany: return "🇩🇪"; case .korea: return "🇰🇷"; case .russia: return "🇷🇺"
        case .cuba: return "🇨🇺"; case .iraq: return "🇮🇶"; case .libya: return "🇱🇾"
        }
    }
    var side: Side {
        switch self { case .usa, .uk, .france, .germany, .korea: return .allied; default: return .soviet }
    }
    var signature: String {
        switch self {
        case .usa: return "空降伞兵"; case .uk: return "狙击手"; case .france: return "法国巨炮"
        case .germany: return "坦克杀手"; case .korea: return "黑鹰战机"; case .russia: return "磁暴坦克"
        case .cuba: return "古巴爆破手"; case .iraq: return "辐射工兵"; case .libya: return "自爆卡车"
        }
    }
}

enum Lane: String, Codable, CaseIterable, Identifiable {
    case construction = "建筑", defense = "防御", infantry = "步兵", vehicle = "战车", air = "空军", naval = "海军"
    var id: Self { self }
    var symbol: String {
        switch self { case .construction: return "building.2"; case .defense: return "shield.lefthalf.filled"
        case .infantry: return "person.2"; case .vehicle: return "gearshape"; case .air: return "airplane"; case .naval: return "ferry" }
    }
}

enum Role: String, Codable {
    case yard, power, refinery, barracks, factory, radar, lab, dock, depot, turret, strategic
    case mcv, miner, soldier, engineer, dog, tank, plane, ship
}

struct Weapon {
    let damage: Double, range: Double, reload: Double
    var air = false
    var ground = true
    var splash = 0.0
    var suicide = false
    var color = "shell"
    init(_ damage: Double, _ range: Double, _ reload: Double, air: Bool = false,
         ground: Bool = true, splash: Double = 0, suicide: Bool = false, color: String = "shell") {
        self.damage = damage; self.range = range; self.reload = reload; self.air = air
        self.ground = ground; self.splash = splash; self.suicide = suicide; self.color = color
    }
}

struct ReferenceStats: Decodable {
    let name: String, sourceId: String, sourceName: String, cost: Int, hp: Int, power: Int
    let sight: Int, speed: Int, armor: String, sourcePrerequisite: String, cameo: String
}

struct Blueprint: Identifiable {
    let id: String, side: Side, role: Role, lane: Lane, stats: ReferenceStats
    let requires: [Role], exclusive: Nation?, footprint: Int, weapon: Weapon?
    var isBuilding: Bool { lane == .construction || lane == .defense }
    var flies: Bool { lane == .air || id == "JUMPJET" }
    var duration: Double { max(2.2, min(37, Double(stats.cost) / (isBuilding ? 115 : 140))) }
    var speed: Double { Double(stats.speed) * (flies ? 0.38 : 0.27) }
    var name: String { stats.name }
}

enum Catalog {
    static let all: [Blueprint] = {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "roster", withExtension: "json"),
              let bytes = try? Data(contentsOf: url),
              let stats = try? JSONDecoder().decode([String: ReferenceStats].self, from: bytes)
        else { preconditionFailure("Missing bundled L3 roster") }
        var list: [Blueprint] = []
        func add(_ id: String, _ side: Side, _ role: Role, _ lane: Lane, _ requires: [Role],
                 _ size: Int = 1, _ weapon: Weapon? = nil, only: Nation? = nil) {
            guard let record = stats[id] else { preconditionFailure("Missing stats \(id)") }
            list.append(Blueprint(id: id, side: side, role: role, lane: lane, stats: record,
                                  requires: requires, exclusive: only, footprint: size, weapon: weapon))
        }
        for side in [Side.allied, .soviet] {
            let a = side == .allied
            add(a ? "GACNST" : "NACNST", side, .yard, .construction, [], 3)
            add(a ? "GAPOWR" : "NAPOWR", side, .power, .construction, [.yard], 2)
            add(a ? "GAPILE" : "NAHAND", side, .barracks, .construction, [.yard, .power], 2)
            add(a ? "GAREFN" : "NAREFN", side, .refinery, .construction, [.yard, .power], 3)
            add(a ? "GAWEAP" : "NAWEAP", side, .factory, .construction, [.yard, .refinery, .barracks], 3)
            add(a ? "AMRADR" : "NARADR", side, .radar, .construction, [.yard, .refinery], 2)
            add(a ? "GADEPT" : "NADEPT", side, .depot, .construction, [.yard, .factory], 2)
            add(a ? "GATECH" : "NATECH", side, .lab, .construction, [.yard, .factory, .radar], 2)
            add(a ? "GAYARD" : "NAYARD", side, .dock, .construction, [.yard, .refinery, .power], 2)
            add(a ? "GAPILL" : "NALASR", side, .turret, .defense, [.yard, .barracks], 1, Weapon(24, 5.2, 0.85, color: "bullet"))
            add(a ? "ATESLA" : "TESLA", side, .turret, .defense, [.yard, .radar, .power], 1, Weapon(105, 7, 2.4, air: true, color: a ? "prism" : "arc"))
            add(a ? "GAWEAT" : "NAMISL", side, .strategic, .defense, [.yard, .lab], 2)
            add(a ? "E1" : "E2", side, .soldier, .infantry, [.barracks], 1, Weapon(a ? 14 : 12, 3.4, a ? 0.82 : 0.88, color: "bullet"))
            add(a ? "ENGINEER" : "SENGINEER", side, .engineer, .infantry, [.barracks])
            add(a ? "ADOG" : "DOG", side, .dog, .infantry, [.barracks], 1, Weapon(90, 1, 1.1, color: "bite"))
            add(a ? "CMIN" : "HARV", side, .miner, .vehicle, [.factory, .refinery], 1, a ? nil : Weapon(13, 3.8, 0.9, color: "bullet"))
            add(a ? "MTNK" : "HTNK", side, .tank, .vehicle, [.factory], 1, Weapon(a ? 52 : 67, a ? 4.8 : 5.1, a ? 1.35 : 1.65))
            add(a ? "FV" : "HTK", side, .tank, .vehicle, [.factory], 1, Weapon(26, 5, 0.95, air: true))
            add(a ? "AMCV" : "SMCV", side, .mcv, .vehicle, [.factory, .depot])
            add(a ? "SREF" : "APOC", side, .tank, .vehicle, [.factory, .lab], 1,
                Weapon(a ? 104 : 120, a ? 7.3 : 5.7, 2.1, air: !a, splash: 1.1, color: a ? "prism" : "shell"))
            add(a ? "DEST" : "SUB", side, .ship, .naval, [.dock], 1, Weapon(76, 6.5, 1.7))
            add(a ? "AEGIS" : "DRED", side, .ship, .naval, a ? [.dock, .radar] : [.dock, .lab], 1,
                Weapon(a ? 78 : 135, a ? 8 : 10, 2.4, air: a, ground: !a, splash: a ? 0 : 1.7))
        }
        add("JUMPJET", .allied, .soldier, .infantry, [.barracks, .radar], 1, Weapon(18, 4.6, 0.8, air: true, color: "bullet"))
        add("SHK", .soviet, .soldier, .infantry, [.barracks], 1, Weapon(45, 3.4, 1.5, color: "arc"))
        add("ORCA", .allied, .plane, .air, [.radar], 1, Weapon(85, 4.3, 2.8))
        add("ZEP", .soviet, .plane, .air, [.factory, .lab], 1, Weapon(140, 2.8, 2.3, splash: 1.4))
        add("SNIPE", .allied, .soldier, .infantry, [.barracks, .radar], 1, Weapon(135, 8.5, 2.6, color: "bullet"), only: .uk)
        add("GTGCAN", .allied, .turret, .defense, [.yard, .radar], 2, Weapon(140, 10, 3.1, splash: 1.5), only: .france)
        add("TNKD", .allied, .tank, .vehicle, [.factory, .radar], 1, Weapon(95, 5.8, 1.55), only: .germany)
        add("BEAG", .allied, .plane, .air, [.radar], 1, Weapon(115, 4.8, 2.6, splash: 0.8), only: .korea)
        add("TTNK", .soviet, .tank, .vehicle, [.factory, .radar], 1, Weapon(90, 5, 1.55, color: "arc"), only: .russia)
        add("DESO", .soviet, .soldier, .infantry, [.barracks, .radar], 1, Weapon(58, 4.5, 1.5, splash: 1.7, color: "rad"), only: .iraq)
        add("TERROR", .soviet, .soldier, .infantry, [.barracks, .radar], 1, Weapon(220, 1.2, 1, splash: 2.2, suicide: true), only: .cuba)
        add("DTRUCK", .soviet, .tank, .vehicle, [.factory, .radar], 1, Weapon(520, 1.6, 1, splash: 3.1, suicide: true), only: .libya)
        return list
    }()
    static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    static func options(_ nation: Nation, _ lane: Lane) -> [Blueprint] {
        all.filter { $0.side == nation.side && $0.lane == lane && $0.role != .yard &&
            ($0.exclusive == nil || $0.exclusive == nation) && !(nation == .korea && $0.id == "ORCA") }
    }
    static func id(_ role: Role, _ nation: Nation) -> String {
        all.first { $0.side == nation.side && $0.role == role }!.id
    }
}
