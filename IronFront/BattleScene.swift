import SpriteKit
import UIKit

private final class TokenNode: SKNode {
    let art = SKSpriteNode(), ring = SKShapeNode(), health = SKSpriteNode(color:.black,size:.zero)
    let fill = SKSpriteNode(color:.green,size:.zero), team = SKSpriteNode(color:.white,size:.zero)
    var textureKey = "", hasPosition = false
    override init() {
        super.init()
        ring.fillColor = .clear; ring.lineWidth = 1.6; ring.zPosition = -0.15
        addChild(ring); addChild(art); addChild(team); addChild(health); health.addChild(fill)
        art.anchorPoint = CGPoint(x:0.5,y:0.18); health.zPosition = 0.3; fill.anchorPoint.x = 0
        health.anchorPoint.x = 0; team.zPosition = 0.2
    }
    required init?(coder: NSCoder) { fatalError() }
}

final class BattleScene: SKScene {
    weak var session: GameSession?
    private let lens = SKCameraNode(), field = SKNode(), ghost = SKShapeNode(), box = SKShapeNode()
    private var fogPlane: SKSpriteNode?
    private var tokens: [Int:TokenNode] = [:], decorations: [Int:SKSpriteNode] = [:]
    private var textures: [String:SKTexture] = [:]
    private var previous: TimeInterval = 0, accumulator = 0.0, lastFlash = 0, lastRevision = -1
    /// Time already accumulated toward the next fixed simulation step.
    var substepTime: Double { min(Battle.step, max(0, accumulator)) }
    private var oldFog: [UInt8] = [], lastAudio = 0.0
    private var lastPlacement: String = ""
    init(_ session: GameSession) {
        self.session = session; super.init(size:CGSize(width:600,height:370))
        scaleMode = .resizeFill; backgroundColor = UIColor(red:0.047,green:0.080,blue:0.08,alpha:1)
        camera = lens; addChild(lens); addChild(field); addChild(ghost); addChild(box)
        ghost.zPosition = 4050; ghost.lineWidth = 2; box.zPosition = 4060
        box.strokeColor = .systemMint; box.fillColor = UIColor.systemMint.withAlphaComponent(0.12)
        guard let g = session.game else { return }
        field.addChild(Cartography.sheet(Cartography.ground(g.map),z:-10))
        makeScenery(g)
        if g.settings.fog {
            let fog = Cartography.sheet(Cartography.fog(g),z:3500); field.addChild(fog); fogPlane = fog.children.first as? SKSpriteNode
        }
        focus(g.owned(0,.yard).first?.pos ?? g.owned(0,.mcv).first?.pos ?? g.map.seats[0])
        lens.setScale(0.94); session.scene = self
    }
    required init?(coder: NSCoder) { fatalError() }
    private func texture(_ key: String) -> SKTexture? {
        if let cached = textures[key] { return cached }
        guard let img = Pictures.get(key) else { return nil }
        let tex = SKTexture(image:img); tex.filteringMode = .linear; textures[key] = tex; return tex
    }
    private func makeScenery(_ g: Battle) {
        let n = Battlefield.size
        let fields = Set(g.map.oreMines.flatMap(Battlefield.mineralField(around:)))
        var rng = RandomStream(state:g.map.seed ^ 0x63A5)
        let climate = g.map.theater.layout.climate
        for i in g.map.tiles.indices {
            let cell = Cell(i%n,i/n), p = cell.center, roll = rng.next()
            let mine = g.map.oreMines.contains(i), ore = !mine && (g.map.ore[i] > 0 || fields.contains(i))
            let ground = g.map.tiles[i]
            let outcrop = ground == .ridge && roll < 0.28
            if !mine && !ore && !outcrop && (roll > (climate == .taiga ? 0.25 : 0.12) ||
                ground != .grass || g.map.seats.contains(where:{$0.distance(p)<4.6})) { continue }
            let key: String, width: CGFloat
            if mine { key = "ore-drill"; width = 39 }
            else if ore { key = g.map.gems.contains(i) ? "gem" : "gold"; width = 26+CGFloat(rng.next())*7 }
            else if outcrop || roll < 0.025 || climate == .desert || climate == .salt { key = "rock"; width = 23+CGFloat(rng.next())*13 }
            else {
                switch climate {
                case .snow: key = "snowpine"
                case .taiga: key = roll < 0.12 ? "pines" : "pine"
                default: key = ["pine","pines","birch","olive"][Int(rng.next()*4)]
                }
                width = 23+CGFloat(rng.next())*20
            }
            guard let tex = texture(key) else { continue }
            let node = SKSpriteNode(texture:tex), s = tex.size()
            node.size = CGSize(width:width,height:width*s.height/s.width); node.anchorPoint = CGPoint(x:0.5,y:ore ? 0.32 : 0.12)
            node.position = Cartography.project(mine ? p : p.offset((rng.next()-0.5)*0.5,(rng.next()-0.5)*0.5))
            node.zPosition = 100 - node.position.y*0.5 - (ore ? 10 : 0)
            node.name = mine ? "mine" : (ore ? "ore" : "scenery")
            node.isHidden = (ore || mine) && g.explored[i] == 0
            field.addChild(node); decorations[i] = node
        }
    }
    func focus(_ p: Point) { lens.position = Cartography.project(p); lens.position.y += 11 }
    var radarViewport: [Point] {
        guard let view else { return [] }
        let r = view.bounds
        let screen = [CGPoint(x:r.minX,y:r.minY),CGPoint(x:r.maxX,y:r.minY),
                      CGPoint(x:r.maxX,y:r.maxY),CGPoint(x:r.minX,y:r.maxY)]
        return screen.map { Cartography.unproject(convertPoint(fromView:$0)) }
    }
    func pan(_ delta: CGPoint) {
        lens.position.x -= delta.x*lens.xScale; lens.position.y += delta.y*lens.yScale; clampCamera()
    }
    private func clampCamera() {
        let p = Cartography.unproject(lens.position), maxValue = Double(Battlefield.size)-0.5
        lens.position = Cartography.project(Point(max(0.5,min(maxValue,p.x)),max(0.5,min(maxValue,p.y))))
    }
    func zoom(_ amount: CGFloat, at point: CGPoint) {
        let before = convertPoint(fromView:point)
        lens.setScale(min(2.15,max(0.5,lens.xScale/amount)))
        let after = convertPoint(fromView:point)
        lens.position.x += before.x-after.x; lens.position.y += before.y-after.y; clampCamera()
    }
    func pointTap(_ location: CGPoint, double: Bool) {
        guard let session, let g = session.game else { return }
        let at = convertPoint(fromView:location)
        let hit = tokens.compactMap { id,node -> (Int,CGFloat)? in
            guard !node.isHidden, let p = g.pieces[id] else { return nil }
            let local = node.convert(at,from:self), pad: CGFloat = p.spec.isBuilding ? 0 : 6*lens.xScale
            let r = node.art.frame.insetBy(dx:-pad,dy:-pad)
            return r.contains(local) ? (id,node.zPosition) : nil
        }.max(by:{$0.1<$1.1})?.0
        let usingGround = session.placementBlueprint != nil || session.support != nil
        if !usingGround, hit == nil, !session.selection.contains(where:{ g.pieces[$0]?.spec.isBuilding == false }),
           g.map.oreMines.contains(where:{ i in
               guard g.visible[i] != 0, let drill = decorations[i] else { return false }
               return drill.frame.contains(field.convert(at,from:self))
           }) {
            session.say("矿井 · 每 \(Battlefield.growthInterval) 秒为周围矿田补充金矿"); return
        }
        let p = usingGround ? Cartography.unproject(at) : (hit.flatMap { g.pieces[$0]?.pos } ?? Cartography.unproject(at))
        session.tap(p,hit:hit,double:double)
    }
    func selectBox(_ start: CGPoint, _ end: CGPoint, done: Bool) {
        let a = convertPoint(fromView:start), b = convertPoint(fromView:end)
        let rect = CGRect(x:min(a.x,b.x),y:min(a.y,b.y),width:abs(a.x-b.x),height:abs(a.y-b.y))
        box.path = CGPath(rect:rect,transform:nil); box.isHidden = done
        if done, let g = session?.game {
            session?.select(g.owned(0).filter { !$0.spec.isBuilding && rect.contains(Cartography.project($0.pos)) }.map(\.id))
            session?.boxSelect = false
        }
    }
    /// Four arcs with a registration mark on each axis keep the unit footprint visible on bright terrain.
    private func reticle(width: CGFloat, height: CGFloat) -> CGPath {
        let arcs = CGMutablePath()
        for quadrant in 0..<4 {
            let axis = CGFloat(quadrant) * .pi / 2
            let first = axis + 0.15, last = axis + .pi/2 - 0.15
            arcs.move(to:CGPoint(x:cos(first),y:sin(first)))
            arcs.addArc(center:.zero,radius:1,startAngle:first,endAngle:last,clockwise:false)
        }
        let shape = CGMutablePath()
        shape.addPath(arcs,transform:CGAffineTransform(scaleX:width/2,y:height/2))
        for quadrant in 0..<4 {
            let axis = CGFloat(quadrant) * .pi / 2
            shape.move(to:CGPoint(x:cos(axis)*width/2,y:sin(axis)*height/2))
            shape.addLine(to:CGPoint(x:cos(axis)*(width/2+3),y:sin(axis)*(height/2+3)))
        }
        return shape
    }
    func ping(_ p: Point, hostile: Bool) {
        let shape = SKShapeNode(path:reticle(width:34,height:18))
        shape.strokeColor = hostile ? .systemOrange : .systemMint; shape.lineWidth = 1.8
        shape.position = Cartography.project(p); shape.zPosition = 4000; addChild(shape)
        let mark = UIAccessibility.isReduceMotionEnabled ? SKAction.wait(forDuration:0.2) : SKAction.scale(to:0.65,duration:0.25)
        shape.run(.sequence([mark,.fadeOut(withDuration:0.2),.removeFromParent()]))
    }
    override func update(_ currentTime: TimeInterval) {
        guard let s = session, let g = s.game else { return }
        let elapsed = previous == 0 ? 0 : min(0.25,max(0,currentTime-previous)); previous = currentTime
        if !s.paused && g.outcome == .playing {
            accumulator += elapsed
            while accumulator >= Battle.step { s.step(); accumulator -= Battle.step }
        }
        let alpha = min(1,CGFloat(elapsed*13))
        for id in tokens.keys where g.pieces[id] == nil { tokens.removeValue(forKey:id)?.removeFromParent() }
        for p in g.pieces.values {
            let node: TokenNode
            if let existing = tokens[p.id] { node = existing } else { node = TokenNode(); field.addChild(node); tokens[p.id] = node }
            node.isHidden = p.owner != 0 && !g.isVisible(p.pos)
            guard !node.isHidden else { continue }
            updateToken(node,p,selected:s.selection.contains(p.id),alpha:alpha,time:g.time)
        }
        if lastRevision != g.revision {
            let firstFrame = lastRevision < 0
            lastRevision = g.revision
            if fogPlane != nil && oldFog != g.visible { fogPlane?.texture = Cartography.fog(g); oldFog = g.visible }
            for (i,node) in decorations {
                if node.name == "ore" {
                    if g.explored[i] == 0 { node.isHidden = true; continue }
                    guard firstFrame || g.visible[i] != 0 else { continue }
                    let amount = g.map.ore[i]
                    node.isHidden = amount == 0 || g.occupied[i] != nil
                    if !node.isHidden {
                        node.texture = texture(g.map.gems.contains(i) ? "gem" : "gold")
                        node.setScale(0.38 + 0.62 * sqrt(min(1,CGFloat(amount)/CGFloat(Battlefield.goldCapacity))))
                    }
                } else { node.isHidden = g.occupied[i] != nil || (node.name == "mine" && g.explored[i] == 0) }
            }
        }
        for f in g.flash where f.id > lastFlash {
            lastFlash = f.id
            if g.isVisible(f.from) || g.isVisible(f.to) { showEffect(f) }
        }
        showPlacement(s,g)
    }
    private func updateToken(_ node: TokenNode, _ p: Piece, selected: Bool, alpha: CGFloat, time: Double) {
        let b = p.spec, dx = cos(p.direction), dy = sin(p.direction)
        let rear = !b.isBuilding && dx+dy < -0.05
        let rearKey = b.id+"-rear"
        let key = rear && (b.lane != .infantry || ["SHK","DESO","JUMPJET"].contains(b.id)) ? rearKey : b.id
        if node.textureKey != key {
            node.textureKey = key
            if let tex = texture(key) ?? texture(b.id) {
                node.art.texture = tex; let image = tex.size()
                let width: CGFloat
                if b.isBuilding { width = CGFloat(b.footprint)*44 + (b.footprint == 1 ? 8 : 0) }
                else if b.lane == .infantry { width = b.role == .dog ? 22 : max(13,24*image.width/image.height) }
                else if b.flies || b.lane == .naval { width = b.id == "ZEP" || b.lane == .naval ? 68 : 53 }
                else { width = b.role == .mcv || b.role == .miner ? 53 : 43 }
                node.art.size = CGSize(width:width,height:width*image.height/image.width)
                node.art.anchorPoint.y = b.isBuilding ? min(0.44,CGFloat(b.footprint)*11.5/node.art.size.height) : 0.22
                let ringW = b.isBuilding ? width*0.93 : max(20,width*0.80)
                node.ring.path = reticle(width:ringW,height:ringW/2)
                node.health.size = CGSize(width:max(18,min(48,width*0.65)),height:3.8)
                node.health.position = CGPoint(x:-node.health.size.width/2,y:node.art.size.height*(1-node.art.anchorPoint.y)+4)
            }
        }
        let position = Cartography.project(p.pos)
        if !node.hasPosition || hypot(position.x-node.position.x,position.y-node.position.y)>100 {
            node.position = position; node.hasPosition = true
        } else { node.position.x += (position.x-node.position.x)*alpha; node.position.y += (position.y-node.position.y)*alpha }
        node.zPosition = 100-node.position.y*0.5+(b.flies ? 80 : 0)
        let frontFacesRight = !rear && ["HTNK","HTK","APOC","TTNK","SUB"].contains(b.id)
        node.art.xScale = b.isBuilding || ((dx-dy < 0) != frontFacesRight) ? 1 : -1
        node.art.position.y = b.flies ? 13+sin(time*2+Double(p.id))*1.8 : 0
        if b.lane == .infantry && p.waypoint < p.path.count { node.art.position.y += abs(sin(time*11+Double(p.id)))*1.8 }
        let tint = Palette.team[p.owner], fraction = max(0,min(1,p.hp/Double(b.stats.hp)))
        node.ring.isHidden = !selected; node.ring.strokeColor = .systemMint
        node.health.isHidden = !selected && fraction > 0.985
        node.fill.color = fraction > 0.55 ? .systemGreen : (fraction > 0.28 ? .systemYellow : .systemRed)
        node.fill.size = CGSize(width:(node.health.size.width-2)*fraction,height:2.2); node.fill.position = CGPoint(x:1,y:0)
        node.team.color = tint; node.team.size = CGSize(width:b.isBuilding ? 12 : 6,height:2.4)
        node.team.position = CGPoint(x:0,y:-(b.isBuilding ? CGFloat(b.footprint)*9 : 4))
    }
    private func showPlacement(_ session: GameSession, _ game: Battle) {
        guard let b = session.placementBlueprint, let c = session.site else {
            ghost.isHidden = true; lastPlacement = ""; return
        }
        let good = game.placement(b,owner:0,origin:c), key = "\(b.id)/\(c.x)/\(c.y)/\(good)"
        guard key != lastPlacement else { return }
        ghost.removeAllChildren(); lastPlacement = key; ghost.isHidden = false
        let size = Double(b.footprint), start = Point(Double(c.x),Double(c.y)), path = CGMutablePath()
        path.move(to:Cartography.project(start)); for v in [start.offset(size,0),start.offset(size,size),start.offset(0,size)] { path.addLine(to:Cartography.project(v)) }; path.closeSubpath()
        ghost.path = path; ghost.strokeColor = good ? .systemMint : .systemRed; ghost.fillColor = ghost.strokeColor.withAlphaComponent(0.18)
        let grid = CGMutablePath()
        for i in 1..<b.footprint {
            let d = Double(i)
            grid.move(to:Cartography.project(start.offset(d,0))); grid.addLine(to:Cartography.project(start.offset(d,size)))
            grid.move(to:Cartography.project(start.offset(0,d))); grid.addLine(to:Cartography.project(start.offset(size,d)))
        }
        if !grid.isEmpty {
            let cells = SKShapeNode(path:grid); cells.strokeColor = ghost.strokeColor.withAlphaComponent(0.80)
            cells.lineWidth = 1.0; cells.zPosition = 1; ghost.addChild(cells)
        }
        if let tex = texture(b.id) {
            let image = SKSpriteNode(texture:tex), w = CGFloat(b.footprint)*44
            image.size = CGSize(width:w,height:w*tex.size().height/tex.size().width); image.anchorPoint.y = CGFloat(b.footprint)*11.5/image.size.height
            image.position = Cartography.project(start.offset(size/2,size/2)); image.alpha = 0.55; ghost.addChild(image)
        }
    }
    private func showEffect(_ f: Flash) {
        let a = Cartography.project(f.from), b = Cartography.project(f.to)
        if f.style == "ore" {
            guard !UIAccessibility.isReduceMotionEnabled, session?.game?.isVisible(f.to) == true else { return }
            if let rig = decorations[Battlefield.index(f.from.cell)] {
                let stroke = SKAction.sequence([.scaleY(to:0.975,duration:0.12),.scaleY(to:1,duration:0.22)])
                rig.run(stroke,withKey:"drilling")
            }
            for offset in [-3,0,3] {
                let dx = CGFloat(offset), chip = SKShapeNode(circleOfRadius:1.35)
                chip.fillColor = UIColor(red:0.95,green:0.72,blue:0.29,alpha:1); chip.strokeColor = .clear
                let arc = CGMutablePath()
                arc.move(to:CGPoint(x:a.x,y:a.y+6))
                arc.addQuadCurve(to:CGPoint(x:b.x+dx,y:b.y+2),control:CGPoint(x:(a.x+b.x)/2+dx,y:max(a.y,b.y)+13+abs(dx)))
                chip.zPosition = 125 - min(a.y,b.y)*0.5; field.addChild(chip)
                chip.run(.sequence([.follow(arc,asOffset:false,orientToPath:false,duration:0.32),.fadeOut(withDuration:0.12),.removeFromParent()]))
            }
            return
        }
        let shape: SKShapeNode
        if ["burst","blast","storm","drop"].contains(f.style) {
            let large = f.style == "blast" || f.style == "storm"
            shape = SKShapeNode(circleOfRadius:large ? 32 : 8); shape.position = b
            shape.fillColor = (f.style == "storm" ? UIColor.systemTeal : .systemOrange).withAlphaComponent(0.65)
            shape.strokeColor = f.style == "drop" ? .systemMint : .systemYellow
            shape.run(.scale(to:large ? 2.8 : 1.8,duration:0.30))
        } else {
            let path = CGMutablePath(); path.move(to:CGPoint(x:a.x,y:a.y+9))
            if f.style == "arc" { path.addLine(to:CGPoint(x:(a.x+b.x)/2+5,y:(a.y+b.y)/2+15)) }
            path.addLine(to:CGPoint(x:b.x,y:b.y+7)); shape = SKShapeNode(path:path)
            shape.strokeColor = f.style == "arc" ? .cyan : (f.style == "prism" ? .systemPurple : (f.style == "rad" ? .systemGreen : .systemYellow))
            shape.lineWidth = f.style == "bullet" ? 0.9 : 2
            if let t = session?.game?.time, t-lastAudio > 0.65 { GameAudio.shared.play("contact"); lastAudio = t }
        }
        shape.zPosition = 3600; addChild(shape)
        shape.run(.sequence([.fadeOut(withDuration:0.22),.removeFromParent()]))
    }
}
