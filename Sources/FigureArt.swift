import CoreGraphics

/// Cómo se dibuja cada personaje con `FigureBrush`. Los monigotes miden unos 24 pt hasta la coronilla.
extension FigureBrush {
    // MARK: - Paseante con paraguas

    mutating func walker(_ w: Creatures.Walker, wind: CGFloat, time: CGFloat) {
        var walking = false
        if case .walking = w.state { walking = true }
        place(at: CGPoint(x: w.x, y: w.y))
        let d = w.direction

        // Piernas: andando se balancean; colgando, casi juntas.
        let swing = walking ? sin(w.phase) * 3.5 : sin(time * 3 + w.phase) * 1.2
        let hip = CGPoint(x: 0, y: 9)
        segment(hip, CGPoint(x: swing, y: 0), width: 1.4)
        segment(hip, CGPoint(x: -swing, y: walking ? 0 : 0.8), width: 1.4)
        // Tronco, cabeza y el brazo que sujeta el paraguas.
        segment(hip, CGPoint(x: 0, y: 17), width: 1.7)
        ellipse(CGPoint(x: 0, y: 20.5), CGPoint(x: 2.7, y: 2.7))
        let hand = CGPoint(x: d * 3.5, y: 15)
        segment(CGPoint(x: 0, y: 16), hand, width: 1.2)

        // Paraguas: se inclina con el viento; al caer, más abierto y con el mango hacia el movimiento.
        let tilt = walking ? wind * 4 : max(-6, min(6, -w.vx * 0.08))
        let top = CGPoint(x: hand.x + tilt, y: 30)
        let radii = walking ? CGPoint(x: 12, y: 7) : CGPoint(x: 13.5, y: 8.5)
        segment(CGPoint(x: hand.x, y: hand.y - 1.5), top, width: 0.9)
        worldDome(world(top), radii)
        segment(CGPoint(x: top.x, y: top.y + radii.y), CGPoint(x: top.x, y: top.y + radii.y + 2.5), width: 1)
    }

    // MARK: - Pez

    mutating func fish(_ f: Creatures.Fish, time: CGFloat) {
        let s: CGFloat = f.vx >= 0 ? 1 : -1
        // Al darse la vuelta el cuerpo se ve de frente y se estrecha.
        let turn = max(0.35, min(1, abs(f.vx) / f.speed))
        let len = f.size * turn
        place(at: CGPoint(x: f.x, y: f.y), facing: s)
        let wag = sin(time * 8 + f.phase) * f.size * 0.18
        let base = CGPoint(x: -len * 0.85, y: 0)
        for side: CGFloat in [1, -1] {
            segment(base, CGPoint(x: -len * 1.55, y: side * f.size * 0.42 + wag), width: f.size * 0.22)
        }
        segment(CGPoint(x: -len * 0.1, y: f.size * 0.36), CGPoint(x: -len * 0.5, y: f.size * 0.62),
                width: f.size * 0.16)
        ellipse(.zero, CGPoint(x: len, y: f.size * 0.42))
        ellipse(CGPoint(x: len * 0.55, y: f.size * 0.08), CGPoint(x: f.size * 0.08, y: f.size * 0.08), style: .ink)
    }

    // MARK: - Modo Mafia

    /// Postura del monigote, en coordenadas del personaje (pies en el origen, mirando hacia +x).
    private struct Pose {
        var hip = CGPoint(x: 0, y: 9)
        var neck = CGPoint(x: 0.5, y: 17)
        var knees = (CGPoint(x: -1.8, y: 4.5), CGPoint(x: 1.8, y: 4.5))
        var feet = (CGPoint(x: -2.5, y: 0), CGPoint(x: 2.5, y: 0))
        var hands = (CGPoint(x: 3, y: 10), CGPoint(x: -1, y: 10))
        /// Puede apuntar con los brazos (si no, la postura manda sobre ellos).
        var canAim = true
        var lift: CGFloat = 0
    }

    private static func pose(of f: MafiaFight.Fighter, time t: CGFloat) -> Pose {
        var p = Pose()
        switch f.move {
        case .stand:
            break
        case .run:
            let q = f.runPhase
            func leg(_ q: CGFloat) -> (CGPoint, CGPoint) {
                let foot = CGPoint(x: sin(q) * 5.5, y: max(0, cos(q)) * 3)
                return (CGPoint(x: foot.x * 0.5 + 2.2, y: 4.8 + max(0, cos(q)) * 1.5), foot)
            }
            let a = leg(q), b = leg(q + .pi)
            p.knees = (a.0, b.0)
            p.feet = (a.1, b.1)
            p.neck = CGPoint(x: 2.2, y: 16.8)
            p.hands = (CGPoint(x: -sin(q) * 4.5 + 2, y: 11.5), CGPoint(x: sin(q) * 4.5 + 2, y: 11.5))
        case .jump(let flips):
            if flips != 0 {
                // Encogido para dar la voltereta.
                p.knees = (CGPoint(x: 4, y: 8), CGPoint(x: 2.5, y: 8.5))
                p.feet = (CGPoint(x: 2, y: 5), CGPoint(x: -0.5, y: 4))
                p.neck = CGPoint(x: 0.8, y: 16.5)
            } else {
                p.knees = (CGPoint(x: -0.5, y: 5), CGPoint(x: 3.5, y: 6))
                p.feet = (CGPoint(x: -2, y: 1.5), CGPoint(x: 3, y: 2.5))
            }
        case .roll:
            p.hip = CGPoint(x: 0, y: 6)
            p.neck = CGPoint(x: 1.5, y: 12)
            p.knees = (CGPoint(x: 4.5, y: 7), CGPoint(x: 3, y: 7.5))
            p.feet = (CGPoint(x: 3, y: 4), CGPoint(x: 1, y: 3))
            p.hands = (CGPoint(x: 4, y: 9), CGPoint(x: 3, y: 8))
        case .kick:
            // Patada voladora: una pierna estirada, el cuerpo echado atrás y un saltito.
            let k = min(1, f.moveTime / max(f.moveLength, 0.1))
            p.lift = sin(k * .pi) * 6
            p.hip = CGPoint(x: 0, y: 10)
            p.neck = CGPoint(x: -2.5, y: 17.5)
            p.knees = (CGPoint(x: -1, y: 5), CGPoint(x: 5, y: 11))
            p.feet = (CGPoint(x: -1.5, y: 0), CGPoint(x: 11, y: 12.5))
            p.hands = (CGPoint(x: 3, y: 15), CGPoint(x: -5, y: 13))
            p.canAim = false
        case .rope:
            p.hands = (CGPoint(x: 0, y: 23), CGPoint(x: 0, y: 20.5))
            p.knees = (CGPoint(x: 1.5, y: 4.5), CGPoint(x: -1.8, y: 5))
            p.feet = (CGPoint(x: 0.5, y: 0), CGPoint(x: -1, y: 2))
            p.canAim = false
        case .land(let heroic):
            if heroic {
                // Aterrizaje de superhéroe: rodilla en el suelo y una mano apoyada.
                p.hip = CGPoint(x: 0, y: 5)
                p.neck = CGPoint(x: 2.5, y: 12)
                p.knees = (CGPoint(x: 5, y: 4.5), CGPoint(x: -2, y: 0.6))
                p.feet = (CGPoint(x: 4.5, y: 0), CGPoint(x: -6, y: 0.5))
                p.hands = (CGPoint(x: 6, y: 0.3), CGPoint(x: -6, y: 13))
                p.canAim = false
            } else {
                p.hip = CGPoint(x: 0, y: 7)
                p.neck = CGPoint(x: 1, y: 15)
                p.knees = (CGPoint(x: -2.5, y: 4), CGPoint(x: 3.5, y: 4))
                p.feet = (CGPoint(x: -3, y: 0), CGPoint(x: 3, y: 0))
            }
        case .knocked:
            p.knees = (CGPoint(x: -3, y: 5), CGPoint(x: 2.5, y: 4.5))
            p.feet = (CGPoint(x: -4.5, y: 1.5), CGPoint(x: 4, y: 0.5))
            p.hands = (CGPoint(x: -6.5, y: 21), CGPoint(x: 6, y: 20))
            p.canAim = false
        case .swim:
            // Crol: los brazos dan vueltas por encima del agua y las piernas patalean debajo.
            let q = f.runPhase
            p.neck = CGPoint(x: 1.5, y: 17)
            p.hands = (CGPoint(x: 2 + cos(q) * 6.5, y: 15 + sin(q) * 5.5),
                       CGPoint(x: 2 + cos(q + .pi) * 6.5, y: 15 + sin(q + .pi) * 5.5))
            p.knees = (CGPoint(x: -2, y: 4.5 + sin(q * 1.4)), CGPoint(x: 1, y: 4.5 - sin(q * 1.4)))
            p.feet = (CGPoint(x: -3.5, y: 0.5), CGPoint(x: -0.5, y: 0))
        case .sinking:
            // Brazos arriba, pidiendo socorro.
            p.hands = (CGPoint(x: -4, y: 23 + sin(t * 12) * 1.5), CGPoint(x: 4, y: 23 - sin(t * 12) * 1.5))
            p.canAim = false
        }
        return p
    }

    mutating func fighter(_ f: MafiaFight.Fighter, time t: CGFloat) {
        let p = Self.pose(of: f, time: t)
        let s = f.scale
        place(at: CGPoint(x: f.x, y: f.y + p.lift * s), facing: f.facing, scale: s, angle: f.angle,
              pivot: CGPoint(x: 0, y: 11))
        let head = CGPoint(x: p.neck.x + 0.3, y: p.neck.y + 3.6)
        let shoulder = CGPoint(x: p.neck.x, y: p.neck.y - 1)

        // Cuerda.
        if f.move == .rope {
            worldSegment(world(CGPoint(x: 0, y: 24)), CGPoint(x: f.x, y: f.ropeTop), width: 0.9)
        }
        // Piernas, tronco y cabeza.
        for (knee, foot) in [(p.knees.0, p.feet.0), (p.knees.1, p.feet.1)] {
            segment(p.hip, knee, width: 1.6)
            segment(knee, foot, width: 1.5)
        }
        segment(p.hip, p.neck, width: f.hero ? 2.6 : 2.2)
        ellipse(head, CGPoint(x: 2.9, y: 2.9))

        // Brazos: apuntando (en la pantalla) o según la postura.
        let aiming = p.canAim && f.aimTime > 0
        let guns = f.hero ? 2 : 1
        if aiming {
            let from = world(shoulder)
            for k in 0..<guns {
                let a = f.aim + (k == 0 ? 0 : -0.12 * f.facing)
                let dir = CGPoint(x: cos(a), y: sin(a))
                let reach = (k == 0 ? 8 : 7.2) * s
                let hand = CGPoint(x: from.x + dir.x * reach, y: from.y + dir.y * reach - CGFloat(k) * 1.2 * s)
                let elbow = CGPoint(x: from.x + dir.x * reach * 0.5, y: from.y + dir.y * reach * 0.5 - 0.8 * s)
                worldSegment(from, elbow, width: 1.3 * s)
                worldSegment(elbow, hand, width: 1.2 * s)
                gun(at: hand, dir: dir, scale: s, flash: f.flash > 0 && (guns == 1 || f.hand == k))
            }
        } else {
            for (k, hand) in [p.hands.0, p.hands.1].enumerated() {
                let elbow = CGPoint(x: (shoulder.x + hand.x) / 2 + 0.6, y: (shoulder.y + hand.y) / 2 - 0.6)
                segment(shoulder, elbow, width: 1.3)
                segment(elbow, hand, width: 1.2)
                if k < guns {
                    // Pistola hacia abajo y adelante.
                    segment(hand, CGPoint(x: hand.x + 2.6, y: hand.y - 2.4), width: 1.8)
                }
            }
        }

        if f.hero {
            // Corbata y melena negra peinada hacia atrás.
            segment(CGPoint(x: p.neck.x + 0.3, y: p.neck.y - 0.6), CGPoint(x: p.neck.x + 0.8, y: p.neck.y - 4.6),
                    width: 1.1, style: .ink)
            segment(CGPoint(x: head.x + 0.6, y: head.y + 2.5), CGPoint(x: head.x - 2.6, y: head.y + 2.2),
                    width: 1.7, style: .ink)
            segment(CGPoint(x: head.x - 0.5, y: head.y + 2.3), CGPoint(x: head.x - 3.8, y: head.y - 0.2),
                    width: 1.8, style: .ink)
        } else {
            // Sombrero de ala y gafas oscuras.
            segment(CGPoint(x: head.x - 4.2, y: head.y + 2.3), CGPoint(x: head.x + 4.2, y: head.y + 2.3), width: 1.2)
            segment(CGPoint(x: head.x - 2.2, y: head.y + 3.7), CGPoint(x: head.x + 2.2, y: head.y + 3.7), width: 2.8)
            segment(CGPoint(x: head.x - 2.2, y: head.y + 2.9), CGPoint(x: head.x + 2.2, y: head.y + 2.9),
                    width: 0.7, style: .ink)
            segment(CGPoint(x: head.x + 0.6, y: head.y + 0.4), CGPoint(x: head.x + 2.9, y: head.y + 0.4),
                    width: 1.1, style: .ink)
        }
    }

    /// Pistola en `hand` apuntando a `dir`, con fogonazo si acaba de disparar.
    private mutating func gun(at hand: CGPoint, dir: CGPoint, scale s: CGFloat, flash: Bool) {
        let muzzle = CGPoint(x: hand.x + dir.x * 4.5 * s, y: hand.y + dir.y * 4.5 * s)
        worldSegment(hand, muzzle, width: 1.9 * s)
        // Culata hacia abajo, del lado de la mano.
        let down = dir.x >= 0 ? CGPoint(x: dir.y, y: -dir.x) : CGPoint(x: -dir.y, y: dir.x)
        worldSegment(hand, CGPoint(x: hand.x + down.x * 2.3 * s, y: hand.y + down.y * 2.3 * s), width: 1.4 * s)
        guard flash else { return }
        let c = CGPoint(x: muzzle.x + dir.x * 3 * s, y: muzzle.y + dir.y * 3 * s)
        worldEllipse(c, CGPoint(x: 2.4 * s, y: 2.4 * s), style: .glow)
        for a: CGFloat in [-0.6, 0, 0.6] {
            let d = CGPoint(x: cos(atan2(dir.y, dir.x) + a), y: sin(atan2(dir.y, dir.x) + a))
            worldSegment(c, CGPoint(x: c.x + d.x * 5.5 * s, y: c.y + d.y * 5.5 * s), width: 1.1 * s, style: .glow)
        }
    }

    mutating func bullet(_ b: MafiaFight.Bullet) {
        let speed = max(1, hypot(b.vx, b.vy))
        let tail = CGPoint(x: b.x - b.vx / speed * 12, y: b.y - b.vy / speed * 12)
        worldSegment(CGPoint(x: b.x, y: b.y), tail, width: 1.3)
    }

    mutating func casing(_ c: MafiaFight.Casing) {
        let d = CGPoint(x: cos(c.angle) * 1.4, y: sin(c.angle) * 1.4)
        worldSegment(CGPoint(x: c.x - d.x, y: c.y - d.y), CGPoint(x: c.x + d.x, y: c.y + d.y), width: 1.1)
    }

    /// Lancha: casco en cuenco, borda, proa levantada, parabrisas y motor fuera borda.
    mutating func boat(_ b: MafiaFight.Boat, deck y: CGFloat) {
        let x = b.x, fc = b.facing
        worldDome(CGPoint(x: x, y: y), CGPoint(x: 34, y: 11), flipped: true)
        worldSegment(CGPoint(x: x - 36, y: y + 0.5), CGPoint(x: x + 36, y: y + 0.5), width: 2.2)
        worldSegment(CGPoint(x: x + fc * 34, y: y), CGPoint(x: x + fc * 41, y: y + 5), width: 2)
        worldSegment(CGPoint(x: x + fc * 12, y: y + 1), CGPoint(x: x + fc * 17, y: y + 10), width: 1.2)
        worldSegment(CGPoint(x: x - fc * 35, y: y - 2), CGPoint(x: x - fc * 39, y: y + 9), width: 3.2)
    }
}
