import XCTest

final class SkirmishUITests: XCTestCase {
    private func shot(_ name: String) {
        let item = XCTAttachment(screenshot:XCUIScreen.main.screenshot()); item.name = name
        item.lifetime = .keepAlways; add(item)
    }
    private func waitForStatus(_ prefix: String,on button: XCUIElement,timeout: TimeInterval = 3) -> Bool {
        let expected = XCTNSPredicateExpectation(predicate:NSPredicate(format:"value BEGINSWITH %@",prefix),object:button)
        return XCTWaiter.wait(for:[expected],timeout:timeout) == .completed
    }
    func testNativeSkirmish() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .landscapeLeft; app.launch()
        XCTAssertTrue(app.buttons["startMatch"].waitForExistence(timeout:15))
        let ownCountry = app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@", "玩家国家")).firstMatch
        ownCountry.tap(); app.buttons["美国"].tap()
        let remove = app.buttons["减少电脑"], addBot = app.buttons["增加电脑"]
        for _ in 0..<7 where remove.isEnabled { remove.tap() }
        addBot.tap()
        app.buttons["mapSettings"].tap()
        app.buttons["field-frontier"].tap(); app.buttons["简单"].tap(); app.buttons["$10000"].tap(); app.buttons["完成"].tap()
        shot("01-Lobby")
        for _ in 0..<7 where addBot.isEnabled { addBot.tap() }
        XCTAssertFalse(addBot.isEnabled)
        let seventh = app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@", "电脑 7，")).firstMatch
        XCTAssertTrue(seventh.isHittable)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(CGPoint(x:seventh.frame.midX,y:seventh.frame.midY)))
        shot("02-SevenOpponents")
        for _ in 0..<7 where remove.isEnabled { remove.tap() }
        XCTAssertFalse(remove.isEnabled)
        addBot.tap()
        app.buttons["mapSettings"].tap()
        XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout:5))
        app.buttons["完成"].tap()
        app.buttons["startMatch"].tap()
        if app.buttons["开始新对战"].waitForExistence(timeout:1.5) { app.buttons["开始新对战"].tap() }
        let deploy = app.buttons["展开基地"]
        XCTAssertTrue(deploy.waitForExistence(timeout:20))
        let field = app.descendants(matching:.any).matching(identifier:"battlefield").firstMatch
        XCTAssertTrue(field.exists)
        let screen = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(field.frame.width,screen.width-2)
        XCTAssertGreaterThanOrEqual(field.frame.height,screen.height-2)
        XCTAssertFalse(app.buttons["hideProduction"].exists)
        XCTAssertGreaterThanOrEqual(app.buttons["showProduction"].frame.height,43)
        app.buttons["展开雷达"].tap()
        XCTAssertTrue(app.staticTexts["雷达离线"].exists || app.descendants(matching:.any)["雷达离线"].exists)
        app.buttons["收起雷达"].tap()
        shot("03-Deployment")
        deploy.tap()
        let power = app.buttons["build-GAPOWR"]
        XCTAssertTrue(power.waitForExistence(timeout:8))
        XCTAssertFalse(app.buttons["minus-GAPOWR"].isEnabled)
        power.tap(); app.buttons["plus-GAPOWR"].tap()
        XCTAssertTrue(waitForStatus("待产 2，生产中",on:power))
        app.buttons["minus-GAPOWR"].tap()
        XCTAssertTrue(waitForStatus("待产 1，生产中",on:power))
        XCTAssertFalse(app.buttons["取消当前生产"].exists)
        XCTAssertTrue(waitForStatus("可部署，待产 0",on:power,timeout:28))
        app.buttons["plus-GAPOWR"].tap()
        XCTAssertTrue(waitForStatus("可部署，待产 1",on:power))
        app.buttons["minus-GAPOWR"].tap()
        XCTAssertTrue(waitForStatus("可部署，待产 0",on:power))
        let ready = power
        let tray = app.descendants(matching:.any).matching(identifier:"productionTray").firstMatch
        XCTAssertLessThan(tray.frame.height,screen.height*0.30)
        XCTAssertGreaterThanOrEqual(ready.frame.height,43)
        XCTAssertGreaterThanOrEqual(ready.frame.width,43)
        print("IronFront HUD screen=\(screen.size) field=\(field.frame.size) tray=\(tray.frame.size) ready=\(ready.frame.size)")
        ready.tap(); XCTAssertTrue(app.buttons["确认放置"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["hideProduction"].exists)
        shot("04-Placement"); app.buttons["确认放置"].tap()
        XCTAssertTrue(app.staticTexts["建筑就绪"].waitForExistence(timeout:5))
        app.buttons["hideProduction"].tap()
        app.buttons["unitOrders"].tap()
        XCTAssertTrue(app.buttons["维修"].isHittable)
        XCTAssertTrue(app.buttons["变卖"].isHittable)
        app.buttons["收起单位指令"].tap(); app.buttons["showProduction"].tap()
        for (id, name) in [("GAREFN","盟军矿石精炼厂"),("GAPILE","盟军兵营"),("AMRADR","空指部")] {
            app.buttons["build-"+id].tap()
            let place = app.buttons["部署"+name]; XCTAssertTrue(place.waitForExistence(timeout:40))
            place.tap(); app.buttons["确认放置"].tap()
        }
        app.buttons["步兵生产"].tap()
        let engineer = app.buttons["build-ENGINEER"], gi = app.buttons["build-E1"]
        engineer.tap(); gi.tap(); engineer.tap(); gi.tap()
        engineer.tap(); gi.tap(); engineer.tap(); gi.tap(); gi.tap()
        let bothActive = NSPredicate { _,_ in
            [gi,engineer].allSatisfy { ($0.value as? String)?.contains("生产中") == true }
        }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:bothActive,object:nil)],timeout:4),.completed)
        print("Concurrent production GI: \(gi.value ?? "") | Engineer: \(engineer.value ?? "")")
        shot("05-Production")
        XCTAssertTrue(waitForStatus("价格 200",on:gi,timeout:20))
        XCTAssertTrue(waitForStatus("价格 500",on:engineer,timeout:15))
        app.buttons["hideProduction"].tap()
        app.buttons["全军"].tap(); XCTAssertTrue(app.buttons["停止"].exists)
        app.buttons["展开雷达"].tap()
        let radar = app.descendants(matching:.any).matching(identifier:"radarMap").firstMatch
        XCTAssertTrue(radar.exists); shot("05-Battlefield")
        let original = try XCTUnwrap(radar.value as? String)
        radar.coordinate(withNormalizedOffset:CGVector(dx:0.78,dy:0.65)).tap()
        let moved = NSPredicate(format:"value != %@",original)
        XCTAssertTrue(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:moved,object:radar)],timeout:4) == .completed)
        let afterJump = try XCTUnwrap(radar.value as? String)
        field.coordinate(withNormalizedOffset:CGVector(dx:0.55,dy:0.49)).press(forDuration:0.1,
            thenDragTo:field.coordinate(withNormalizedOffset:CGVector(dx:0.38,dy:0.57)))
        XCTAssertTrue(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"value != %@",afterJump),object:radar)],timeout:4) == .completed)
        app.buttons["收起雷达"].tap(); app.buttons["基地定位"].tap()
        app.buttons["showProduction"].tap(); XCTAssertTrue(app.buttons["build-E1"].exists)
        app.buttons["hideProduction"].tap()
        app.buttons["单位指令"].tap(); app.buttons["记录当前所选"].tap()
        let advance = app.buttons["进攻移动"]
        advance.tap(); XCTAssertTrue(advance.isSelected)
        field.coordinate(withNormalizedOffset:CGVector(dx:0.19,dy:0.62)).tap()
        XCTAssertTrue(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"selected == false"),object:advance)],timeout:2) == .completed)
        app.buttons["暂停对战"].tap(); app.buttons["保存并返回大厅"].tap()
        XCTAssertTrue(app.buttons["resumeMatch"].waitForExistence(timeout:5))
        app.terminate(); app.launch(); app.buttons["resumeMatch"].tap()
        XCTAssertTrue(app.buttons["暂停对战"].waitForExistence(timeout:12))
        app.buttons["暂停对战"].tap(); app.buttons["认输"].tap()
        app.buttons["确认认输"].tap()
        XCTAssertTrue(app.staticTexts["战斗失利"].waitForExistence(timeout:5)); shot("06-Result")
        app.buttons["返回对战大厅"].tap()
        XCTAssertTrue(app.buttons["startMatch"].waitForExistence(timeout:5)); XCTAssertFalse(app.buttons["resumeMatch"].exists)
    }

    func testFundingStopsRefundsAndResumesOnOreDelivery() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .landscapeLeft; app.launch()
        app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@", "玩家国家")).firstMatch.tap()
        app.buttons["美国"].tap()
        let remove = app.buttons["减少电脑"]
        for _ in 0..<7 where remove.isEnabled { remove.tap() }
        app.buttons["mapSettings"].tap()
        app.buttons["field-frontier"].tap(); app.buttons["简单"].tap(); app.buttons["$5000"].tap()
        app.buttons["完成"].tap(); app.buttons["startMatch"].tap()
        if app.buttons["开始新对战"].waitForExistence(timeout:1) { app.buttons["开始新对战"].tap() }
        app.buttons["展开基地"].tap()
        let plant = app.buttons["build-GAPOWR"], barracks = app.buttons["build-GAPILE"]
        let refinery = app.buttons["build-GAREFN"]
        plant.tap(); XCTAssertTrue(waitForStatus("可部署",on:plant,timeout:20))
        plant.tap(); app.buttons["确认放置"].tap()
        plant.tap(); barracks.tap(); refinery.tap()
        XCTAssertTrue(waitForStatus("可部署",on:barracks,timeout:15))
        barracks.tap(); app.buttons["确认放置"].tap()
        XCTAssertTrue(waitForStatus("可部署",on:refinery,timeout:30))

        app.buttons["步兵生产"].tap()
        let engineer = app.buttons["build-ENGINEER"], gi = app.buttons["build-E1"]
        engineer.tap(); app.buttons["plus-ENGINEER"].tap()
        let stopped = "待产 1，等待资金 80%"
        XCTAssertTrue(waitForStatus(stopped,on:engineer,timeout:15))
        gi.tap()
        XCTAssertTrue(waitForStatus("待产 1，等待资金 0%",on:gi))
        XCTAssertTrue(waitForStatus(stopped,on:engineer))
        shot("10-AwaitingFunds")
        app.buttons["plus-ENGINEER"].tap()
        XCTAssertTrue(waitForStatus("待产 2，等待资金 80%",on:engineer))
        app.buttons["minus-ENGINEER"].tap()
        XCTAssertTrue(waitForStatus(stopped,on:engineer))
        app.buttons["minus-E1"].tap(); app.buttons["minus-ENGINEER"].tap()
        XCTAssertTrue(app.staticTexts["已取消 1 件工程师，返还 $400"].waitForExistence(timeout:3))
        XCTAssertTrue(app.descendants(matching:.any).matching(NSPredicate(format:"label == %@", "资金 400")).firstMatch.exists)
        shot("11-PartialRefund")
        engineer.tap(); XCTAssertTrue(waitForStatus(stopped,on:engineer,timeout:10))
        app.buttons["plus-ENGINEER"].tap()
        engineer.press(forDuration:0.7)
        XCTAssertTrue(app.staticTexts["已取消 1 件工程师，返还 $400"].waitForExistence(timeout:3))
        XCTAssertTrue(waitForStatus(stopped,on:engineer,timeout:10))

        // Deploy the completed refinery. Its first real miner delivery pays the last $100.
        app.buttons["建筑生产"].tap(); refinery.tap(); app.buttons["确认放置"].tap()
        app.buttons["步兵生产"].tap()
        XCTAssertTrue(waitForStatus("价格 500",on:engineer,timeout:36))
    }

    func testItemProgressPausesAndRestores() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .landscapeLeft; app.launch()
        app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@", "玩家国家")).firstMatch.tap()
        app.buttons["美国"].tap(); app.buttons["startMatch"].tap()
        if app.buttons["开始新对战"].waitForExistence(timeout:1) {app.buttons["开始新对战"].tap()}
        app.buttons["展开基地"].tap()
        let plant = app.buttons["build-GAPOWR"]; plant.tap()
        XCTAssertTrue(waitForStatus("可部署",on:plant,timeout:25)); plant.tap(); app.buttons["确认放置"].tap()

        let refinery = app.buttons["build-GAREFN"]
        refinery.tap(); refinery.tap()
        XCTAssertTrue(waitForStatus("待产 2，生产中",on:refinery))
        func percent() throws -> Int {
            let value = try XCTUnwrap(refinery.value as? String)
            return try XCTUnwrap(value.split(separator:" ").last.flatMap { Int($0.dropLast()) })
        }
        let before = try percent()
        app.buttons["暂停对战"].tap()
        // Four wall-clock seconds would advance this 17-second job by 23 percentage points.
        Thread.sleep(forTimeInterval:4.0)
        app.buttons["继续战斗"].tap()
        let after = try percent()
        XCTAssertGreaterThanOrEqual(after,before); XCTAssertLessThan(after-before,13)
        app.buttons["暂停对战"].tap(); app.buttons["保存并返回大厅"].tap()
        app.terminate(); app.launch(); app.buttons["resumeMatch"].tap(); app.buttons["showProduction"].tap()
        XCTAssertTrue(waitForStatus("待产 2，生产中",on:refinery))
        let restored = try percent()
        XCTAssertGreaterThanOrEqual(restored,after); XCTAssertLessThan(restored-after,20)
        print("Production clock before pause \(before)%, after resume \(after)%, after loading \(restored)%")
    }

    func testOreMineAndAutomaticRefineryDeliveries() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .landscapeLeft; app.launch()
        app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@", "玩家国家")).firstMatch.tap()
        app.buttons["美国"].tap()
        let remove = app.buttons["减少电脑"]
        for _ in 0..<7 where remove.isEnabled { remove.tap() }
        app.buttons["mapSettings"].tap()
        app.buttons["field-frontier"].tap(); app.buttons["简单"].tap(); app.buttons["$10000"].tap()
        app.buttons["完成"].tap(); app.buttons["startMatch"].tap()
        if app.buttons["开始新对战"].waitForExistence(timeout:1) { app.buttons["开始新对战"].tap() }
        app.buttons["展开基地"].tap()
        for id in ["GAPOWR","GAREFN"] {
            let key = app.buttons["build-"+id]; key.tap()
            XCTAssertTrue(waitForStatus("可部署",on:key,timeout:35))
            key.tap(); app.buttons["确认放置"].tap()
        }
        app.buttons["hideProduction"].tap(); app.buttons["基地定位"].tap()
        let field = app.descendants(matching:.any).matching(identifier:"battlefield").firstMatch
        let center = field.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5))
        // Home and its right-hand ore field are generated at the same coordinates on every frontier seed.
        center.withOffset(CGVector(dx:204,dy:-38)).tap()
        XCTAssertTrue(app.staticTexts["矿井 · 每 3 秒为周围矿田补充金矿"].waitForExistence(timeout:3))
        center.press(forDuration:0.1,thenDragTo:center.withOffset(CGVector(dx:-127,dy:16)))
        shot("12-OreMine")
        let income = app.descendants(matching:.any).matching(NSPredicate(format:"label BEGINSWITH %@", "资金 ")).firstMatch
        func balanceReaches(_ amount: Int) -> Bool {
            let paid = NSPredicate { _,_ in
                guard let balance = Int(income.label.filter(\.isNumber)) else { return false }
                return balance >= amount
            }
            return XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:paid,object:nil)],timeout:40) == .completed
        }
        // The miner receives no player orders. Each full load adds 340 to the 7200 left after construction.
        XCTAssertTrue(balanceReaches(7540))
        shot("12-AutomaticOreHarvest")
        XCTAssertTrue(balanceReaches(7880))
    }

    func testFieldTapsAndRotation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .landscapeLeft; app.launch()
        app.buttons["startMatch"].tap()
        if app.buttons["开始新对战"].waitForExistence(timeout:1) {app.buttons["开始新对战"].tap()}
        XCTAssertTrue(app.buttons["展开基地"].waitForExistence(timeout:12))
        let field = app.descendants(matching:.any).matching(identifier:"battlefield").firstMatch
        let unit = app.buttons["unitOrders"]
        // Both starting tanks flank the MCV. This offset is the left tank at the initial camera scale.
        let tank = field.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).withOffset(CGVector(dx:-107,dy:-1))
        tank.tap()
        XCTAssertTrue(app.buttons["进攻移动"].waitForExistence(timeout:2))
        let initialName = try XCTUnwrap(unit.value as? String)
        XCTAssertTrue(initialName.contains("坦克"))
        tank.doubleTap()
        XCTAssertTrue(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"value == %@", "2 个单位"),object:unit)],timeout:3) == .completed)
        let attack = app.buttons["进攻移动"]; attack.tap()
        XCTAssertTrue(attack.isSelected)
        field.coordinate(withNormalizedOffset:CGVector(dx:0.22,dy:0.60)).tap()
        XCTAssertTrue(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"selected == false"),object:attack)],timeout:2) == .completed)
        let opener = app.buttons["showProduction"]
        opener.tap()
        let tray = app.descendants(matching:.any).matching(identifier:"productionTray").firstMatch
        XCTAssertTrue(tray.waitForExistence(timeout:5))
        XCUIDevice.shared.orientation = .landscapeRight
        shot("09-RotatedProduction")
        let settled = NSPredicate { _,_ in
            app.windows.firstMatch.frame.insetBy(dx:-1,dy:-1).contains(tray.frame)
        }
        let result = XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:settled,object:nil)],timeout:4)
        let window = app.windows.firstMatch.frame
        print("Rotated console window=\(window) tray=\(tray.frame) field=\(field.frame)")
        XCTAssertEqual(result,.completed)
        XCTAssertTrue(app.buttons["hideProduction"].isHittable)
        XCTAssertGreaterThanOrEqual(field.frame.width,window.width-2)
        if window.height > 510 { XCTAssertGreaterThan(tray.frame.height,130) }
        XCUIDevice.shared.orientation = .landscapeLeft
        app.buttons["hideProduction"].tap()
        XCTAssertTrue(opener.waitForExistence(timeout:4))
        app.buttons["暂停对战"].tap(); app.buttons["保存并返回大厅"].tap()
    }

    func testTenMapsSoloPracticeAndEightSeatLaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .landscapeLeft; app.launch()
        app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@", "玩家国家")).firstMatch.tap()
        app.buttons["美国"].tap()
        let remove = app.buttons["减少电脑"], add = app.buttons["增加电脑"]
        XCTAssertTrue(remove.waitForExistence(timeout:12))
        for _ in 0..<7 where remove.isEnabled { remove.tap() }
        XCTAssertFalse(remove.isEnabled)
        let seats = app.descendants(matching:.any).matching(identifier:"seatCount").firstMatch
        XCTAssertEqual(seats.value as? String,"1")
        app.buttons["mapSettings"].tap()
        let maps = ["frontier","gulf","frost","rivers","basin","pass","lakes","isles","junction","strait"]
        func choose(_ code: String) {
            let button = app.buttons["field-"+code], list = app.scrollViews["mapList"].firstMatch
            for _ in 0..<5 where !button.isHittable { list.swipeUp() }
            XCTAssertTrue(button.isHittable,code)
            button.tap(); XCTAssertTrue(button.isSelected,code)
        }
        for map in maps { choose(map) }
        shot("15-TenMaps"); app.buttons["完成"].tap()
        XCTAssertEqual(app.buttons["mapSettings"].value as? String,"裂岸海峡")
        app.buttons["startMatch"].tap()
        if app.buttons["开始新对战"].waitForExistence(timeout:1) { app.buttons["开始新对战"].tap() }
        XCTAssertTrue(app.staticTexts["自由演练"].waitForExistence(timeout:12))
        app.buttons["展开基地"].tap(); app.buttons["build-GAPOWR"].tap()
        app.buttons["暂停对战"].tap()
        XCTAssertTrue(app.staticTexts["裂岸海峡"].exists)
        app.buttons["保存并返回大厅"].tap()
        app.terminate(); app.launch(); app.buttons["resumeMatch"].tap()
        XCTAssertTrue(app.staticTexts["自由演练"].waitForExistence(timeout:12))
        app.buttons["暂停对战"].tap(); app.buttons["结束演练"].tap(); app.buttons["确认结束演练"].tap()
        XCTAssertTrue(app.staticTexts["演练结束"].waitForExistence(timeout:5)); app.buttons["返回对战大厅"].tap()

        for _ in 0..<7 { add.tap() }
        XCTAssertFalse(add.isEnabled); XCTAssertEqual(seats.value as? String,"8")
        app.buttons["mapSettings"].tap(); choose("isles"); app.buttons["完成"].tap()
        app.buttons["startMatch"].tap()
        XCTAssertTrue(app.staticTexts["8 国存活"].waitForExistence(timeout:15))
        app.buttons["展开基地"].tap(); app.buttons["暂停对战"].tap()
        XCTAssertTrue(app.staticTexts["潮汐群岛"].exists)
        app.buttons["保存并返回大厅"].tap()
    }

    func testSevenComputersFightOnDevice() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .landscapeLeft; app.launch()
        let addBot = app.buttons["增加电脑"]
        XCTAssertTrue(addBot.waitForExistence(timeout:12))
        for _ in 0..<7 where addBot.isEnabled { addBot.tap() }
        XCTAssertFalse(addBot.isEnabled)
        let player = app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@", "玩家国家")).firstMatch
        player.tap(); app.buttons["伊拉克"].tap()
        let firstBot = app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@", "电脑 1，")).firstMatch
        firstBot.tap(); app.buttons["英国"].tap()
        app.buttons["mapSettings"].tap()
        app.buttons["field-gulf"].tap()
        app.buttons["困难"].tap(); app.buttons["完成"].tap()
        app.buttons["startMatch"].tap()
        if app.buttons["开始新对战"].waitForExistence(timeout:1.2) { app.buttons["开始新对战"].tap() }
        XCTAssertTrue(app.staticTexts["8 国存活"].waitForExistence(timeout:20))
        app.buttons["展开基地"].tap()
        XCTAssertTrue(app.buttons["build-NAPOWR"].exists)
        app.buttons["hideProduction"].tap(); shot("07-EightCountries")
        // Let the running simulation resolve through combat against an undefended starting army.
        let defeated = app.staticTexts["战斗失利"]
        XCTAssertTrue(defeated.waitForExistence(timeout:260))
        shot("08-CombatResult")
        app.buttons["返回对战大厅"].tap()
    }
}
