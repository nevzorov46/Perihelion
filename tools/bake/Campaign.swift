/// Campaign source: the skies are hand-made, the motes are not.
/// `tools/run.sh bake` finds a shot for each sky that meets its brief and writes
/// Perihelion/Game/Levels.swift. Difficulty rises through the briefs.
struct CampaignSky {
    let def: LevelDef
    let brief: Design.Brief
    /// Ranks the candidates that meet the brief.
    let prefer: (Design.Result) -> Double
}

private func sky(
    _ id: String, _ name: String, root: Int, preview: Double, hint: String,
    bodies: [BodySpec], launch: SIMD2<Double>, brief: Design.Brief,
    prefer: @escaping (Design.Result) -> Double = { $0.turn * 0.3 + $0.window }
) -> CampaignSky {
    CampaignSky(
        def: LevelDef(id: id, name: name, hint: hint, root: root, preview: preview, bodies: bodies,
                      launch: launch, motes: [], shot: nil, window: 0),
        brief: brief, prefer: prefer)
}

let campaign: [CampaignSky] = [
    sky("first-light", "First Light", root: 50, preview: 1.1,
        hint: "Drag anywhere and pull back. Let go to launch.",
        bodies: [.fixed(.planet, x: 820, y: 610, mu: 9e6)],
        launch: SIMD2(170, 400),
        brief: .init(motes: 3, spread: 0.3, minSpeed: 380, maxSpeed: 560, maxTime: 5, minLength: 800, maxLength: 1050,
                     minTurn: 0.3, maxTurn: 1.2, minWindow: 0.6),
        prefer: { $0.window + $0.turn * 0.2 }),

    sky("bend", "The Bend", root: 52, preview: 0.8,
        hint: "Mass pulls. Aim beside the star and let it bend your path.",
        bodies: [.fixed(.star, x: 880, y: 460, mu: 2.4e7)],
        launch: SIMD2(170, 820),
        brief: .init(motes: 3, aim: -0.45, spread: 0.5, minSpeed: 330, maxSpeed: 600, maxLength: 1400,
                     minTurn: 1.1, maxTurn: 2.4, minWindow: 0.5),
        prefer: { $0.window + $0.turn * 0.15 }),

    sky("slingshot", "Slingshot", root: 55, preview: 0.6,
        hint: "Skim the star fast and close - it will throw you back.",
        bodies: [.fixed(.star, x: 1080, y: 500, mu: 3.4e7)],
        launch: SIMD2(170, 560),
        brief: .init(motes: 4, spread: 0.45, minTurn: 2.6, maxTurn: 4.2, minWindow: 0.4),
        prefer: { $0.turn * 0.4 + $0.window }),

    sky("twin-suns", "Twin Suns", root: 57, preview: 0.5,
        hint: "Every body sings its own note at your closest pass.",
        bodies: [.fixed(.star, x: 650, y: 300, mu: 2.1e7), .fixed(.star, x: 1050, y: 700, mu: 2.3e7)],
        launch: SIMD2(160, 720),
        brief: .init(motes: 4, spread: 0.9, minTurn: 2.2, maxTurn: 6, minWindow: 0.35)),

    sky("moonrise", "Moonrise", root: 53, preview: 0.5,
        hint: "The moon keeps moving while you fly.",
        bodies: [.fixed(.planet, x: 900, y: 520, mu: 1.5e7),
                 .orbiting(.moon, around: 0, radius: 165, phase: 2.2, direction: 1, mu: 1.8e6)],
        launch: SIMD2(160, 280),
        brief: .init(motes: 4, spread: 0.8, minTurn: 2, maxTurn: 7, minWindow: 0.28)),

    sky("figure-eight", "Figure Eight", root: 50, preview: 0.42,
        hint: "Weave around both suns.",
        bodies: [.fixed(.star, x: 590, y: 500, mu: 2.4e7), .fixed(.star, x: 1070, y: 500, mu: 2.4e7)],
        launch: SIMD2(800, 110),
        brief: .init(motes: 5, spread: 0.35, minSpeed: 200, maxSpeed: 330, maxTime: 12, minLength: 2200, maxLength: 3000,
                     minTurn: 7, maxTurn: 20, minWindow: 0.2),
        prefer: { $0.turn * 0.25 + $0.window }),

    sky("binary", "Binary", root: 55, preview: 0.4,
        hint: "Two stars, one dance. Their pull swings as they turn.",
        bodies: [.binary(x: 880, y: 500, separation: 240, mu1: 2.3e7, mu2: 1.7e7, phase: 0.6, direction: 1)],
        launch: SIMD2(150, 520),
        brief: .init(motes: 4, spread: 0.8, minTurn: 2.5, maxTurn: 9, minWindow: 0.2)),

    sky("orrery", "Orrery", root: 48, preview: 0.36,
        hint: "Two worlds on Kepler’s clock: the outer one is always slower.",
        bodies: [.fixed(.star, x: 900, y: 500, mu: 3.2e7),
                 .orbiting(.planet, around: 0, radius: 225, phase: 3.6, direction: 1, mu: 5e6),
                 .orbiting(.planet, around: 0, radius: 370, phase: 0.9, direction: 1, mu: 6e6)],
        launch: SIMD2(140, 860),
        brief: .init(motes: 5, spread: 0.8, minLength: 1400, minTurn: 2.5, maxTurn: 10, minWindow: 0.15)),

    sky("event-horizon", "Event Horizon", root: 45, preview: 0.34,
        hint: "Nothing that crosses the ring comes back.",
        bodies: [.fixed(.hole, x: 980, y: 500, mu: 1.05e8)],
        launch: SIMD2(160, 400),
        brief: .init(motes: 4, spread: 0.6, minLength: 1200, minTurn: 2.8, maxTurn: 9, minWindow: 0.12)),

    sky("three-body", "Three Body", root: 50, preview: 0.32,
        hint: "Three suns on one figure-eight - a real solution of Newton’s equations.",
        bodies: [.threeBody(x: 860, y: 500, scale: 270, period: 9.5, rotation: 0, phase: 0)],
        launch: SIMD2(140, 500),
        brief: .init(motes: 5, spread: 0.9, maxTime: 11, minLength: 1500, minTurn: 3, maxTurn: 14, minWindow: 0.1)),
]
