import XCTest
@testable import FrontCore

final class SkirmishTests: XCTestCase {
    func testRosterAndEightWayStart() throws {
        XCTAssertEqual(Catalog.all.count, 56)
        var s = MatchSettings(); s.opponents = Array(Nation.allCases.dropFirst()); s.theater = .gulf
        let game = Battle(s)
        XCTAssertEqual(game.players.count,8); XCTAssertEqual(Set(game.map.seats.map(\.cell)).count,8)
        XCTAssertEqual(game.owned(0).count,6)
        XCTAssertEqual(Catalog.byID["MTNK"]!.stats.cost,700)
        XCTAssertEqual(Catalog.byID["HTNK"]!.stats.hp,400)
        XCTAssertFalse(Catalog.options(.usa,.vehicle).contains(where:{$0.id=="TNKD"}))
        XCTAssertTrue(Catalog.options(.germany,.vehicle).contains(where:{$0.id=="TNKD"}))
        for _ in 0..<160 { game.tick() }
        XCTAssertTrue((1..<8).allSatisfy { !game.owned($0,.yard).isEmpty && !game.owned($0,.power).isEmpty })
    }
    func testBuildMineQueueSaveAndWin() throws {
        var s = MatchSettings(); s.opponents = [.russia]; s.difficulty = .relaxed
        let g = Battle(s)
        let mcv = try XCTUnwrap(g.owned(0,.mcv).first)
        XCTAssertTrue(g.deploy(mcv.id)); XCTAssertFalse(g.enqueue("GAWEAP",owner:0))
        for id in ["GAPOWR","GAREFN","GAPILE","GAWEAP"] {
            XCTAssertTrue(g.enqueue(id,owner:0)); let b = Catalog.byID[id]!
            while g.players[0].work(for:b).active?.ready != true { g.tick() }
            XCTAssertFalse(g.place(b.id,owner:0,origin:mcv.origin))
            let location = try XCTUnwrap(g.buildSite(b,owner:0))
            XCTAssertTrue(g.place(b.id,owner:0,origin:location))
        }
        XCTAssertEqual(g.owned(0,.miner).count,1)
        let cash = g.players[0].credits
        XCTAssertTrue(g.enqueue("MTNK",owner:0)); XCTAssertEqual(g.cancelProduction("MTNK",owner:0),0)
        XCTAssertEqual(g.players[0].credits,cash)
        XCTAssertTrue(g.enqueue("MTNK",owner:0)); for _ in 0..<180 { g.tick() }
        XCTAssertGreaterThan(g.players[0].mined,0); XCTAssertGreaterThanOrEqual(g.owned(0,.tank).count,3)
        let saved = try JSONEncoder().encode(g), resumed = try Battle.restore(saved)
        XCTAssertEqual(resumed.time,g.time); XCTAssertEqual(resumed.pieces.count,g.pieces.count)
        XCTAssertEqual(resumed.players[0].credits,g.players[0].credits); XCTAssertEqual(resumed.occupied,g.occupied)
        for p in resumed.owned(1) where p.spec.isBuilding || p.spec.role == .mcv { resumed.hit(p,9999,by:0) }
        resumed.checkOutcome(); XCTAssertEqual(resumed.outcome,.won)
    }
    func testUnaidedOpponentCanFinishMatch() {
        var s = MatchSettings(); s.opponents = [.russia]; s.difficulty = .hard; s.fog = false
        let g = Battle(s)
        for _ in 0..<5000 where g.outcome == .playing { g.tick() }
        XCTAssertEqual(g.outcome,.lost); XCTAssertGreaterThan(g.players[1].kills,0)
    }
    func testEightEconomiesAndPowerRequirements() {
        var s = MatchSettings(); s.opponents = Array(Nation.allCases.dropFirst().prefix(7))
        s.theater = .gulf; s.difficulty = .relaxed
        let g = Battle(s); _ = g.deploy(g.owned(0,.mcv)[0].id)
        let firstNewID = g.nextID
        var factories = Set<Int>(), trainedArmor = Set<Int>()
        // Adjacent countries can destroy a working factory during the same match.
        for _ in 0..<800 where trainedArmor.count < 7 {
            g.tick()
            for piece in g.pieces.values where piece.owner > 0 && piece.id >= firstNewID {
                if piece.spec.role == .factory { factories.insert(piece.owner) }
                if piece.spec.lane == .vehicle && piece.spec.role == .tank { trainedArmor.insert(piece.owner) }
            }
        }
        XCTAssertEqual(factories,Set(1..<8)); XCTAssertEqual(trainedArmor,Set(1..<8))
        for i in 1..<8 { XCTAssertGreaterThan(g.players[i].mined,0,"country \(i)") }
        XCTAssertFalse(g.radarOnline(0))
        let radar = g.spawn("AMRADR",0,Point(8,6))
        XCTAssertFalse(g.radarOnline(0)); _ = g.spawn("GAPOWR",0,Point(7,9))
        XCTAssertTrue(g.radarOnline(0)); g.retire(radar); XCTAssertFalse(g.radarOnline(0))
    }

    func testPlayerCanWinUsingOnlyPlayableOrders() {
        var s = MatchSettings(); s.difficulty = .relaxed; s.opponents = [.cuba]; s.fog = false
        let g = Battle(s); XCTAssertTrue(g.deploy(g.owned(0,.mcv)[0].id))
        let plan = ["GAPOWR","GAREFN","GAPILE","GAWEAP","GAREFN","AMRADR"]
        var stage = 0
        for step in 0..<4800 where g.outcome == .playing {
            if step % 8 == 0 {
                if let front = g.players[0].readyBuilding(in:.construction), front.ready,
                   let b = Catalog.byID[front.type], let cell = g.buildSite(b,owner:0),
                   g.place(b.id,owner:0,origin:cell) { stage += 1 }
                if stage < plan.count && g.players[0].queues[.construction,default:[]].isEmpty {
                    _ = g.enqueue(plan[stage],owner:0)
                }
                if stage >= 4 && g.players[0].queues[.vehicle,default:[]].isEmpty { _ = g.enqueue("MTNK",owner:0) }
                if stage >= 4 && g.players[0].credits > 900 && g.players[0].queues[.infantry,default:[]].isEmpty {
                    _ = g.enqueue("E1",owner:0)
                }
                let troops = g.owned(0).filter { !$0.spec.isBuilding && $0.spec.weapon != nil && $0.spec.role != .miner }
                if troops.count >= 9 || g.time > 95 {
                    let enemy = g.owned(1).filter { $0.spec.isBuilding || $0.spec.role == .mcv }
                        .min { troops[0].pos.distance($0.pos)<troops[0].pos.distance($1.pos) }
                    if let enemy {
                        let free = troops.filter { $0.intent != .attack || $0.target.flatMap { g.pieces[$0] } == nil }
                        g.order(free.map(\.id),owner:0,to:enemy.pos,target:enemy.id)
                    }
                }
            }
            g.tick()
        }
        XCTAssertEqual(g.outcome,.won); XCTAssertGreaterThan(g.players[0].kills,0)
        XCTAssertGreaterThan(g.players[0].mined,0)
    }

    func testShorelineProductionAndAirborneVisibility() throws {
        var s = MatchSettings(); s.theater = .gulf; s.opponents = [.russia]
        let g = Battle(s); let yard = g.owned(0,.mcv)[0]; XCTAssertTrue(g.deploy(yard.id))
        func construct(_ id: String) throws {
            let spec = try XCTUnwrap(Catalog.byID[id]); XCTAssertTrue(g.enqueue(id,owner:0))
            for _ in 0..<Int(ceil(spec.duration/Battle.step))+2 { g.tick() }
            let cell = try XCTUnwrap(g.buildSite(spec,owner:0))
            XCTAssertTrue(g.place(spec.id,owner:0,origin:cell))
        }
        try construct("GAPOWR"); try construct("GAREFN"); try construct("GAYARD")
        XCTAssertTrue(g.enqueue("DEST",owner:0)); for _ in 0..<80 { g.tick() }
        let ship = try XCTUnwrap(g.owned(0,.ship).first); XCTAssertEqual(g.map.tile(ship.pos.cell),.water)
        try construct("AMRADR"); g.players[0].airReady = g.time
        XCTAssertFalse(g.useSupport(.airborne,owner:0,at:g.map.seats[1]))
        let count = g.owned(0,.soldier).count
        XCTAssertTrue(g.useSupport(.airborne,owner:0,at:yard.pos.offset(3,0)))
        XCTAssertEqual(g.owned(0,.soldier).count,count+5)
        XCTAssertFalse(g.useSupport(.airborne,owner:0,at:yard.pos))
    }

    func testMidQueueSaveAndEngineerCapture() throws {
        var s = MatchSettings(); s.opponents = [.russia]
        let g = Battle(s); _ = g.deploy(g.owned(0,.mcv)[0].id)
        XCTAssertTrue(g.enqueue("GAPOWR",owner:0)); for _ in 0..<8 { g.tick() }
        let loaded = try Battle.restore(JSONEncoder().encode(g))
        XCTAssertEqual(loaded.players[0].queues[.construction],g.players[0].queues[.construction])
        let home = loaded.map.seats[0]
        let enemy = loaded.spawn("NAPOWR",1,home.offset(3.5,1.5))
        let engineer = loaded.spawn("ENGINEER",0,enemy.pos.offset(-1.5,0))
        loaded.refreshVision(); loaded.order([engineer.id],owner:0,to:enemy.pos,target:enemy.id); loaded.tick()
        XCTAssertEqual(enemy.owner,0); XCTAssertNil(loaded.pieces[engineer.id])
        XCTAssertThrowsError(try Battle.restore(Data("broken".utf8)))
    }

    func testDifferentInfantryAdvanceTogetherAndCopiesFinishOneAtATime() throws {
        var setup = MatchSettings(); setup.opponents = [.russia]
        let g = Battle(setup), player = g.players[0], start = g.map.seats[0]
        _ = g.deploy(g.owned(0,.mcv)[0].id)
        let plant = g.spawn("GAPOWR",0,start.offset(5,0))
        let barracks = g.spawn("GAPILE",0,start.offset(-5,0))
        let gi = try XCTUnwrap(Catalog.byID["E1"]), eng = try XCTUnwrap(Catalog.byID["ENGINEER"])
        let funds = player.credits
        for id in [gi.id,eng.id,gi.id,gi.id,eng.id] { XCTAssertTrue(g.enqueue(id,owner:0)) }
        g.processJobs(0,dt:0.5)
        let firstGI = try XCTUnwrap(player.work(for:gi).active), firstEngineer = try XCTUnwrap(player.work(for:eng).active)
        XCTAssertEqual(player.work(for:gi).pending,3); XCTAssertEqual(player.work(for:eng).pending,2)
        XCTAssertEqual(firstGI.fraction(of:gi),0.5/gi.duration,accuracy:0.00001)
        XCTAssertEqual(firstEngineer.fraction(of:eng),0.5/eng.duration,accuracy:0.00001)
        XCTAssertEqual(firstGI.paid,Int(ceil(0.5 / gi.duration * Double(gi.stats.cost))))
        XCTAssertEqual(firstEngineer.paid,Int(ceil(0.5 / eng.duration * Double(eng.stats.cost))))
        XCTAssertEqual(player.queues[.infantry]?.last?.remaining,eng.duration)

        XCTAssertEqual(g.cancelProduction(eng.id,owner:0),0); XCTAssertEqual(g.cancelProduction(gi.id,owner:0),0)
        XCTAssertEqual(player.work(for:gi),ProductWork(pending:2,active:firstGI))
        XCTAssertEqual(player.work(for:eng),ProductWork(pending:1,active:firstEngineer))
        XCTAssertEqual(player.credits,funds-firstGI.paid-firstEngineer.paid)

        g.retire(plant); g.processJobs(0,dt:1)
        let reducedGI = try XCTUnwrap(player.work(for:gi).active), reducedEng = try XCTUnwrap(player.work(for:eng).active)
        XCTAssertEqual(firstGI.remaining-reducedGI.remaining,0.35,accuracy:0.00001)
        XCTAssertEqual(firstEngineer.remaining-reducedEng.remaining,0.35,accuracy:0.00001)
        g.retire(barracks); g.processJobs(0,dt:1)
        XCTAssertEqual(player.work(for:gi).active,reducedGI); XCTAssertEqual(player.work(for:eng).active,reducedEng)
        _ = g.spawn("GAPILE",0,start.offset(-5,0))
        let newID = g.nextID
        g.processJobs(0,dt:(reducedGI.remaining+0.001)/g.productionRate(0))
        XCTAssertEqual(player.work(for:gi).pending,1)
        XCTAssertEqual(try XCTUnwrap(player.work(for:gi).active).remaining,gi.duration-0.001,accuracy:0.00001)
        XCTAssertEqual(player.work(for:eng).pending,1)
        g.processJobs(0,dt:12)
        XCTAssertEqual(player.unfinishedCount,0)
        let troops = g.owned(0).filter { $0.id >= newID }
        XCTAssertEqual(troops.count,3); XCTAssertEqual(Set(troops.map { $0.pos.cell }).count,3)
        XCTAssertNil(g.cancelProduction(eng.id,owner:0))
        XCTAssertEqual(player.credits,funds-2*gi.stats.cost-eng.stats.cost)
    }

    func testVersionOneMixedOrdersResumeIndependentlyWithoutChargingAgain() throws {
        let g = Battle(MatchSettings()), player = g.players[0]
        _ = g.deploy(g.owned(0,.mcv)[0].id)
        _ = g.spawn("GAPOWR",0,g.map.seats[0].offset(5,0)); _ = g.spawn("GAPILE",0,g.map.seats[0].offset(-5,0))
        let gi = try XCTUnwrap(Catalog.byID["E1"]), eng = try XCTUnwrap(Catalog.byID["ENGINEER"])
        for id in [gi.id,eng.id,gi.id] { XCTAssertTrue(g.enqueue(id,owner:0)) }
        // Version 1 encoded each catalogue lane as alternating enum keys and arrays of paid jobs.
        var archive = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(g)) as? [String:Any])
        var people = try XCTUnwrap(archive["players"] as? [[String:Any]])
        let oldBalance = player.credits - 2*gi.stats.cost - eng.stats.cost
        people[0]["credits"] = oldBalance
        people[0]["queues"] = [Lane.infantry.rawValue, [
            ["type":"E1","remaining":0.9],["type":"ENGINEER","remaining":eng.duration],["type":"E1","remaining":gi.duration]
        ]] as [Any]
        archive["players"] = people; archive["version"] = 1
        let restored = try Battle.restore(JSONSerialization.data(withJSONObject:archive))
        let loaded = restored.players[0]
        XCTAssertEqual(loaded.credits,oldBalance)
        restored.processJobs(0,dt:0.25)
        XCTAssertEqual(loaded.work(for:gi).pending,2); XCTAssertEqual(loaded.work(for:eng).pending,1)
        XCTAssertEqual(try XCTUnwrap(loaded.work(for:gi).active).remaining,0.65,accuracy:0.00001)
        XCTAssertEqual(try XCTUnwrap(loaded.work(for:eng).active).remaining,eng.duration-0.25,accuracy:0.00001)
        XCTAssertEqual(loaded.credits,oldBalance)
        let again = try Battle.restore(JSONEncoder().encode(restored))
        XCTAssertEqual(again.cancelProduction(gi.id,owner:0),gi.stats.cost)
        XCTAssertEqual(again.cancelProduction(eng.id,owner:0),eng.stats.cost)
        again.processJobs(0,dt:gi.duration)
        XCTAssertNil(again.players[0].work(for:gi).active)
        XCTAssertEqual(again.players[0].credits,oldBalance+gi.stats.cost+eng.stats.cost)
    }

    func testBuildingWaitsAtItsPaidFractionThenResumesOnOreDelivery() throws {
        let battle = Battle(MatchSettings()), player = battle.players[0]
        let plant = try XCTUnwrap(Catalog.byID["GAPOWR"])
        XCTAssertTrue(battle.deploy(battle.owned(0,.mcv)[0].id))
        player.credits = 0
        XCTAssertNil(battle.reason(plant,owner:0))
        XCTAssertTrue(battle.enqueue(plant.id,owner:0))
        for _ in 0..<5 { battle.tick() }
        XCTAssertEqual(player.work(for:plant).active,Job(plant))
        XCTAssertTrue(try XCTUnwrap(player.work(for:plant).active).waitingForFunds(plant,credits:0))
        player.credits = plant.stats.cost - 340
        battle.processJobs(0,dt:plant.duration)
        let stopped = try XCTUnwrap(player.work(for:plant).active)
        XCTAssertEqual(player.credits,0); XCTAssertEqual(stopped.paid,460)
        XCTAssertEqual(stopped.fraction(of:plant),460.0/800,accuracy:1e-10)
        for _ in 0..<16 { battle.tick() }
        XCTAssertEqual(player.work(for:plant).active,stopped)

        let restored = try Battle.restore(JSONEncoder().encode(battle)), commander = restored.players[0]
        XCTAssertEqual(commander.work(for:plant).active,stopped)
        let refinery = restored.spawn("GAREFN",0,restored.map.seats[0].offset(6,0))
        let miner = restored.spawn("CMIN",0,refinery.pos.offset(2,0))
        miner.cargo = 340; miner.intent = .unload
        restored.tick()
        XCTAssertEqual(commander.mined,340); XCTAssertEqual(commander.credits,340)
        restored.tick()
        let resumed = try XCTUnwrap(commander.work(for:plant).active)
        XCTAssertGreaterThan(resumed.paid,stopped.paid)
        XCTAssertLessThan(resumed.remaining,stopped.remaining)
        restored.processJobs(0,dt:plant.duration/restored.productionRate(0))
        XCTAssertTrue(try XCTUnwrap(commander.work(for:plant).active).ready)
        XCTAssertEqual(commander.credits,0)
        XCTAssertEqual(restored.cancelProduction(plant.id,owner:0),800)
        XCTAssertNil(restored.cancelProduction(plant.id,owner:0))
        XCTAssertEqual(commander.credits,800)
    }

    func testCancelPartiallyPaidInfantryAndUnstartedCopies() throws {
        let g = Battle(MatchSettings()), player = g.players[0], start = g.map.seats[0]
        _ = g.spawn("GAPOWR",0,start.offset(5,0))
        _ = g.spawn("GAPILE",0,start.offset(-5,0))
        let eng = try XCTUnwrap(Catalog.byID["ENGINEER"])
        player.credits = 250
        for _ in 0..<3 { XCTAssertTrue(g.enqueue(eng.id,owner:0)) }
        XCTAssertEqual(player.credits,250)
        for _ in 0..<100 { g.processJobs(0,dt:0.057) }
        let active = try XCTUnwrap(player.work(for:eng).active)
        XCTAssertEqual(active.fraction(of:eng),0.5,accuracy:1e-10)
        XCTAssertEqual(player.credits,0); XCTAssertEqual(active.paid,250)
        XCTAssertEqual(g.cancelProduction(eng.id,owner:0),0)
        XCTAssertEqual(player.credits,0); XCTAssertEqual(player.work(for:eng).active,active)
        XCTAssertEqual(g.cancelProduction(eng.id,owner:0,current:true),250)
        XCTAssertEqual(player.credits,250); XCTAssertEqual(player.work(for:eng).active,Job(eng))
        for _ in 0..<3 { g.processJobs(0,dt:0.013) }
        let partial = try XCTUnwrap(player.work(for:eng).active)
        XCTAssertEqual(partial.paid,6)
        XCTAssertEqual(g.cancelProduction(eng.id,owner:0),6)
        XCTAssertEqual(player.credits,250); XCTAssertNil(g.cancelProduction(eng.id,owner:0))
    }

    func testSmallDepositsRotateAcrossTypesAndTabsAfterSaving() throws {
        var g = Battle(MatchSettings())
        XCTAssertTrue(g.deploy(g.owned(0,.mcv)[0].id))
        _ = g.spawn("GAPOWR",0,g.map.seats[0].offset(5,0))
        _ = g.spawn("GAPILE",0,g.map.seats[0].offset(-5,0))
        let types = ["GAPOWR","GAPILE","ENGINEER","E1"]
        g.players[0].credits = 0
        for id in types { XCTAssertTrue(g.enqueue(id,owner:0)) }
        for deposit in 1...8 {
            g.players[0].credits += 1
            g.processJobs(0,dt:Battle.step)
            if deposit == 3 { g = try Battle.restore(JSONEncoder().encode(g)) }
            XCTAssertEqual(g.players[0].credits,0)
        }
        for id in types { XCTAssertEqual(g.players[0].work(for:Catalog.byID[id]!).active?.paid,2) }
    }

    func testReadyBuildingsCanBePlacedByTypeInEitherOrder() throws {
        let g = Battle(MatchSettings()), player = g.players[0]
        let mcv = g.owned(0,.mcv)[0]; XCTAssertTrue(g.deploy(mcv.id))
        _ = g.spawn("GAPOWR",0,mcv.pos.offset(5,0))
        let plant = try XCTUnwrap(Catalog.byID["GAPOWR"]), barracks = try XCTUnwrap(Catalog.byID["GAPILE"])
        for id in [plant.id,plant.id,barracks.id] { XCTAssertTrue(g.enqueue(id,owner:0)) }
        g.processJobs(0,dt:barracks.duration)
        XCTAssertEqual(player.readyBuilding(in:.construction)?.type,barracks.id)
        XCTAssertFalse(try XCTUnwrap(player.work(for:plant).active).ready)
        g.processJobs(0,dt:plant.duration)
        XCTAssertTrue(try XCTUnwrap(player.work(for:plant).active).ready)
        XCTAssertTrue(try XCTUnwrap(player.work(for:barracks).active).ready)
        XCTAssertEqual(player.work(for:plant).pending,1)
        let site = try XCTUnwrap(g.buildSite(barracks,owner:0))
        XCTAssertTrue(g.place(barracks.id,owner:0,origin:site))
        XCTAssertNil(player.work(for:barracks).active); XCTAssertTrue(player.work(for:plant).active?.ready == true)
        XCTAssertEqual(g.cancelProduction(plant.id,owner:0),0)
        XCTAssertEqual(player.work(for:plant).pending,0); XCTAssertTrue(player.work(for:plant).active?.ready == true)
        XCTAssertTrue(g.place(plant.id,owner:0,origin:try XCTUnwrap(g.buildSite(plant,owner:0))))
        XCTAssertNil(player.work(for:plant).active)
    }

    func testOreMinesOccupyTheirFieldsOnAllSkirmishMaps() throws {
        let tank = try XCTUnwrap(Catalog.byID["MTNK"]), plane = try XCTUnwrap(Catalog.byID["ORCA"])
        let plant = try XCTUnwrap(Catalog.byID["GAPOWR"])
        for theater in Theater.allCases {
            for opponents in [1,7] {
                var s = MatchSettings(); s.theater = theater; s.opponents = Array(Nation.allCases.prefix(opponents))
                let g = Battle(s)
                XCTAssertEqual(g.map.oreMines.count,9)
                XCTAssertTrue(g.map.oreMines.contains(Battlefield.index(Cell(26,26))))
                for site in g.map.oreMines {
                    let cell = Battlefield.cell(site)
                    XCTAssertEqual(g.map.ore[site],0); XCTAssertNotEqual(g.map.tile(cell),.water)
                    XCTAssertFalse(g.passable(cell,for:tank)); XCTAssertTrue(g.passable(cell,for:plane))
                    XCTAssertFalse(g.placement(plant,owner:0,origin:cell,deploying:true))
                    XCTAssertTrue(Battlefield.mineralField(around:site).contains { g.map.ore[$0] > 0 })
                }
            }
        }
    }

    func testDrillRefillsEmptyFieldsAndKeepsItsClockAcrossSave() throws {
        var s = MatchSettings(); s.opponents = [.russia]
        let g = Battle(s)
        g.map.ore = Array(repeating:0,count:g.map.ore.count); g.map.gems.removeAll()
        g.players[1].nextThink = 10000
        let site = try XCTUnwrap(g.map.oreMines.sorted().first)
        let field = Battlefield.mineralField(around:site), water = field[0], structure = field[1], gem = field[2]
        g.map.tiles[water] = .water
        _ = g.spawn("GAPILL",0,Battlefield.cell(structure).center)
        g.map.ore[gem] = 31; g.map.gems.insert(gem)
        let clock = Int(Double(Battlefield.growthInterval)/Battle.step)
        for _ in 1..<clock { g.tick() }
        XCTAssertEqual(g.map.ore.reduce(0,+),31)
        let resumed = try Battle.restore(JSONEncoder().encode(g))
        let wallet = g.players[0].credits
        for _ in 0..<(clock*4) { g.tick(); resumed.tick() }
        XCTAssertEqual(g.map.ore,resumed.map.ore)
        XCTAssertEqual(g.map.ore.reduce(0,+),31+4*g.map.oreMines.count*Battlefield.growthAmount)
        XCTAssertEqual(g.players[0].credits,wallet); XCTAssertEqual(g.map.ore[water],0)
        XCTAssertEqual(g.map.ore[structure],0); XCTAssertEqual(g.map.ore[site],0)
        XCTAssertEqual(g.map.ore[gem],31); XCTAssertEqual(g.map.gems,[gem])
        for cycle in 0..<500 { _ = g.map.replenish(at:site,cycle:cycle,occupied:g.occupied) }
        XCTAssertNil(g.map.replenish(at:site,cycle:501,occupied:g.occupied))
        let harvested = try XCTUnwrap(field.first { g.map.ore[$0] == Battlefield.goldCapacity })
        g.map.ore[harvested] = 0
        XCTAssertEqual(g.map.replenish(at:site,cycle:502,occupied:g.occupied),harvested)
        XCTAssertEqual(g.map.ore[harvested],Battlefield.growthAmount)
    }

    func testCentralDrillReplacesHarvestedGemsWithOrdinaryOre() throws {
        let g = Battle(MatchSettings()), central = Battlefield.index(Cell(26,26))
        let field = Battlefield.mineralField(around:central)
        XCTAssertTrue(field.allSatisfy(g.map.gems.contains))
        XCTAssertNil(g.map.replenish(at:central,cycle:1,occupied:g.occupied))
        let tile = try XCTUnwrap(field.first)
        let miner = g.spawn("CMIN",0,Battlefield.cell(tile).center)
        g.map.ore[tile] = 9; miner.intent = .harvest; miner.target = tile
        g.mine(miner,dt:Battle.step)
        XCTAssertEqual(miner.cargo,9); XCTAssertFalse(g.map.gems.contains(tile))
        XCTAssertEqual(g.map.replenish(at:central,cycle:2,occupied:g.occupied),tile)
        XCTAssertEqual(g.map.ore[tile],Battlefield.growthAmount)
        let restored = try Battle.restore(JSONEncoder().encode(g))
        XCTAssertFalse(restored.map.gems.contains(tile))
        XCTAssertEqual(restored.map.ore[tile],Battlefield.growthAmount)
    }

    func testBothMinersAutomaticallyFindRegrownOreAndDeliverMultipleLoads() throws {
        for nation in [Nation.usa,.russia] {
            var s = MatchSettings(); s.nation = nation; s.opponents = [.uk]; s.difficulty = .relaxed
            let g = Battle(s), player = g.players[0]
            g.players[1].nextThink = 10000
            XCTAssertTrue(g.deploy(g.owned(0,.mcv)[0].id))
            for role in [Role.power,.refinery] {
                let b = try XCTUnwrap(Catalog.byID[Catalog.id(role,nation)])
                XCTAssertTrue(g.enqueue(b.id,owner:0))
                for _ in 0..<300 where player.work(for:b).active?.ready != true { g.tick() }
                XCTAssertTrue(g.place(b.id,owner:0,origin:try XCTUnwrap(g.buildSite(b,owner:0))))
            }
            let miner = try XCTUnwrap(g.owned(0,.miner).first)
            g.map.ore = Array(repeating:0,count:g.map.ore.count); g.map.gems.removeAll()
            let wallet = player.credits
            var deposits = 0, collectedCargo = false
            for _ in 0..<960 where deposits < 3 {
                let last = player.mined
                g.tick()
                if miner.cargo > 0 { collectedCargo = true }
                if player.mined > last { deposits += 1 }
            }
            XCTAssertTrue(collectedCargo); XCTAssertEqual(deposits,3,nation.name)
            XCTAssertEqual(player.credits,wallet+player.mined)
        }
    }

    func testMinerSkipsUnreachableOreAndClosedRefinery() throws {
        let g = Battle(MatchSettings()), miner = g.spawn("HARV",0,Cell(7,8).center)
        g.map.tiles = Array(repeating:.grass,count:g.map.tiles.count)
        g.map.ore = Array(repeating:0,count:g.map.ore.count); g.map.gems.removeAll()
        let trapped = Cell(9,8), reachable = Cell(7,13)
        g.map.ore[Battlefield.index(trapped)] = 100; g.map.ore[Battlefield.index(reachable)] = 100
        for d in Battle.directions { g.map.tiles[Battlefield.index(Cell(trapped.x+d.x,trapped.y+d.y))] = .water }
        g.mine(miner,dt:Battle.step)
        XCTAssertEqual(miner.target,Battlefield.index(reachable))
        let sealed = g.spawn("NAREFN",0,Cell(13,8).center)
        let box = sealed.origin, size = sealed.spec.footprint
        for y in -1...size { for x in -1...size where x == -1 || y == -1 || x == size || y == size {
            g.map.tiles[Battlefield.index(Cell(box.x+x,box.y+y))] = .water
        }}
        _ = g.spawn("NAREFN",0,Cell(6,19).center)
        miner.cargo = 520; miner.stop()
        for _ in 0..<300 where g.players[0].mined == 0 { g.time += Battle.step; g.mine(miner,dt:Battle.step) }
        XCTAssertEqual(g.players[0].mined,520)
    }

    func testOldMinedOutMapGainsDrillsWithoutMovingBuildingsOrReplenishingOnLoad() throws {
        let g = Battle(MatchSettings()), central = Cell(26,26), index = Battlefield.index(central)
        let existing = g.spawn("GAPILL",0,central.center)
        var data = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(g)) as? [String:Any])
        var map = try XCTUnwrap(data["map"] as? [String:Any])
        map.removeValue(forKey:"oreMines"); map.removeValue(forKey:"gems")
        var ore = Array(repeating:0,count:g.map.ore.count)
        let oldDeposit = Battlefield.index(Cell(18,10)) // Original frontier home field
        ore[oldDeposit] = 137; map["ore"] = ore; data["map"] = map
        let restored = try Battle.restore(JSONSerialization.data(withJSONObject:data))
        XCTAssertEqual(restored.pieces[existing.id]?.pos,central.center)
        XCTAssertEqual(restored.map.oreMines.count,g.players.count+1)
        XCTAssertFalse(restored.map.oreMines.contains(index))
        XCTAssertEqual(restored.map.ore.reduce(0,+),137); XCTAssertEqual(restored.map.ore[oldDeposit],0)
        let second = try Battle.restore(JSONEncoder().encode(restored))
        XCTAssertEqual(restored.map.oreMines,second.map.oreMines); XCTAssertEqual(restored.map.ore,second.map.ore)
    }

    func testTenFixedMapsSupportEverySeatCountAndReachableResources() throws {
        XCTAssertEqual(Theater.allCases.count,10)
        var layouts = Set<[UInt8]>()
        for theater in Theater.allCases {
            let layout = theater.layout
            XCTAssertEqual(Set(layout.starts.map(\.cell)).count,8)
            XCTAssertTrue(layouts.insert(layout.tiles.map(\.rawValue)).inserted,theater.rawValue)
            for count in 1...8 {
                var s = MatchSettings(); s.theater = theater; s.fog = false; s.seed = UInt64(count)
                s.opponents = Array(repeating:.russia,count:count-1)
                let game = Battle(s), map = game.map
                let context = "\(theater.rawValue) \(count) 席"
                XCTAssertEqual(map.tiles,layout.tiles,context); XCTAssertEqual(map.ore,layout.ore,context)
                XCTAssertEqual(game.players.count,count); XCTAssertEqual(Set(map.seats.map(\.cell)).count,count)
                if count == 2 { XCTAssertEqual(map.seats[1],layout.starts[4]) }
                for p in game.pieces.values { XCTAssertTrue(game.passable(p.pos.cell,for:p.spec),context) }
                for i in game.players.indices {
                    XCTAssertTrue(game.deploy(game.owned(i,.mcv)[0].id),context)
                    XCTAssertNotNil(game.buildSite(Catalog.byID[Catalog.id(.power,game.players[i].nation)]!,owner:i),context)
                }
                let home = game.owned(0,.tank)[0]
                for i in game.players.indices {
                    let tank = game.owned(i,.tank)[0]
                    let ore = try XCTUnwrap(game.nearestMiningCell(from:tank.pos.cell,for:tank.spec,matching:{ map.ore[$0] > 0 }),context)
                    XCTAssertLessThan(map.seats[i].distance(ore.center),9,context)
                    if i > 0 { XCTAssertEqual(game.route(from:home.pos.cell,to:tank.pos.cell,for:home.spec).last,tank.pos.cell,context) }
                }
                game.tick(); XCTAssertEqual(game.outcome,.playing,context)
                let loaded = try Battle.restore(JSONEncoder().encode(game))
                XCTAssertEqual(loaded.map.theater,theater); XCTAssertEqual(loaded.map.seats,map.seats)
                XCTAssertEqual(loaded.players.count,count); XCTAssertEqual(loaded.map.oreMines,map.oreMines)
            }
        }
    }

    func testAllEightPortsOpenOntoNavigableWaterOnNavalMaps() throws {
        let naval = Theater.allCases.filter(\.allowsShipyards)
        XCTAssertEqual(naval.count,3)
        for theater in naval {
            var s = MatchSettings(); s.theater = theater; s.opponents = Array(repeating:.usa,count:7); s.fog = false
            let game = Battle(s)
            var fleet = [Piece]()
            for i in game.players.indices {
                let context = "\(theater.rawValue) 席位 \(i+1)"
                XCTAssertTrue(game.deploy(game.owned(i,.mcv)[0].id),context)
                for id in ["GAPOWR","GAREFN","GAYARD"] {
                    let b = try XCTUnwrap(Catalog.byID[id])
                    XCTAssertTrue(game.enqueue(id,owner:i),context)
                    game.processJobs(i,dt:b.duration/game.productionRate(i)+1)
                    let site = try XCTUnwrap(game.buildSite(b,owner:i),context)
                    XCTAssertTrue(game.place(id,owner:i,origin:site),context)
                }
                let ship = try XCTUnwrap(Catalog.byID["DEST"])
                XCTAssertTrue(game.enqueue(ship.id,owner:i),context)
                game.processJobs(i,dt:ship.duration/game.productionRate(i)+1)
                let launched = try XCTUnwrap(game.owned(i,.ship).first,context)
                XCTAssertEqual(game.map.tile(launched.pos.cell),.water,context); fleet.append(launched)
            }
            for other in fleet.dropFirst() {
                let route = game.route(from:fleet[0].pos.cell,to:other.pos.cell,for:fleet[0].spec)
                XCTAssertEqual(route.last,other.pos.cell,theater.rawValue)
            }
        }
    }

    func testSoloPracticeBuildsSavesAndKeepsPlaying() throws {
        var s = MatchSettings(); s.theater = .pass; s.opponents = []
        let g = Battle(s); XCTAssertTrue(g.isPractice)
        XCTAssertTrue(g.deploy(g.owned(0,.mcv)[0].id))
        for id in ["GAPOWR","GAREFN"] {
            let b = try XCTUnwrap(Catalog.byID[id]); XCTAssertTrue(g.enqueue(id,owner:0))
            for _ in 0..<320 where g.players[0].work(for:b).active?.ready != true { g.tick() }
            XCTAssertTrue(g.place(id,owner:0,origin:try XCTUnwrap(g.buildSite(b,owner:0))))
        }
        for _ in 0..<600 where g.players[0].mined == 0 { g.tick() }
        XCTAssertGreaterThan(g.players[0].mined,0); XCTAssertEqual(g.outcome,.playing)
        let restored = try Battle.restore(JSONEncoder().encode(g))
        XCTAssertEqual(restored.settings.opponents,[]); XCTAssertEqual(restored.players.count,1)
        restored.tick(); XCTAssertEqual(restored.outcome,.playing)
        for building in restored.owned(0).filter(\.spec.isBuilding) { restored.retire(building) }
        restored.checkOutcome(); XCTAssertEqual(restored.outcome,.practiceEnded)
    }

    func testWaterMovementAndBlockedCorners() throws {
        var s = MatchSettings(); s.theater = .gulf
        let g = Battle(s), tank = Catalog.byID["MTNK"]!, ship = Catalog.byID["DEST"]!
        XCTAssertTrue(g.passable(Cell(0,0),for:ship)); XCTAssertFalse(g.passable(Cell(0,0),for:tank))
        let start = Cell(25,25), end = Cell(29,25)
        g.occupied[Battlefield.index(Cell(26,25))] = 900
        let path = g.route(from:start,to:end,for:tank)
        XCTAssertEqual(path.last,end); XCTAssertFalse(path.contains(Cell(26,25)))
        XCTAssertFalse(path.isEmpty)
    }
}
