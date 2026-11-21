import Foundation

enum MapClimate: String, Decodable { case temperate, coastal, snow, desert, taiga, salt, industrial }

/// Each character in the bundled atlas is one battlefield cell. Numbered cells are clockwise start slots.
struct SkirmishMap {
    let code: String, detail: String, climate: MapClimate, naval: Bool, seed: UInt64
    let tiles: [Ground], ore: [Int], oreMines: Set<Int>, gems: Set<Int>
    let starts: [Point]

    private struct Record: Decodable {
        let theater: Theater, code: String, detail: String, climate: MapClimate, naval: Bool, seed: UInt64
        let rows: [String]
    }

    static let catalog: [Theater:SkirmishMap] = {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource:"skirmish-maps",withExtension:"json"),
              let data = try? Data(contentsOf:url),
              let records = try? JSONDecoder().decode([Record].self,from:data)
        else { preconditionFailure("Missing bundled skirmish maps") }
        precondition(records.count == Theater.allCases.count && Set(records.map(\.theater)) == Set(Theater.allCases))
        return Dictionary(uniqueKeysWithValues:records.map { ($0.theater,SkirmishMap($0)) })
    }()

    private init(_ record: Record) {
        code = record.code; detail = record.detail; climate = record.climate; naval = record.naval; seed = record.seed
        let n = Battlefield.size
        precondition(record.rows.count == n && record.rows.allSatisfy { $0.utf8.count == n })
        var ground = [Ground](), slots = [Int:Point](), fields = [(cell:Cell, gem:Bool)]()
        ground.reserveCapacity(n*n)
        for (y,row) in record.rows.enumerated() {
            for (x,mark) in row.enumerated() {
                let cell = Cell(x,y)
                switch mark {
                case ".": ground.append(.grass)
                case ":": ground.append(.dirt)
                case ",": ground.append(.gravel)
                case "~": ground.append(.water)
                case "=": ground.append(.road)
                case "^": ground.append(.ridge)
                case "o","*":
                    fields.append((cell,mark == "*"))
                    ground.append(mark == "*" ? .gravel : .dirt)
                default:
                    guard let slot = mark.wholeNumberValue, (1...MatchSettings.maxPlayers).contains(slot),
                          slots.updateValue(cell.center,forKey:slot) == nil else { preconditionFailure("Invalid map marker \(mark)") }
                    ground.append(.grass)
                }
            }
        }
        precondition(slots.count == MatchSettings.maxPlayers)
        starts = slots.sorted { $0.key < $1.key }.map(\.value)
        tiles = ground
        let mines = Set(fields.map { Battlefield.index($0.cell) })
        var stock = [Int](repeating:0,count:n*n), gemCells = Set<Int>(), random = RandomStream(state:record.seed)
        for (site,gem) in fields {
            let span = gem ? 4 : 2
            for dy in -span...span { for dx in -span...span where dx*dx+dy*dy <= (gem ? 16 : 5) {
                let cell = Cell(site.x+dx,site.y+dy)
                guard Battlefield.inside(cell) else { continue }
                let i = Battlefield.index(cell)
                guard ground[i].isLand, !mines.contains(i) else { continue }
                stock[i] = gem ? 1200 + Int(random.next()*1200) : 1000 + Int(random.next()*750)
                if gem { gemCells.insert(i) }
            }}
        }
        ore = stock; oreMines = mines; gems = gemCells
    }

    func seats(for total: Int) -> [Point] {
        let count = min(starts.count,max(1,total))
        // Select evenly spaced clockwise slots, keeping two opponents on opposite sides.
        return (0..<count).map { starts[($0 * starts.count + count/2) / count] }
    }
}
