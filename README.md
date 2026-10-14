# GMod Lighting Editor

Lighting tools for Garry's Mod Star Trek RP, built on the section system of [Star Trek Modules](https://github.com/oninoni/startrekmodules).

## Power outages

Cut power to any ship section, and the lights in that section stutter, die and give way to red emergency lighting. Restore it and they struggle back on. Changing power never freezes the game.

### Why it doesn't lag

The usual way to darken a map is to change its baked lighting (`engine.LightStyle`) and rebuild it with `render.RedownloadAllLightmaps()`. That rebuild re-uploads every lightmap on the map, a freeze of a fraction of a second to several seconds, every single time. It also only works map-wide: unless a map's lights are individually named (most aren't), its baked lighting can't be changed one room at a time.

This addon never touches the baked lighting. Every frame, for each section without power:
1. The GPU's stencil buffer marks the pixels whose visible surface lies inside that section's boxes. That covers walls, floors, props and players, whether you're standing inside the section or looking into it from elsewhere, and anything in front of it still blocks the view.
2. Only those pixels are darkened, with a slow red emergency pulse on top.
3. Red glows appear on the section's **real light fixtures**, read straight out of the map's `.bsp`, and a few real red lights light the room around the nearest ones.

It's a handful of draw calls per dark section, and only the nearest few dark sections are drawn (6 by default). Fades and flickers run every frame at no cost.

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
- **Emergency lighting:** color and pulse.
- **Fixtures:** glow size, and how many real emergency lights to use.
- **Timing:** flicker and fade times.
- **Sounds.**
- **Draw limits:** how many sections are drawn, and how far away.

### Limits

- **Flashlights are dimmed** inside a dark section by the same amount as everything else there, because the darkening applies to the finished image. The default darkness (`DarkLevel = 0.82`) leaves them usable.
- **No fixture glows if the light data is compressed:** they need the map's light data to be readable; most maps store it plainly. If a map stores it compressed, the addon says so in the console and skips just the glows. The darkening and red pulse still work.
- **Box-shaped areas:** areas are STM's section boxes, so anything the boxes include gets darkened, a few units past a wall included.

## Tests

`tests/` runs the real addon files in a mock Garry's Mod.
- **Software stencil buffer:** every "pixel" is a ray to a known surface, and each draw call applies real depth and stencil rules. The tests check pixel by pixel that only surfaces inside dead sections are darkened, viewed from inside the section, from another section across the ship and from outside the hull, including two-box (lettered) sections.
- **Everything else:** flicker and fade timing, restoring, late joiners, sounds, commands, permissions, Helix commands, and the draw and light caps.

```
lua5.1 tests/run.lua
```

To also check the `.bsp` light reader against real maps, point it at them. It's verified against Star Trek Modules' `stm_showroom.bsp` (584 fixtures) and a TF2 test map:

```
STM_SHOWROOM_BSP=path/to/stm_showroom.bsp TF2_TEST_BSP=path/to/test2.bsp lua5.1 tests/run.lua
```

It can't prove the real engine renders exactly like the mock, so check it in-game too.
