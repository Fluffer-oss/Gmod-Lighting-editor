# GMod Lighting Editor

Lighting tools for Garry's Mod Star Trek RP, built on the section system of [Star Trek Modules](https://github.com/oninoni/startrekmodules).

## Power outages

Cut power to a deck, and for everyone on it the lights stutter and die: the map's baked lighting goes dark, light fixtures go black, and players and props lose their light. Flashlights still work. Restore it and the lights struggle back on. Changing power never freezes the game.

### Why it doesn't freeze

The usual way to darken a map is to change its baked lighting (`engine.LightStyle`) and rebuild it with `render.RedownloadAllLightmaps()`. That rebuild re-uploads every lightmap on the map, a freeze of a fraction of a second to several seconds, every single time. It's also map-wide for everyone at once.

This addon never rebuilds anything. In Source, a world material's `$color` multiplies exactly the light that comes from its lightmap (`LightmappedGeneric` scales its lightmap lighting by it). So on each player's own game:
- **World:** every lightmapped world and brush-entity material (doors, hatches) has its `$color` turned down, so walls and floors lose their baked light. Changing a material parameter costs nothing, so it fades smoothly frame by frame.
- **Light fixtures:** the materials in `Config.LightMaterials` go fully black (color, glow and reflections).
- **Models:** players, NPCs and props are drawn with only a little flat light (`Config.ModelLight`) instead of the map's lighting.

It's per player: only the people on a dark deck see it, everyone else's game is untouched. It covers everything they see, so it doesn't matter that STM's sections don't cover every corridor. Walking or riding a turbolift onto a deck with different power fades over half a second.

### Which deck you're on

Inside one of STM's section boxes, that section's deck. Outside them (corridors and rooms the sections miss), the deck whose overall extent contains you, with `Config.DeckPadding` (64 units) to spare. In a turbolift shaft or anywhere else outside every deck, you stay on the last deck you were on.

### Requirements

- **Star Trek Modules**, with its sections set up for your map (the map's `section<deck>_<id>` triggers). The addon uses STM's own section data, which STM syncs to every client.
- Nothing about the map itself is decompiled or edited, so protected maps are fine.

### Commands

| Command | |
|---|---|
| `lighting_outage here` | cut power to the deck you're on |
| `lighting_outage 4` | deck 4 |
| `lighting_outage ship` | every deck |
| `lighting_restore ...` | same targets, power back on |

On Helix servers there are also the chat commands `/PowerOutage` and `/PowerRestore`, with the same targets. Only admins can use any of these; on LeopardRP, so can the schema's `administrator` rank.

### For other addons

```lua
LightingEditor.SetDeckPower(deck, false)   -- e.g. from damage or a console
LightingEditor.IsDeckPowered(deck)
hook.Add("LightingEditor.DeckPowerChanged", "x", function(deck, powered) end)
```

### Settings

`lua/lighting_editor/sh_config.lua` has:
- **`DarkLevel`:** how much baked light a dead deck loses (0.92 by default).
- **`LightMaterials`:** materials that go black with the power. Add your map's light fixtures here; on a test server, `sv_cheats 1` and `mat_crosshair 1` show the material you look at.
- **`DarkenModels` and `ModelLight`:** whether models go dark, and how much light they keep.
- **Timing:** flicker and fade times, and `DeckChangeTime`.
- **`DeckPadding`** and **sounds.**

### Limits

- **Only lightmapped surfaces darken through `$color`.** That's almost every wall and floor. Materials with their own glow (`$selfillum`) keep it unless they're in `LightMaterials`; unlit and water materials don't change.
- **Dark models are evenly lit:** while the lights are out, models lose their shading direction along with their light.
- **Materials are shared:** a material darkens everywhere the player can see it, so someone on a dark deck looking through a window at a lit one sees it dark too.

## Tests

`tests/` runs the real addon files in a mock Garry's Mod, with simulated materials:
- **Materials:** the exact values written to each material: dark on a dead deck, lit fixtures black, untouched shaders left alone, exact originals back on restore, and no writes at all while nothing changes.
- **Decks:** deck lookup (sections, the gaps between them, turbolift shafts), fades when changing deck, and that players on powered decks see nothing.
- **Never freezes:** the mock errors if anything calls `engine.LightStyle` or `render.RedownloadAllLightmaps`.
- **Everything else:** flicker timing, model lighting, late joiners, sounds, commands, permissions and Helix commands.

```
lua5.1 tests/run.lua
```

It can't prove the real engine renders exactly like the mock, so check it in-game too.
