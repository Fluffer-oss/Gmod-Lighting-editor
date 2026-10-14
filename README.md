# GMod Lighting Editor

Lighting tools for Garry's Mod Star Trek RP, built on the section system of [Star Trek Modules](https://github.com/oninoni/startrekmodules).

## Power outages

Cut power to any ship section, and the lights in that section stutter and die, leaving it dark. Restore it and they struggle back on. Changing power never freezes the game.

### Why it doesn't lag

The usual way to darken a map is to change its baked lighting (`engine.LightStyle`) and rebuild it with `render.RedownloadAllLightmaps()`. That rebuild re-uploads every lightmap on the map, a freeze of a fraction of a second to several seconds, every single time. It also only works map-wide: unless a map's lights are individually named (most aren't), its baked lighting can't be changed one room at a time.

This addon never touches the baked lighting. Every frame:
1. The GPU's stencil buffer marks the pixels whose visible surface lies inside the boxes of the sections without power. That covers walls, floors, props and players, whether you're standing inside a section or looking into it from elsewhere, and anything in front of it still blocks the view.
2. Only those pixels are darkened.

All the dark sections are drawn together, so a whole deck costs about the same as one section: about fifteen draw calls with the default settings. Fades and flickers run every frame at no cost.

### Bleed

STM's section boxes rarely cover a room exactly; there are often gaps between them, or corners they miss. So the darkness doesn't stop at the box edge: it spreads past each box in every direction (sideways, up and down), fading out over 128 units by default. It also reaches a little way into neighbouring sections that still have power. Where the bleed of two dark sections overlaps, it doesn't get any darker than inside them.

### Requirements

- **Star Trek Modules**, with its sections set up for your map (the map's `section<deck>_<id>` triggers). The addon uses STM's own section data, which STM syncs to every client.
- Nothing about the map itself is decompiled or edited, so protected maps are fine.

### Commands

| Command | |
|---|---|
| `lighting_outage here` | cut power where you're standing |
| `lighting_outage 4` | every section on deck 4 |
| `lighting_outage 4 2A` | deck 4, section 2A |
| `lighting_outage ship` | the whole ship |
| `lighting_restore ...` | same targets, power back on |

On Helix servers there are also the chat commands `/PowerOutage` and `/PowerRestore`, with the same targets. Only admins can use any of these; on LeopardRP, so can the schema's `administrator` rank.

### For other addons

```lua
LightingEditor.SetSectionPower(deck, sectionId, false)   -- e.g. from damage or a console
LightingEditor.IsSectionPowered(deck, sectionId)
hook.Add("LightingEditor.SectionPowerChanged", "x", function(deck, sectionId, powered) end)
```

Section ids use STM's numbering: section "4" is `400`, "4A" is `401`, "4B" is `402`. `LightingEditor.ParseSectionId("4A")` converts them.

### Settings

`lua/lighting_editor/sh_config.lua` has:
- **Darkness:** how dark a dead section gets (`DarkLevel`).
- **Timing:** flicker and fade times.
- **Sounds.**
- **Bleed:** how far darkness spreads past the section boxes (`BleedDistance`), and in how many steps it fades (`BleedSteps`; more steps = smoother, three more draw calls each).
- **Draw limits:** how far away dark sections are drawn (`SectionDrawDistance`), and how many section boxes at most (`MaxBoxesDrawn`, the nearest ones; 128 by default, more than a deck usually has).

### Limits

- **Flashlights are dimmed** inside a dark section by the same amount as everything else there, because the darkening applies to the finished image. The default darkness (`DarkLevel = 0.82`) leaves them usable.
- **Box-shaped areas:** areas are STM's section boxes plus the bleed, so the darkness follows the boxes, not the walls. Turn `BleedDistance` down if it reaches too far into lit rooms next door, or up if gaps between boxes stay lit.

## Tests

`tests/` runs the real addon files in a mock Garry's Mod.
- **Software stencil buffer:** every "pixel" is a ray to a known surface, and each draw call applies real depth and stencil rules. The tests check pixel by pixel that only surfaces inside dead sections (and their bleed) are darkened, viewed from inside the section, from another section across the ship and from outside the hull, including two-box (lettered) sections. They also check that a whole deck goes dark, that the bleed fades out in every direction, and that overlaps don't stack.
- **Everything else:** flicker and fade timing, restoring, late joiners, sounds, commands, permissions, Helix commands, and the draw limits.

```
lua5.1 tests/run.lua
```

It can't prove the real engine renders exactly like the mock, so check it in-game too.
