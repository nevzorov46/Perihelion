# Perihelion

A gravity-assist puzzle for iPhone where orbits play notes.

Pull back, let go, and a comet flies through a star system under real Newtonian gravity. Collect every mote of light in one shot. Every close pass of a star or planet rings a note and taps the Taptic Engine; every mote climbs a pentatonic scale. A clean run ends on a rising phrase.

Swift, Metal, SwiftUI, AVAudioEngine, Core Haptics. No dependencies, no assets - every pixel and every sound is generated.

## The physics is not faked

- **Restricted N-body.** The comet feels every body; the bodies ignore the comet and ride exact analytic paths: Kepler circles, a binary around its barycentre. Periods come from the masses (ω = √(μ/r³)), never from a designer's slider.
- **The figure-eight three-body solution.** The last campaign sky puts three suns on the Chenciner-Montgomery choreography, integrated from Simó's initial conditions. After one period the table closes to 3·10⁻⁸.
- **Symplectic, fixed-step integrator.** Kick-drift-kick leapfrog at 480 Hz. A circular orbit keeps its energy to 1·10⁻⁸ over the full 16-second flight.

## Levels that prove themselves

Motes are not placed by hand. `tools/run.sh bake` fires shots into each hand-made sky, keeps one whose path meets the level's brief, and drops the motes onto that path. **Every level ships with the shot that made it** - a proof that it can be solved.

Difficulty is measured, not guessed. The tool re-fires the proof shot with the error a hand makes (±0.9° of aim, ±2.4% of power) and counts how many near-misses still win. That fraction is the level's *window*, and the briefs make it shrink as the campaign goes on: 0.83 on the first sky, 0.13 on the three-body one.

## Same bits everywhere

Levels are baked on a Mac and played on a phone, and the simulation is chaotic: a last-bit difference in a moon's position becomes a different trajectory a few seconds later. libm's `sin`/`cos` are not guaranteed to be correctly rounded, so the physics uses its own, built only from `+ − × ÷` (`DMath.swift`), which IEEE-754 makes exact. `tools/run.sh verify` prints a fingerprint of every proof flight's final state; it must match on every machine.

## Rendering

One frame: a baked background (nebula and stars, rendered once per level), a spacetime grid bent by the masses in the vertex shader, trail ribbons, and one instanced draw of every sprite - stellar granulation, lit planets, an accretion disk - into an `rgba16Float` target. Then a 13-tap downsample / tent upsample bloom (Jimenez 2014), ACES tonemapping and an sRGB drawable. Dynamic buffers are cycled three-deep behind a semaphore, so the CPU never writes into memory the GPU is reading.

## Sound

An FM synth in an `AVAudioSourceNode`. The game talks to the audio thread through a lock-free single-producer/single-consumer ring (`Synchronization.Atomic`): no locks and no allocation on the render thread.

## Running

Xcode 26, iOS 18, iPhone.

```bash
open Perihelion.xcodeproj
```

Hands-free: fire every level's proof shot by itself, for recordings.

```bash
xcrun simctl launch booted com.nevzorov.Perihelion -demo YES
```

Physics checks and level baking run on the Mac, compiling the app's own physics sources:

```bash
tools/run.sh verify
tools/run.sh bake
```

## Status

A first playable slice: two skies, First Light and Slingshot. The other eight - twin suns, a moon on the move, a binary, an orrery, a black hole, the three-body dance - are baked and verified, waiting to be switched on. Next: a daily sky that is the same for everyone, and a share card of your trajectory.
