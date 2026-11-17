# Third-party assets

These assets keep their own licenses and are not covered by the MIT License in `LICENSE`, which applies to the source code.

Everything else in the game (map, stations, lines, trains, passenger glyphs, menu art, app icon) is original
vector art drawn in code. No assets come from Mini Metro or any other commercial game, and none were made
with an image-generation model.

| Asset | Used for | Files in the project | Author | Source | License | Attribution |
|---|---|---|---|---|---|---|
| Outfit (variable font) | All UI text | `MetroNetwork/Resources/Fonts/Outfit.ttf` (original: `Assets/ThirdParty/outfit/Outfit-Variable.ttf`) | Copyright 2021 The Outfit Project Authors (https://github.com/Outfitio/Outfit-Fonts) | https://github.com/google/fonts/tree/main/ofl/outfit | SIL Open Font License 1.1 | License must ship with the font: `MetroNetwork/Resources/Fonts/Outfit-OFL.txt` (bundled in the app) |
| Particle Pack 1.1 — `circle_05` | Soft glow: station and train shadows, selection halo, station spawn pulse | `MetroNetwork/Resources/Textures/glow.png` | Kenney Vleugels (kenney.nl) | https://kenney.nl/assets/particle-pack | CC0 1.0 | Not required |
| Particle Pack 1.1 — `star_06` | Sparkle when a passenger arrives | `MetroNetwork/Resources/Textures/sparkle.png` | Kenney Vleugels (kenney.nl) | https://kenney.nl/assets/particle-pack | CC0 1.0 | Not required |

Downloaded 2026-11-13: the Outfit font (with the user's approval). The two Kenney textures were copied from the
Particle Pack (downloaded from kenney.nl); the originals and `License.txt` are kept in
`Assets/ThirdParty/kenney-particle-pack/`.

## Conversions

- Kenney textures: the 512 × 512 transparent PNGs were downscaled to 128 × 128 with `sips`; otherwise unchanged
  (they are white and are tinted in code).
- Outfit: copied unchanged and registered at launch with Core Text (`App/AppFonts.swift`).

## Drawn in code

- App icon and menu logo: `Tools/make-icon.swift` (Core Graphics) writes `Assets.xcassets/AppIcon.appiconset`
  and `Logo.imageset`. Re-run with `swift Tools/make-icon.swift`.
- City blocks, park trees, water ripples, street grid: `Game/Renderers/MapRenderer.swift`, seeded per map.
- Station symbols, trains, line casing, passenger glyphs: SpriteKit shape nodes.

## Kenney — Interface Sounds (CC0 1.0)

- Source: Kenney Interface Sounds 1.0 (www.kenney.nl), downloaded from kenney.nl
  (no new download). License: Creative Commons Zero — `Assets/ThirdParty/kenney-interface-sounds/License.txt`.
- Used (decoded from Ogg to 44.1 kHz mono WAV in `MetroNetwork/Resources/Sounds/`; originals kept next to the license):
  click_002 → tap, confirmation_001 → line, pluck_001 → station, tick_002 → deliver, drop_002 → purchase,
  question_001 → warning, bong_001 → event, maximize_003 → week, error_006 → gameover, confirmation_004 → complete,
  back_002 → remove, toggle_002 → toggle.

## Music

- Original, generated in code at run time (`MetroNetwork/Audio/MusicSynth.swift`). No third-party music.
