HARNESS_DIR = arg[0]:match("^(.*/)") or "./"
package.path = HARNESS_DIR .. "?.lua;" .. package.path
local M = require("mock")
local F = require("files")
local V, Color = M.Vector, M.Color

local passed, failed = 0, 0
local function check(cond, label)
    if cond then passed = passed + 1 else failed = failed + 1 print("FAIL: " .. label) end
end
local function step(label, fn)
    local ok, err = pcall(fn)
    if not ok then failed = failed + 1 print("ERROR in '" .. label .. "': " .. tostring(err)) end
end
local function near(a, b) return a and b and math.abs(a - b) < 1e-4 end
local function vnear(v, x, y, z) return v and near(v.x, x) and near(v.y, y) and near(v.z, z) end

--------------------------------------------------------------------------------
-- The ship
--------------------------------------------------------------------------------

-- Star Trek Modules' section data, as synced to both realms.
-- Deck 1 (z 0..128): two sections with an uncovered corridor (x 512..768) between them.
-- Deck 2 (z 256..384): one section over the whole deck.
local function area(x1, y1, z1, x2, y2, z2) return { Min = V(x1, y1, z1), Max = V(x2, y2, z2) } end
local function MakeDecks()
    return {
        [1] = { Sections = {
            [100] = { RealId = "1", Name = "Bridge", Areas = { area(0, 0, 0, 512, 256, 128) } },
            [500] = { RealId = "5", Name = "Engineering", Areas = { area(768, 0, 0, 1024, 256, 128) } }
        } },
        [2] = { Sections = {
            [100] = { RealId = "1", Name = "Quarters", Areas = { area(0, 0, 256, 1024, 256, 384) } }
        } }
    }
end

local function quad(x, y, z, size) -- a floor tile centered on x, y
    local h = size / 2
    return { { x - h, y - h, z }, { x + h, y - h, z }, { x + h, y + h, z }, { x - h, y + h, z } }
end

local ALARM = "models/kingpommes/startrek/intrepid/light_alarm"
local BRIDGE_LIGHT = "models/kingpommes/startrek/intrepid/light_bridge_ceiling"
local CORRIGATED = "kingpommes/startrek/intrepid/wall_corrigated"
local SELFILLUM, ADDITIVE = 64, 128
local function tex(name) return { textureName = name } end

-- The map's world faces: inside the ship (near a section), on the hull's
-- outside, and in the sky.
M.files["maps/rp_test.bsp"] = F.Map({
    { material = "maps/floor", verts = quad(100, 100, 0, 64), area = 4096 },
    { material = "maps/floor", verts = quad(600, 100, 0, 64), area = 4096 },     -- uncovered corridor: still inside
    { material = "maps/hull", verts = quad(500, -2000, 64, 64), area = 4096 },   -- outside the ship
    { material = "maps/mixed", verts = quad(200, 100, 128, 64), area = 3000 },   -- mostly inside: darkened
    { material = "maps/mixed", verts = quad(200, -3000, 0, 64), area = 1000 },
    { material = "maps/hullmostly", verts = quad(200, 100, 0, 64), area = 1000 }, -- mostly outside: left alone
    { material = "maps/hullmostly", verts = quad(200, -3000, 0, 64), area = 3000 },
    { material = "maps/glowstrip", verts = quad(300, 50, 128, 32) },
    { material = "maps/cubemapped", verts = quad(400, 200, 0, 32) },
    { material = "maps/water", verts = quad(450, 200, 0, 32) },
    { material = "maps/skyface", verts = quad(100, 100, 128, 32), flags = 0x4 }, -- sky: never drawn lit
    { material = "maps/nodraw", verts = quad(100, 100, 120, 32), flags = 0x80 },
    { material = CORRIGATED, verts = quad(800, 100, 128, 32) },
    { material = "maps/stairs", verts = { { 0, 0, 300 }, { 90, 0, 300 }, { 0, 90, 300 } } }
}, {
    { model = "models/props/console.mdl", pos = { 100, 100, 10 } },
    { model = "models/props/asteroid.mdl", pos = { 0, 0, -9000 } },              -- 3D skybox
    { model = "models/kingpommes/startrek/intrepid/alarm.mdl", pos = { 300, 100, 100 } },
    { model = "models/kingpommes/startrek/intrepid/alarm.mdl", pos = { 300, 900, 300 } } -- outside: no alarm here
})
M.files["models/props/console.mdl"] = F.Model({ "console", "console_screen" }, { "models\\props_old\\", "models\\props\\" })
M.files["models/props/asteroid.mdl"] = F.Model({ "asteroid" }, { "models/props/" })
M.files["models/kingpommes/startrek/intrepid/alarm.mdl"] = F.Model({ "light_alarm", "alarm_frame" }, { "models/kingpommes/startrek/intrepid/" })
M.files["materials/stm/forcefield.vtf"] = F.Texture(0.1, 0.3, 0.6)

M.materials = {
    ["maps/floor"] = { shader = "LightmappedGeneric", params = { ["$color"] = V(1, 1, 1), ["$basetexture"] = tex("maps/floor") } },
    ["maps/hull"] = { shader = "LightmappedGeneric", params = { ["$color"] = V(1, 1, 1) } },
    ["maps/mixed"] = { shader = "WorldVertexTransition", params = { ["$color"] = V(0.5, 0.8, 1) } },
    ["maps/hullmostly"] = { shader = "LightmappedGeneric", params = { ["$color"] = V(1, 1, 1) } },
    ["maps/glowstrip"] = { shader = "LightmappedGeneric", params = { ["$flags"] = SELFILLUM, ["$basetexture"] = tex("maps/glowstrip"), ["$selfillumtint"] = V(1, 1, 1) } },
    ["maps/cubemapped"] = { shader = "LightmappedGeneric", params = { ["$envmap"] = "env_cubemap", ["$envmaptint"] = V(0.6, 0.6, 0.6) } },
    ["maps/water"] = { shader = "Water", params = { ["$color"] = V(1, 1, 1) } },
    ["maps/skyface"] = { shader = "LightmappedGeneric", params = {} },
    ["maps/nodraw"] = { shader = "LightmappedGeneric", params = {} },
    ["maps/stairs"] = { shader = "LightmappedGeneric", params = {} },
    ["maps/door"] = { shader = "LightmappedGeneric", params = { ["$color"] = V(1, 1, 1) } },
    [CORRIGATED] = { shader = "LightmappedGeneric", params = { ["$basetexture"] = tex(CORRIGATED) } },
    ["models/props/console"] = { shader = "VertexLitGeneric", params = { ["$phong"] = 1, ["$phongboost"] = 2, ["$envmap"] = "env_cubemap" } },
    ["models/props/console_screen"] = { shader = "VertexLitGeneric", params = { ["$flags"] = SELFILLUM, ["$basetexture"] = tex("models/props/console_screen") } },
    ["models/props/asteroid"] = { shader = "VertexLitGeneric", params = { ["$color2"] = V(1, 1, 1) } },
    ["models/props/door_metal"] = { shader = "VertexLitGeneric", params = { ["$color2"] = V(0.9, 0.9, 0.9) } },
    ["models/props/beam_cone"] = { shader = "VertexLitGeneric", params = { ["$flags"] = ADDITIVE, ["$basetexture"] = tex("models/props/beam_cone") } },
    ["models/planets/earth"] = { shader = "VertexLitGeneric", params = { ["$color2"] = V(1, 1, 1) } },
    ["models/stm/forcefield"] = { shader = "UnlitGeneric", params = { ["$basetexture"] = "stm/forcefield", ["$color"] = V(1, 1, 1) } },
    [ALARM] = { shader = "VertexLitGeneric", params = { ["$alarmcolor"] = V(0, 0, 0), ["$basetexture"] = tex(ALARM) } },
    ["models/kingpommes/startrek/intrepid/alarm_frame"] = { shader = "VertexLitGeneric", params = {} },
    [BRIDGE_LIGHT] = { shader = "VertexLitGeneric", params = { ["$flags"] = SELFILLUM, ["$basetexture"] = tex(BRIDGE_LIGHT), ["$brightness"] = 1 } },
    ["lights/white"] = { shader = "UnlitGeneric", params = { ["$color"] = V(1, 1, 1) } } -- no texture
}
M.worldMaterials = { "maps/floor", "maps/hull", "lights/white" }

-- Client-side entities.
local function Ent(class, model, pos, materials, extra)
    local e = { __valid = true, class = class, model = model, pos = pos, materials = materials or {}, color = Color(255, 255, 255, 255) }
    function e:GetClass() return self.class end
    function e:GetModel() return self.model end
    function e:GetPos() return self.pos end
    function e:WorldSpaceCenter() return self.pos end
    function e:GetMaterials() return self.materials end
    function e:GetMaterial() return self.override or "" end
    function e:IsPlayer() return false end
    function e:GetNoDraw() return self.noDraw == true end
    function e:GetColor() return self.color end
    function e:OBBMins() return V(-64, -2, -64) end
    function e:OBBMaxs() return V(64, 2, 64) end
    for k, v in pairs(extra or {}) do e[k] = v end
    return e
end
local door = Ent("prop_dynamic", "models/props/door.mdl", V(256, 0, 64), { "models/props/door_metal" })
local brushDoor = Ent("func_door", "*3", V(700, 128, 64), { "maps/door" })
local beam = Ent("prop_dynamic", "models/props/beam.mdl", V(200, 200, 100), {}, { override = "models/props/beam_cone" })
local field = Ent("force_field", "models/stm/forcefield.mdl", V(640, 128, 64), { "models/stm/forcefield" })
local planet = Ent("prop_dynamic", "models/planets/earth.mdl", V(0, 0, -20000), { "models/planets/earth" })
local lamp = Ent("prop_dynamic", "models/props/lamp.mdl", V(150, 150, 120), { BRIDGE_LIGHT, "lights/white" })
M.entities = { door, brushDoor, beam, field, planet, lamp }

-- Server-side map light entities.
local function MapLight(class, name, pos, extra)
    local e = { __valid = true, class = class, name = name, pos = pos, fired = {}, flags = 0, vars = {} }
    function e:GetPos() return self.pos end
    function e:GetName() return self.name end
    function e:Fire(input) table.insert(self.fired, input) end
    function e:GetNoDraw() return self.noDraw == true end
    function e:SetNoDraw(v) self.noDraw = v end
    function e:HasSpawnFlags(f) return math.floor(self.flags / f) % 2 == 1 end
    function e:GetInternalVariable(k) return self.vars[k] end
    for k, v in pairs(extra or {}) do e[k] = v end
    return e
end
local bridgeLight = MapLight("light", "bridgeLights", V(100, 100, 120))
local darkLight = MapLight("light", "storeroom", V(800, 100, 120), { flags = 1 })        -- already off
local dynLight = MapLight("light_dynamic", "", V(200, 100, 120), { vars = { m_On = true } })
local deck2Lamp = MapLight("env_projectedtexture", "", V(100, 100, 350), { vars = { m_bState = true } })
local sprite = MapLight("env_sprite", "", V(300, 100, 120))
local hiddenSprite = MapLight("env_sprite", "", V(310, 100, 120), { noDraw = true })    -- hidden by the map
local spot = MapLight("point_spotlight", "", V(400, 100, 120), { vars = { m_bSpotlightOn = true } })
M.serverEntities = { bridgeLight, darkLight, dynLight, deck2Lamp, sprite, hiddenSprite, spot }

--------------------------------------------------------------------------------
-- Realms
--------------------------------------------------------------------------------

local admin = M.MakePlayer("admin", true)
local crew = M.MakePlayer("crewman", false)
local server, adminCl, crewCl, clients

local function STM(realm)
    realm.Star_Trek = {
        Sections = { Decks = MakeDecks() },
        Alert = {
            AlertMaterial = ALARM, BridgeDimName = "bridgeLights",
            AlertTypes = { red = { BridgeDim = true }, yellow = { BridgeDim = false } }
        },
        LCARS = {
            ColorOrange = Color(202, 151, 50), ColorRed = Color(197, 52, 54),
            ActiveInterfaces = {}
        }
    }
end

local function NewClient(ply)
    local realm = M.NewRealm(false, ply)
    STM(realm)
    realm.include("autorun/lighting_editor.lua")
    return realm
end

local function boot()
    M.pooled, M.queueToServer, M.queueToClients = {}, {}, {}
    server = M.NewRealm(true)
    STM(server)
    -- STM's server alert functions, switching the bridge lights like STM does.
    local alert = server.Star_Trek.Alert
    function alert:Enable(type)
        self.ActiveAlert = type
        bridgeLight:Fire(self.AlertTypes[type].BridgeDim and "turnOff" or "turnOn")
        return true
    end
    function alert:Disable()
        self.ActiveAlert = nil
        bridgeLight:Fire("turnOn")
        return true
    end
    server.include("autorun/lighting_editor.lua")
    adminCl, crewCl = NewClient(admin), NewClient(crew)
    clients = { [admin] = adminCl, [crew] = crewCl }
    adminCl.hook.Run("InitPostEntity")
    crewCl.hook.Run("InitPostEntity")
    M.Pump(server, clients)
end
local function pump() M.Pump(server, clients) end

local frames = 0
local function Frame()
    frames = frames + 1
    for _, realm in pairs(clients) do
        realm.hook.Run("PreRender")
        realm.hook.Run("Think")
    end
end
-- Advances the clock to `t`, running client frames every 0.05s on the way.
local function RunTo(t)
    while M.time < t - 1e-9 do
        M.time = math.min(t, M.time + 0.05)
        Frame()
    end
end

local function P(realm, name, p) return realm.materialDefs[name].params[p] end
local function floor(realm) return P(realm, "maps/floor", "$color").x end
local function isBlack(realm, name) local t = P(realm, name, "$basetexture") return type(t) == "table" and t.textureName == "lightingeditor_black" end
local function liveLights(realm)
    local list = {}
    for _, l in pairs(realm.dlights) do if l.dietime and l.dietime > M.time then table.insert(list, l) end end
    return list
end

local DECK1, DECK2 = V(256, 128, 0), V(256, 128, 300)
boot()
local Config = server.LightingEditor.Config
local DARK = Config.DarkLevel
local K = 1 - DARK

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

step("finding the deck", function()
    local LE = server.LightingEditor
    check(LE.FindDeck(V(100, 100, 50)) == 1, "inside a deck 1 section")
    check(LE.FindDeck(V(600, 100, 50)) == 1, "in a corridor no section covers: still deck 1")
    check(LE.FindDeck(V(100, 100, 300)) == 2, "deck 2")
    check(LE.FindDeck(V(100, 100, 5000)) == nil, "far above the ship: no deck")
    check(LE.NearSection(V(600, 100, 0), 96) and not LE.NearSection(V(500, -2000, 64), 96), "inside vs the hull's outside")
end)

step("reading the map's files", function()
    local LE = crewCl.LightingEditor
    local faces, props = {}, {}
    local ok = LE.ScanMap(function(name, center, faceArea) table.insert(faces, { name, center, faceArea }) end,
        function(model, pos) table.insert(props, { model, pos }) end, function() end)
    check(ok, "map read")
    check(#faces == 12, "12 drawn faces, sky and nodraw skipped: " .. #faces)
    check(faces[1][1] == "maps/floor" and vnear(faces[1][2], 100, 100, 0) and near(faces[1][3], 4096), "face material, center and area")
    check(vnear(faces[#faces][2], 30, 30, 300), "a triangle's center (edges stored both ways round)")
    check(#props == 4 and props[1][1] == "models/props/console.mdl" and vnear(props[1][2], 100, 100, 10), "static props and positions")
    local candidates = LE.ModelMaterialCandidates("models/props/console.mdl")
    check(#candidates == 2 and candidates[1][2] == "models/props/console" and candidates[2][1] == "models/props_old/console_screen", "model materials under each folder")
    check(vnear(LE.TextureColor("stm/forcefield"), 0.1, 0.3, 0.6), "texture average color")
    check(LE.TextureColor("missing/texture") == nil, "missing texture: no color")
end)

step("finding what to darken happens over several frames", function()
    local step = M.sysTimeStep
    M.sysTimeStep = 0.001 -- a slow computer: the time budget runs out quickly
    local before = frames
    for _ = 1, 200 do
        Frame()
        if crewCl.LightingEditor.WorldScanned then break end
    end
    check(crewCl.LightingEditor.WorldScanned, "scan finished")
    check(frames - before > 1, "spread over " .. (frames - before) .. " frames")
    M.sysTimeStep = step
end)

step("with power everywhere, nothing is touched", function()
    crew.pos, admin.pos = DECK1, DECK2
    RunTo(105)
    check(crewCl.materialWrites == 0 and adminCl.materialWrites == 0, "no material writes")
    check(#M.errors == 0, "no errors: " .. tostring(M.errors[1]))
end)

step("crew can't cut power", function()
    server.RunCmd(crew, "lighting_outage", { "1" })
    pump()
    check(crew.chat[#crew.chat]:find("permission") ~= nil, "crewman told no permission")
    check(next(server.LightingEditor.Outages) == nil, "nothing changed")
end)

step("cut power to deck 1: flicker, then dark", function()
    server.RunCmd(admin, "lighting_outage", { "1" })
    pump()
    check(admin.chat[#admin.chat]:find("Power cut on: deck 1") ~= nil, "admin told: " .. tostring(admin.chat[#admin.chat]))
    check(#crewCl.sounds == 1 and #adminCl.sounds == 0, "sound for the crewman on deck 1 only")
    local seen = {}
    local stop = M.time + Config.FlickerOutTime - 0.05
    while M.time < stop do
        RunTo(M.time + 0.05)
        seen[floor(crewCl) < 0.5 and "dark" or "lit"] = true
        seen[isBlack(crewCl, CORRIGATED) and "off" or "on"] = true
    end
    check(seen.dark and seen.lit and seen.off and seen.on, "lights flicker before dying")
    RunTo(M.time + 10)
end)

step("deck 1 without power: surfaces", function()
    local c = crewCl
    check(near(floor(c), K), "floor's baked light down to " .. K .. ": " .. floor(c))
    check(vnear(P(c, "maps/mixed", "$color"), 0.5 * K, 0.8 * K, K), "displacement, mostly inside, scaled from its own color")
    check(vnear(P(c, "maps/cubemapped", "$envmaptint"), 0.6 * K, 0.6 * K, 0.6 * K), "cubemap reflections dimmed")
    check(near(P(c, "maps/door", "$color").x, K), "brush door dark")
    check(vnear(P(c, "maps/hull", "$color"), 1, 1, 1), "the hull's outside untouched")
    check(vnear(P(c, "maps/hullmostly", "$color"), 1, 1, 1), "a material mostly on the outside untouched")
    check(vnear(P(c, "maps/water", "$color"), 1, 1, 1), "water untouched")
    check(P(c, "maps/skyface", "$color") == nil and P(c, "maps/nodraw", "$color") == nil, "sky and nodraw faces ignored")
end)

step("deck 1 without power: props, entities and glow", function()
    local c = crewCl
    check(vnear(P(c, "models/props/console", "$color2"), K, K, K), "static prop dark")
    check(near(P(c, "models/props/console", "$phongboost"), 2 * K), "and its highlights")
    check(vnear(P(c, "models/props/console", "$envmaptint"), K, K, K), "and its reflections")
    check(isBlack(c, "models/props/console_screen"), "static prop's glowing screen off")
    check(P(c, "models/props/asteroid", "$color2").x == 1, "3D skybox prop untouched")
    check(vnear(P(c, "models/props/door_metal", "$color2"), 0.9 * K, 0.9 * K, 0.9 * K), "door (entity) dark")
    check(isBlack(c, "models/props/beam_cone"), "additive light cone (material override) off")
    check(P(c, "models/planets/earth", "$color2").x == 1, "STM exterior (planet far outside) untouched")
    check(P(c, "models/stm/forcefield", "$basetexture") == "stm/forcefield" and P(c, "models/stm/forcefield", "$color").x == 1, "force field untouched")
    check(isBlack(c, "maps/glowstrip"), "self-illuminated wall strip off")
    check(isBlack(c, CORRIGATED), "wall_corrigated (listed) black")
    check(isBlack(c, BRIDGE_LIGHT), "bridge light off by texture, so STM's brightness proxy can't undo it")
    check(vnear(P(c, "lights/white", "$color"), 0, 0, 0), "lights/white (no texture) black by color")
    check(P(c, ALARM, "$basetexture").textureName == ALARM and P(c, ALARM, "$color2") == nil, "STM alert material untouched")
    local black = c.renderTargets.lightingeditor_black
    check(black.cleared[1] == 0 and black.cleared[2] == 0 and black.cleared[3] == 0, "the black texture is black")
end)

step("players, weapons and hands are dimmed while drawn", function()
    for _, pair in ipairs({ { "PrePlayerDraw", "PostPlayerDraw" }, { "PreDrawViewModel", "PostDrawViewModel" }, { "PreDrawPlayerHands", "PostDrawPlayerHands" } }) do
        crewCl.hook.Run(pair[1])
        check(near(crewCl.modulation[1], K), pair[1] .. " dims")
        crewCl.hook.Run(pair[2])
        check(crewCl.modulation[1] == 1, pair[2] .. " restores")
    end
end)

step("the admin on deck 2 (with power) sees nothing change", function()
    check(adminCl.materialWrites == 0, "no material writes on the admin's game")
    adminCl.hook.Run("PrePlayerDraw")
    check(adminCl.modulation[1] == 1, "players normal")
end)

step("steady darkness costs nothing per frame", function()
    local writes = crewCl.materialWrites
    RunTo(M.time + 2)
    check(crewCl.materialWrites == writes, "no material writes while nothing changes")
end)

step("new props are picked up while dark", function()
    crewCl.materialDefs["models/props/mug"] = { shader = "VertexLitGeneric", params = { ["$color2"] = V(1, 1, 1) } }
    local mug = Ent("prop_physics", "models/props/mug.mdl", V(120, 120, 40), { "models/props/mug" })
    table.insert(M.entities, mug)
    RunTo(M.time + 1.5)
    check(near(P(crewCl, "models/props/mug", "$color2").x, K), "spawned mug dark")
    table.remove(M.entities)
end)

step("STM's light sources keep shining, as real light", function()
    local lcars = crewCl.Star_Trek.LCARS
    local console = Ent("prop_dynamic", "models/props/console.mdl", V(100, 0, 64), {})
    lcars.ActiveInterfaces[5] = { Ent = console, AnimPos = 1, Windows = {
        { WPosG = V(100, 0, 64), WAngG = { Up = function() return V(0, 1, 0) end }, WScale = 20, WWidth = 400, WHeight = 200,
          Elements = { { Color = Color(202, 151, 50) }, { Color = Color(53, 164, 192) } } }
    } }
    crewCl.Star_Trek.Alert.CurrentAlert = "red"
    crewCl.materialDefs[ALARM].params["$alarmcolor"] = V(255 / 256, 0, 0)
    RunTo(M.time + 0.5)

    local byPos, screen = {}, nil
    for _, l in ipairs(liveLights(crewCl)) do
        byPos[string.format("%d %d %d", l.pos.x, l.pos.y, l.pos.z)] = l
        if l.dir then screen = l end
    end

    check(screen ~= nil, "the LCARS screen gives off light")
    if screen then
        check(screen.pos.y > 0 and vnear(screen.dir, 0, 1, 0), "from its face, towards the front")
        check(screen.r == math.floor((202 + 53) / 2 + 0.5) and screen.b == math.floor((50 + 192) / 2 + 0.5), "the average color of what it shows")
        local size = math.sqrt((400 / 20) * (200 / 20))
        check(near(screen.size, math.max(size * Config.Emitters.LCARS.RadiusPerUnit, Config.Emitters.LCARS.MinRadius)), "sized by the screen")
        check(near(screen.brightness, Config.Emitters.LCARS.Brightness / K), "bright enough to show in the dark")
    end

    local fieldLight = byPos["640 128 64"]
    check(fieldLight ~= nil, "the force field gives off light")
    if fieldLight then
        check(fieldLight.b == 255 and math.abs(fieldLight.g - 255 / 2) <= 1 and math.abs(fieldLight.r - 255 / 6) <= 1,
            string.format("the color of its texture: %d %d %d", fieldLight.r, fieldLight.g, fieldLight.b))
    end

    local alarm = byPos["300 100 100"]
    check(alarm ~= nil and alarm.r == 255 and alarm.g == 0 and alarm.b == 0, "the alert fixture glows the alert's red")
    check(byPos["300 900 300"] == nil, "only fixtures inside the ship")

    -- Red alert: screens switch to STM's red palette.
    lcars.ActiveInterfaces[5].Windows[1].CurrentStyle = "LCARS_RED"
    RunTo(M.time + 0.5)
    for _, l in ipairs(liveLights(crewCl)) do
        if l.dir then check(l.r == 197 and l.g == 52 and l.b == 54, "red alert screens light red") end
    end

    crewCl.Star_Trek.Alert.CurrentAlert = nil -- (the material keeps its color until STM clears it)
    lcars.ActiveInterfaces[5] = nil
    RunTo(M.time + 1)
    check(#liveLights(crewCl) == 1, "alert over and screen closed: only the force field still lights (" .. #liveLights(crewCl) .. ")")
    crewCl.materialDefs[ALARM].params["$alarmcolor"] = V(0, 0, 0)
end)

step("at most Config.Emitters.MaxLights lights, nearest first", function()
    for i = 20, 1, -1 do -- furthest first
        table.insert(M.entities, Ent("force_field", "models/stm/forcefield.mdl", V(300 + i * 40, 128, 64), { "models/stm/forcefield" }))
    end
    crewCl.dlights = {}
    RunTo(M.time + 0.5)
    local lights, furthest = liveLights(crewCl), 0
    for _, l in ipairs(lights) do furthest = math.max(furthest, l.pos.x) end
    check(#lights == Config.Emitters.MaxLights, "capped at " .. Config.Emitters.MaxLights .. ": " .. #lights)
    check(furthest < 300 + 20 * 40, "the furthest left out")
    for _ = 1, 20 do table.remove(M.entities) end
end)

step("the server switches deck 1's map lights off", function()
    check(bridgeLight.fired[#bridgeLight.fired] == "TurnOff", "named light off")
    check(#darkLight.fired == 0, "a light that was already off is left alone")
    check(dynLight.fired[#dynLight.fired] == "TurnOff", "dynamic light off")
    check(spot.fired[#spot.fired] == "LightOff", "spotlight off")
    check(sprite.noDraw == true, "glow sprite hidden")
    check(#deck2Lamp.fired == 0, "deck 2's lamp untouched")
end)

step("STM's alerts can't switch the bridge lights back on during an outage", function()
    server.Star_Trek.Alert:Enable("yellow") -- STM turns the bridge lights on for yellow alert
    check(bridgeLight.fired[#bridgeLight.fired] == "TurnOff", "switched back off")
    server.Star_Trek.Alert:Enable("red")
end)

step("walking into a corridor the sections don't cover: still dark", function()
    crew.pos = V(640, 128, 0)
    RunTo(M.time + 2)
    check(near(floor(crewCl), K), "still dark")
end)

step("taking the turbolift to deck 2: fades back to normal", function()
    crew.pos = V(1300, 128, 200) -- in a turbolift shaft outside every deck: stays on deck 1
    RunTo(M.time + 1)
    check(near(floor(crewCl), K), "between decks: still dark")
    crew.pos = DECK2
    RunTo(M.time + 0.2 + Config.DeckChangeTime / 2)
    local mid = floor(crewCl)
    check(mid > K + 0.05 and mid < 0.95, "fading, not snapping: " .. mid)
    RunTo(M.time + Config.DeckChangeTime)
    check(near(floor(crewCl), 1), "floor fully lit")
    check(not isBlack(crewCl, BRIDGE_LIGHT), "lights back on")
    local writes = crewCl.materialWrites
    RunTo(M.time + 2)
    check(crewCl.materialWrites == writes, "then left alone")
    crew.pos = DECK1
    RunTo(M.time + 1)
    check(near(floor(crewCl), K), "back on deck 1: dark")
end)

step("late joiners see the dark deck, with no sound", function()
    local late = M.MakePlayer("late", false)
    late.pos = DECK1
    local lateCl = NewClient(late)
    clients[late] = lateCl
    lateCl.hook.Run("InitPostEntity")
    pump()
    RunTo(M.time + 3)
    check(near(floor(lateCl), K), "dark for the joiner")
    check(isBlack(lateCl, CORRIGATED), "lights off for the joiner")
    check(#lateCl.sounds == 0, "no sound")
    clients[late] = nil
end)

step("restore power: everything's exactly as it was", function()
    crewCl.sounds = {}
    server.Star_Trek.Alert:Disable()
    server.RunCmd(admin, "lighting_restore", { "1" })
    pump()
    check(admin.chat[#admin.chat]:find("restored to: deck 1") ~= nil, "admin told")
    check(#crewCl.sounds == 1, "crewman hears it")
    RunTo(M.time + Config.FlickerInTime / 2)
    check(floor(crewCl) < 1, "not instantly back")
    RunTo(M.time + Config.FlickerInTime + Config.FadeInTime + 0.5)
    for name, def in pairs(M.materials) do
        for p, original in pairs(def.params) do
            local now = P(crewCl, name, p)
            local same
            if type(original) == "table" and original.textureName then same = type(now) == "table" and now.textureName == original.textureName
            elseif type(original) == "table" then same = vnear(now, original.x, original.y, original.z)
            else same = now == original end
            check(same, name .. " " .. p .. " restored exactly")
        end
    end
    crewCl.hook.Run("PrePlayerDraw")
    check(crewCl.modulation[1] == 1, "players normal")

    check(bridgeLight.fired[#bridgeLight.fired] == "TurnOn" and dynLight.fired[#dynLight.fired] == "TurnOn" and spot.fired[#spot.fired] == "LightOn", "map lights back on")
    check(#darkLight.fired == 0, "the one that was off stays off")
    check(sprite.noDraw == false and hiddenSprite.noDraw == true, "sprites as they were")
end)

step("red alert holds the bridge lights off after power returns", function()
    local alert = server.Star_Trek.Alert
    alert:Enable("red")
    server.RunCmd(admin, "lighting_outage", { "1" })
    local count = #bridgeLight.fired
    server.RunCmd(admin, "lighting_restore", { "1" })
    check(#bridgeLight.fired == count, "not switched on while STM has them dimmed")
    alert:Disable()
    pump()
end)

step("a map that can't be read falls back to the world's materials", function()
    local saved = M.files["maps/rp_test.bsp"]
    M.files["maps/rp_test.bsp"] = nil
    local other = M.MakePlayer("other", false)
    other.pos = DECK1
    local otherCl = NewClient(other)
    clients[other] = otherCl
    otherCl.hook.Run("InitPostEntity")
    pump()
    for _ = 1, 50 do Frame() end
    check(otherCl.LightingEditor.WorldScanned, "finished anyway")
    server.RunCmd(admin, "lighting_outage", { "1" })
    pump()
    RunTo(M.time + 5)
    check(near(floor(otherCl), K), "world materials still darkened")
    server.RunCmd(admin, "lighting_restore", { "1" })
    pump()
    RunTo(M.time + 5)
    clients[other] = nil
    M.files["maps/rp_test.bsp"] = saved
end)

step("here, ship, and bad decks", function()
    admin.pos = DECK2
    server.RunCmd(admin, "lighting_outage", { "here" })
    check(admin.chat[#admin.chat]:find("deck 2") ~= nil, "'here' is the admin's deck: " .. admin.chat[#admin.chat])
    check(deck2Lamp.fired[#deck2Lamp.fired] == "TurnOff", "deck 2's lamp off")
    admin.pos = V(0, 0, 5000)
    server.RunCmd(admin, "lighting_outage", { "here" })
    check(admin.chat[#admin.chat]:find("not on any deck") ~= nil, "'here' off the ship explained")
    server.RunCmd(admin, "lighting_outage", { "ship" })
    check(admin.chat[#admin.chat]:find("2 decks") ~= nil, "ship covers both decks")
    local sends = #M.queueToClients
    server.RunCmd(admin, "lighting_restore", { "ship" })
    check(#M.queueToClients - sends == 1, "one network update for the whole ship")
    pump()
    check(server.LightingEditor.IsDeckPowered(1) and server.LightingEditor.IsDeckPowered(2), "all powered")
    check(deck2Lamp.fired[#deck2Lamp.fired] == "TurnOn", "deck 2's lamp back on")
    server.RunCmd(admin, "lighting_outage", { "7" })
    check(admin.chat[#admin.chat]:find("no deck 7") ~= nil, "unknown deck explained")
end)

step("Helix chat commands", function()
    local registered = {}
    server.ix = { command = { Add = function(name, def) registered[name] = def end }, type = { string = 1, optional = 64 } }
    server.hook.Run("InitializedPlugins")
    check(registered.PowerOutage and registered.PowerRestore, "PowerOutage and PowerRestore registered")
    check(registered.PowerOutage.adminOnly, "admin only")
    local reply = registered.PowerOutage.OnRun(nil, admin, "2")
    check(reply and reply:find("cut on: deck 2") ~= nil, "PowerOutage works: " .. tostring(reply))
end)

for _, e in ipairs(M.errors) do print("logged: " .. e) end
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
