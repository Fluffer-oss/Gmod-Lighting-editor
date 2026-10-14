# GMod Lighting Editor

Lighting tools for Garry's Mod Star Trek RP, built on the section system of [Star Trek Modules](https://github.com/oninoni/startrekmodules).

## Power outages

Cut power to a deck, and for everyone on it the lights stutter and die: the walls, floors, static props, doors, props and players lose their light, cubemap reflections dim, and everything that glows goes out. STM's LCARS screens and force fields stay on and light up the dark around them. Flashlights still work. Restore it and the lights struggle back on. Changing power never freezes the game.

### Why it doesn't freeze

The usual way to darken a map is to change its baked lighting (`engine.LightStyle`) and rebuild it with `render.RedownloadAllLightmaps()`. That rebuild re-uploads every lightmap on the map, a freeze of a fraction of a second to several seconds, every single time. It's also map-wide for everyone at once.

This addon never rebuilds anything. It changes material parameters, which costs nothing and can fade smoothly frame by frame. Each player's own game handles it, so only the people on a dark deck see it.

### What goes dark, and how

| | How | |
|---|---|---|
| Walls, floors, brush doors | `$color` | Source multiplies a world material's `$color` into exactly the light from its lightmap, so only the baked light goes. Flashlights are drawn in a separate pass it doesn't touch. |
| Cubemap reflections | `$envmaptint` | On world and model materials. |
| Static props, props, doors, NPCs, weapons | `$color2`, `$phongboost` | Their lighting and their highlights. Model shaders convert `$color2` (and `$envmaptint`, and the per-model color) from gamma to linear before using them, which world shaders don't, so models get the value that comes out as the same linear scale as the walls. Without that, props end up about 20× darker than the walls around them. |
| Players, your weapon and hands | dimmed while drawn | Player colors come from a material proxy that would undo a material change. |
| Light fixtures (`Config.LightMaterials`) | glowing parts blacked out | Their bright parts (above `GlowThreshold`, 0.7) and whatever the material marks as self-illuminated go black; frames, markings and detail stay, and the fixture is darkened like any surface. `GlowOff = "black"` blacks out the whole texture instead. Copies the map compiler makes for cubemaps (`maps/<map>/<name>_x_y_z`) count too. |
| Self-illuminated surfaces (a wall with a glowing strip) | marked parts blacked out | Darkened like any surface, and only what the material marks as glowing (its `$selfillummask`, or its texture's alpha) goes black. White paint stays white. |
| Pure light (additive materials, sprites) | out entirely | Light cones and glows. |
| Plain unlit materials (labels, signs, screens) | left alone | |
| The map's light entities | switched off by the server | Named lights, `light_dynamic`, `env_projectedtexture`, `point_spotlight`, and the sprites and glows on fixtures, on that deck. Ones that were already off stay off. |

**Only the inside of the ship.** After you join, the addon reads the map file (read-only, in the background, a couple of milliseconds per frame at most) to find which material every surface uses and where, and where every static prop is. Then:
- World materials with at least half their area within `InteriorDistance` (96 units) of a section box are darkened.
- Static props, props and entities within that distance are darkened.
- The hull's outside, the 3D skybox, the sky and STM's exterior (its planets and ships) are left alone, along with anything matching `Config.KeepMaterials`.

If the map file can't be read, it falls back to every material the world uses.

### STM's light sources

These keep running with the power out, and give off real dynamic light. The nearest 12 are lit (`Config.Emitters.MaxLights`). While the deck is dark, their light is raised to show, at most `Config.Emitters.MaxBoost` (2) times. Static props can't receive dynamic light, so raising it further lights the walls far more than the props around them, which turns the props into black cutouts.
- **LCARS screens:** light the average color of what they show, from their face outward. A bigger screen lights a bigger area. During red alert they light STM's red.
- **Force fields:** light the color of their texture. The average color comes from the texture file, tinted by the material and the field's own color.

STM's alerts switch the bridge lights back on when they change; the server switches them back off if the bridge's deck has no power, and red alert's dimmed bridge lights stay off when power returns.

### How a light's glowing parts are blacked out

Swapping a texture for a copy beats material proxies that animate a color (STM's bridge lights use one). Each copy is made once, in the background, one texture per frame, on the graphics card:
1. The texture's brightness (gray, via GMod's color-modify shader), minus the threshold.
2. That, stretched so anything clearly bright becomes 1.
3. Whichever is more, that or the material's self-illumination mask.
4. The texture, alpha and all, times 1 minus that.

Until a copy is ready (or if one can't be made), a listed light goes all black (transparent black, so see-through parts stay see-through) and a surface with glowing parts is left as it is.

### Which deck you're on

Inside one of STM's section boxes, that section's deck. Outside them (corridors and rooms the sections miss), the deck whose overall extent contains you, with `Config.DeckPadding` (64 units) to spare. In a turbolift shaft or anywhere else outside every deck, you stay on the last deck you were on. Arriving on a deck with different power fades over half a second.

### Requirements

- **Star Trek Modules**, with its sections set up for your map (the map's `section<deck>_<id>` triggers). The addon uses STM's own section data, which STM syncs to every client.
- Nothing about the map is changed, so protected maps are fine.

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
- **`DarkLevel`:** how much light a dead deck loses (0.92 by default).
- **`LightMaterials`:** materials that go black with the power, on top of everything that glows. On a test server, `sv_cheats 1` and `mat_crosshair 1` show the material you're looking at.
- **`GlowOff`, `GlowThreshold`:** whether listed lights lose only their glowing parts or go all black, and how bright counts as glowing.
- **`KeepMaterials`, `KeepClasses`:** materials (name patterns) and entity classes never touched (`core_effect` is in there). Add your hull's exterior materials if any get darkened.
- **`InteriorDistance`:** how close to a section counts as inside the ship.
- **`Emitters`:** brightness and reach of LCARS screens and force fields, how many are lit, and `MaxBoost`.
- **`MapLights`:** which map light entities the server switches off, and how.
- **Timing:** flicker and fade times, and `DeckChangeTime`. Also `DeckPadding` and sounds.

### Limits

- **Materials are shared:** a material darkens everywhere the player can see it, so someone on a dark deck looking through a window at a lit deck sees it dark too.
- **Flashlights on props:** on walls and floors the flashlight is unaffected, but a model's tint also scales the flashlight pass drawn on it, so props under a flashlight are as dim as the rest of their light. Only rebuilding the lighting (`engine.LightStyle` plus `render.RedownloadAllLightmaps`, which is what freezes) changes a static prop's baked light by itself.
- **Other addons' lights:** dynamic lights and projected textures from other addons (like flashlights) aren't touched.

## Tests

`tests/` runs the real addon files in a mock Garry's Mod, with simulated materials and real binary game files (a map, models and a texture, built byte for byte by `tests/files.lua`):
- **Map reading:** face materials, centers and areas, skipped sky and nodraw faces, static props, model materials and texture colors, and the fallback when the map can't be read.
- **Darkening:** the exact values written to every kind of material. It checks what's left alone (the hull's outside, the skybox, STM's exterior, force fields, the alert material) and that everything returns to its exact original on restore. It also checks that nothing is written while nothing changes, and that the background scan is spread over frames.
- **Emitters:** LCARS and force field light colors, placement, size and brightness, the boost and light caps, and no light from alert fixtures.
- **Server:** map lights switched off and back on per deck, lights that were already off, and STM's alert and bridge lights.
- **Never freezes:** the mock errors if anything calls `engine.LightStyle` or `render.RedownloadAllLightmaps`.
- **Everything else:** decks, flicker timing, fades, late joiners, sounds, commands, permissions and Helix commands.

```
lua5.1 tests/run.lua
```

It can't prove the real engine renders exactly like the mock, so check it in-game too.
