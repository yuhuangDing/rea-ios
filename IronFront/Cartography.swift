import UIKit
import SpriteKit

enum Cartography {
    static let half: CGFloat = 24
    static func project(_ p: Point) -> CGPoint { CGPoint(x:(p.x-p.y)*half,y:-(p.x+p.y)*half*0.5) }
    static func unproject(_ p: CGPoint) -> Point {
        Point(Double((p.x-2*p.y)/(2*half)),Double((-p.x-2*p.y)/(2*half)))
    }
    static func sheet(_ texture: SKTexture, z: CGFloat) -> SKNode {
        let n = CGFloat(Battlefield.size), group = SKNode(), plane = SKSpriteNode(texture:texture)
        let side = n*half*sqrt(2); plane.size = CGSize(width:side,height:side)
        plane.zRotation = -.pi/4; group.yScale = 0.5; group.position.y = -n*half/2
        group.zPosition = z; group.addChild(plane); return group
    }
    static func pixels(_ bytes: [UInt8], side: Int) -> CGImage {
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width:side,height:side,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:side*4,
                       space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),
                       provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent)!
    }
    static func color(_ terrain: Ground, _ map: Theater) -> (Int,Int,Int) {
        switch (map.layout.climate,terrain) {
        case (.coastal,.water): return (46,105,124)
        case (.snow,.water): return (66,117,142)
        case (.salt,.water): return (76,140,136)
        case (_, .water): return (46,89,96)
        case (.snow,.grass): return (180,195,188)
        case (.snow,.gravel): return (144,158,164)
        case (.snow,.dirt): return (161,164,151)
        case (.snow,.road): return (125,132,125)
        case (.snow,.ridge): return (106,125,138)
        case (.coastal,.grass): return (112,124,82)
        case (.coastal,.dirt): return (159,143,101)
        case (.desert,.grass): return (166,129,84)
        case (.desert,.dirt): return (183,139,90)
        case (.desert,.gravel): return (154,113,83)
        case (.desert,.ridge): return (123,76,57)
        case (.taiga,.grass): return (76,103,71)
        case (.taiga,.dirt): return (117,103,72)
        case (.taiga,.ridge): return (83,92,86)
        case (.salt,.grass): return (160,154,115)
        case (.salt,.dirt): return (185,173,132)
        case (.salt,.gravel): return (199,193,162)
        case (.industrial,.grass): return (103,113,91)
        case (.industrial,.gravel): return (126,127,118)
        case (.industrial,.road): return (92,92,84)
        case (.industrial,.ridge): return (72,74,75)
        case (_, .ridge): return (95,91,84)
        case (_, .grass): return (105,120,74)
        case (_, .dirt): return (138,123,83)
        case (_, .road): return (139,129,100)
        case (_, .gravel): return (115,118,100)
        }
    }
    static func ground(_ map: Battlefield) -> SKTexture {
        let n = Battlefield.size, res = 18, side = n*res
        var bytes = [UInt8](repeating:255,count:side*side*4)
        var state = UInt32(truncatingIfNeeded:map.seed)
        var lattice = [Double](); lattice.reserveCapacity((n+2)*(n+2))
        for _ in 0..<((n+2)*(n+2)) {
            state = state &* 1664525 &+ 1013904223; lattice.append(Double(state>>24)/255)
        }
        let palette = map.tiles.map { color($0,map.theater) }
        for y in 0..<side {
            let gy = y/res, fy = Double(y%res)/Double(res)
            for x in 0..<side {
                let gx = x/res, fx = Double(x%res)/Double(res), idx = gy*n+gx
                let l = gy*(n+2)+gx
                let broad = (1-fy)*(lattice[l]*(1-fx)+lattice[l+1]*fx)
                    + fy*(lattice[l+n+2]*(1-fx)+lattice[l+n+3]*fx)
                state = state &* 1664525 &+ 1013904223
                let dither = Double(state>>24)/255-0.5
                let nearX = max(0,min(n-1,gx+(fx < 0.5 ? -1 : 1)))
                let nearY = max(0,min(n-1,gy+(fy < 0.5 ? -1 : 1)))
                let wx = max(0,abs(fx-0.5)*1.45-0.24), wy = max(0,abs(fy-0.5)*1.45-0.24)
                let c = palette[idx], h = palette[gy*n+nearX], v = palette[nearY*n+gx]
                let isWet = map.tiles[idx] == .water
                var grain = (broad-0.5)*30 + dither*(isWet ? 9 : 31)
                if isWet && (y + Int(broad*15))%13 < 2 { grain += 13 }
                if map.tiles[idx] == .road && ((x+y)%21 == 2 || (x+y)%21 == 4) { grain -= 8 }
                if map.tiles[idx] == .ridge {
                    if gx > 0 && map.tiles[idx-1] != .ridge && fx < 0.24 { grain += 29 }
                    if gy+1 < n && map.tiles[idx+n] != .ridge && fy > 0.58 { grain -= 36 }
                    if (x/2+y+Int(broad*12))%17 < 3 { grain -= 12 }
                }
                let q = (y*side+x)*4
                bytes[q] = UInt8(clamping:Int(Double(c.0)+Double(h.0-c.0)*wx+Double(v.0-c.0)*wy+grain))
                bytes[q+1] = UInt8(clamping:Int(Double(c.1)+Double(h.1-c.1)*wx+Double(v.1-c.1)*wy+grain))
                bytes[q+2] = UInt8(clamping:Int(Double(c.2)+Double(h.2-c.2)*wx+Double(v.2-c.2)*wy+grain*0.8))
            }
        }
        return SKTexture(cgImage:pixels(bytes,side:side))
    }
    static func fog(_ game: Battle) -> SKTexture {
        let n = Battlefield.size
        var bytes = [UInt8](repeating:0,count:n*n*4)
        for i in 0..<n*n {
            bytes[i*4] = 12; bytes[i*4+1] = 22; bytes[i*4+2] = 25
            bytes[i*4+3] = game.visible[i] == 1 ? 0 : (game.explored[i] == 1 ? 112 : 239)
        }
        let texture = SKTexture(cgImage:pixels(bytes,side:n)); texture.filteringMode = .linear; return texture
    }
}
