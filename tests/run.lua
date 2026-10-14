HARNESS_DIR = arg[0]:match("^(.*/)") or "./"
package.path = HARNESS_DIR .. "?.lua;" .. package.path
local M = require("mock")
local V = M.Vector

local passed, failed = 0, 0
local function check(cond, label)
    if cond then passed = passed + 1 else failed = failed + 1 print("FAIL: " .. label) end
end
local function step(label, fn)
    local ok, err = pcall(fn)
    if not ok then failed = failed + 1 print("ERROR in '" .. label .. "': " .. tostring(err)) end
end

-- Star Trek Modules' section data, as synced to both realms. Deck 1:
--   section "1" (100):  x 0..512
--   section "4A" (401): an L of two boxes, x 512..768 (y 0..256 and y 256..512)
--   section "5" (500):  x 768..1024
local function area(x1, y1, z1, x2, y2, z2) return { Min = V(x1, y1, z1), Max = V(x2, y2, z2) } end
local function MakeDecks()
    return {
        [1] = { Bounds = {}, Sections = {
            [100] = { RealId = "1", Name = "Bridge", Areas = { area(0, 0, 0, 512, 256, 128) } },
            [401] = { RealId = "4A", Name = "Corridor", Areas = { area(512, 0, 0, 768, 256, 128), area(512, 256, 0, 768, 512, 128) } },
            [500] = { RealId = "5", Name = "Engineering", Areas = { area(768, 0, 0, 1024, 256, 128) } }
        } }
    }
end

local admin = M.MakePlayer("admin", true)
local crew = M.MakePlayer("crewman", false)
local server, adminCl, crewCl, clients

local function boot()
    M.pooled, M.queueToServer, M.queueToClients = {}, {}, {}
    server = M.NewRealm(true)
    server.Star_Trek = { Sections = { Decks = MakeDecks() } }
    server.include("autorun/lighting_editor.lua")
    adminCl = M.NewRealm(false, admin)
    adminCl.Star_Trek = { Sections = { Decks = MakeDecks() } }
    adminCl.include("autorun/lighting_editor.lua")
    crewCl = M.NewRealm(false, crew)
    crewCl.Star_Trek = { Sections = { Decks = MakeDecks() } }
    crewCl.include("autorun/lighting_editor.lua")
    clients = { [admin] = adminCl, [crew] = crewCl }
    adminCl.hook.Run("InitPostEntity")
    crewCl.hook.Run("InitPostEntity")
    M.Pump(server, clients)
end
local function pump() M.Pump(server, clients) end

-- Renders one frame for a client from `eye`, looking at `points`; returns darkness per point.
local function Frame(realm, eye, points)
    M.SetView(eye, points)
    realm.hook.Run("PostDrawTranslucentRenderables", false, false, false)
    realm.hook.Run("Think")
    local dark = {}
    for i, px in ipairs(M.pixels) do dark[i] = px.dark or 0 end
    return dark
end

local function balanced(realm)
    local st = realm.stencilState
    return not st.enabled and not st.colorOff and not st.depthWriteOff and not st.in2D
end

-- Scene points (floors and walls) used as pixels.
local P = {
    bridgeFloor = V(100, 128, 0),
    bridgeCeiling = V(300, 128, 128),
    bridgeWall = V(256, 0, 64),
    corridorFloorA = V(600, 128, 0),
    corridorFloorB = V(640, 400, 0),
    engineFloor = V(900, 128, 0),
    outsideFloor = V(100, -200, 0)
}
local ORDER = { "bridgeFloor", "bridgeCeiling", "bridgeWall", "corridorFloorA", "corridorFloorB", "engineFloor", "outsideFloor" }
local function points() local t = {} for i, k in ipairs(ORDER) do t[i] = P[k] end return t end
local function darkMap(dark) local t = {} for i, k in ipairs(ORDER) do t[k] = dark[i] end return t end

boot()
local DARK = server.LightingEditor.Config.DarkLevel

step("section ids like Star Trek Modules", function()
    local LE = server.LightingEditor
    check(LE.ParseSectionId("4A") == 401 and LE.ParseSectionId("4b") == 402 and LE.ParseSectionId("1") == 100 and LE.ParseSectionId(400) == 400, "4A=401, 4b=402, 1=100")
    check(LE.ParseSectionId("x?") == nil, "garbage rejected")
end)

step("crew can't cut power", function()
    server.RunCmd(crew, "lighting_outage", { "1", "1" })
    pump()
    check(crew.chat[#crew.chat]:find("permission") ~= nil, "crewman told no permission")
    check(next(server.LightingEditor.Outages) == nil, "nothing changed")
end)

step("cut power to the bridge", function()
    M.time = 100
    server.RunCmd(admin, "lighting_outage", { "1", "1" })
    pump()
    check(admin.chat[#admin.chat]:find("Power cut in: deck 1 section 1") ~= nil, "admin told: " .. tostring(admin.chat[#admin.chat]))
    check(crewCl.LightingEditor.ClientOutages["1:100"] and crewCl.LightingEditor.ClientOutages["1:100"].out, "every client knows")
end)

step("steady darkness: only surfaces inside the dark section", function()
    M.time = 110 -- long after the flicker and fade
    crew.pos = V(256, 128, 0) -- standing on the bridge
    local d = darkMap(Frame(crewCl, V(256, 128, 64), points()))
    check(math.abs(d.bridgeFloor - DARK) < 1e-6, "bridge floor dark (camera inside the section)")
    check(math.abs(d.bridgeCeiling - DARK) < 1e-6, "bridge ceiling dark")
    check(math.abs(d.bridgeWall - DARK) < 1e-6, "bridge wall dark")
    check(d.corridorFloorA == 0 and d.corridorFloorB == 0 and d.engineFloor == 0, "other sections untouched")
    check(d.outsideFloor == 0, "outside the ship untouched")
    check(balanced(crewCl), "render state restored")
end)

step("looking at the dark bridge from engineering, through the corridor", function()
    local d = darkMap(Frame(crewCl, V(1000, 128, 64), points()))
    check(math.abs(d.bridgeFloor - DARK) < 1e-6, "bridge floor dark from far away (camera outside the section)")
    check(d.corridorFloorA == 0, "corridor floor in between not darkened")
    check(d.engineFloor == 0, "engineering floor (where we stand) not darkened")
end)

step("looking at the dark bridge from outside the ship", function()
    local d = darkMap(Frame(crewCl, V(256, -400, 64), points()))
    check(math.abs(d.bridgeFloor - DARK) < 1e-6, "bridge seen from outside: dark")
    check(d.outsideFloor == 0, "ground outside: normal")
end)

step("a two-box (L-shaped) section goes dark as a whole", function()
    server.RunCmd(admin, "lighting_outage", { "1", "4A" })
    pump()
    M.time = 130
    local d = darkMap(Frame(crewCl, V(256, 128, 64), points()))
    check(math.abs(d.corridorFloorA - DARK) < 1e-6 and math.abs(d.corridorFloorB - DARK) < 1e-6, "both boxes of section 4A dark")
    check(d.engineFloor == 0, "engineering still lit")
    check(math.abs(d.bridgeFloor - DARK) < 1e-6, "bridge still dark too")
end)

step("flicker, then fade, then steady", function()
    local LE = crewCl.LightingEditor
    local entry = { deck = 1, sectionId = 500, out = true, changedAt = 200 }
    local seen = {}
    for t = 0, LE.Config.FlickerOutTime - 0.01, 0.05 do
        seen[LE.SectionDarkness(entry, 200 + t)] = true
    end
    check(seen[0] and seen[DARK], "flicker alternates between lit and dark")
    local afterFlicker = LE.SectionDarkness(entry, 200 + LE.Config.FlickerOutTime + 0.01)
    check(afterFlicker > 0 and afterFlicker < DARK, "then fades down")
    check(math.abs(LE.SectionDarkness(entry, 260) - DARK) < 1e-9, "then holds at full darkness")
    local restored = { deck = 1, sectionId = 500, out = false, changedAt = 300 }
    check(LE.SectionDarkness(restored, 300 + LE.Config.FlickerInTime + LE.Config.FadeInTime + 0.1) == 0, "restored section ends fully lit")
end)

step("emergency lighting after the flicker", function()
    M.time = 300
    server.RunCmd(admin, "lighting_outage", { "1", "5" })
    pump()
    crewCl.sprites = {}
    Frame(crewCl, V(256, 128, 64), points())
    local engineGlowsDuringFlicker = 0
    for _, s in ipairs(crewCl.sprites) do if s.pos.x > 768 then engineGlowsDuringFlicker = engineGlowsDuringFlicker + 1 end end
    check(engineGlowsDuringFlicker == 0, "no emergency glow while lights are still flickering")
end)

step("restore power", function()
    M.time = 400
    server.RunCmd(admin, "lighting_restore", { "1", "1" })
    pump()
    check(admin.chat[#admin.chat]:find("restored") ~= nil, "admin told power restored")
    M.time = 410
    local d = darkMap(Frame(crewCl, V(256, 128, 64), points()))
    check(d.bridgeFloor == 0, "bridge lit again")
    check(math.abs(d.corridorFloorA - DARK) < 1e-6, "corridor still dark")
end)

step("sounds play for people nearby, not for late joiners", function()
    crewCl.sounds = {}
    M.time = 500
    crew.pos = V(256, 128, 0)
    server.RunCmd(admin, "lighting_outage", { "here" }) -- admin is at the origin: not in a section
    pump()
    check(admin.chat[#admin.chat]:find("not inside any section") ~= nil, "'here' outside any section explained")
    admin.pos = V(300, 100, 0)
    server.RunCmd(admin, "lighting_outage", { "here" })
    pump()
    check(#crewCl.sounds == 1, "crewman on the bridge hears it")

    -- A new player joining later sees the state but hears nothing.
    M.time = 600
    local late = M.MakePlayer("late", false)
    local lateCl = M.NewRealm(false, late)
    lateCl.Star_Trek = { Sections = { Decks = MakeDecks() } }
    lateCl.include("autorun/lighting_editor.lua")
    clients[late] = lateCl
    lateCl.hook.Run("InitPostEntity")
    pump()
    check(lateCl.LightingEditor.ClientOutages["1:100"] and lateCl.LightingEditor.ClientOutages["1:100"].out, "late joiner gets the outage")
    check(#lateCl.sounds == 0, "late joiner hears no sound")
    clients[late] = nil
end)

step("whole ship and whole deck", function()
    server.RunCmd(admin, "lighting_restore", { "ship" })
    pump()
    check(admin.chat[#admin.chat]:find("3 sections") ~= nil, "ship restore covers all sections")
    local sends = #M.queueToClients
    server.RunCmd(admin, "lighting_outage", { "1" })
    check(#M.queueToClients - sends == 1, "one network update for a whole deck, not one per section")
    pump()
    for _, id in ipairs({ 100, 401, 500 }) do
        check(server.LightingEditor.Outages["1:" .. id].out, "deck 1 section " .. id .. " dark")
    end
    server.RunCmd(admin, "lighting_outage", { "1", "9Z" })
    check(admin.chat[#admin.chat]:find("no section 9Z") ~= nil, "unknown section explained")
    server.RunCmd(admin, "lighting_outage", { "7" })
    check(admin.chat[#admin.chat]:find("no deck 7") ~= nil, "unknown deck explained")
end)

step("only the nearest few dark sections are drawn", function()
    local LE = crewCl.LightingEditor
    local decks = crewCl.Star_Trek.Sections.Decks
    for i = 1, 20 do -- 20 extra dark sections further and further away
        decks[1].Sections[1000 + i] = { RealId = tostring(10 + i), Name = "x", Areas = { area(2000 + i * 100, 0, 0, 2090 + i * 100, 90, 90) } }
        LE.ClientOutages["1:" .. (1000 + i)] = { deck = 1, sectionId = 1000 + i, out = true, changedAt = 0 }
    end
    local drawCount = 0
    local real = crewCl.render.ClearStencil
    crewCl.render.ClearStencil = function() drawCount = drawCount + 1 real() end
    M.time = 700
    Frame(crewCl, V(256, 128, 64), points())
    crewCl.render.ClearStencil = real
    check(drawCount == LE.Config.MaxSectionsDrawn, "drew " .. drawCount .. " sections, cap is " .. LE.Config.MaxSectionsDrawn)
    for i = 1, 20 do decks[1].Sections[1000 + i] = nil LE.ClientOutages["1:" .. (1000 + i)] = nil end
end)

step("emergency lights on real fixtures, capped", function()
    local LE = crewCl.LightingEditor
    -- Fake fixture list through the public path: a map file isn't needed for this.
    local fixtures = {}
    for i = 1, 30 do fixtures[i] = { pos = V(20 + i * 15, 128, 120), color = crewCl.Color(255, 255, 255) } end
    local real = LE.GetSectionLights
    LE.GetSectionLights = function(deck, id) return (deck == 1 and id == 100) and fixtures or {} end
    crewCl.dlights, crewCl.sprites = {}, {}
    M.time = 800
    Frame(crewCl, V(256, 128, 64), points())
    local count = 0
    for _ in pairs(crewCl.dlights) do count = count + 1 end
    check(count == LE.Config.MaxEmergencyLights, "dynamic lights capped at " .. LE.Config.MaxEmergencyLights .. " (got " .. count .. ")")
    check(#crewCl.sprites == 30, "a glow on every fixture in the dark section")
    LE.GetSectionLights = real
end)

step("real map files: light fixtures out of the .bsp", function()
    local showroom = os.getenv("STM_SHOWROOM_BSP")
    local tf2 = os.getenv("TF2_TEST_BSP")
    if not showroom and not tf2 then
        print("  (skipped: set STM_SHOWROOM_BSP / TF2_TEST_BSP to real .bsp paths)")
        return
    end
    local LE = crewCl.LightingEditor
    if showroom then
        M.maps["maps/stm_showroom.bsp"] = showroom
        local lights = LE.ReadMapLights("maps/stm_showroom.bsp")
        check(lights and #lights == 584, "stm_showroom: 385 point + 199 spot lights from the HDR lump (got " .. tostring(lights and #lights) .. ")")
        local first = lights and lights[1]
        check(first and first.pos.x == 560 and first.pos.y == 208 and first.pos.z == 88, "first light at (560, 208, 88) like the independent reader")
        check(first and first.color.r == 255 and math.abs(first.color.b - 255 * 324.598388671875 / 392.1568908691406) < 0.01, "light color normalized from intensity")
    end
    if tf2 then
        M.maps["maps/test2.bsp"] = tf2
        local lights = LE.ReadMapLights("maps/test2.bsp")
        check(lights and #lights == 2, "test2: the 2 spotlights from the LDR lump, sky lights skipped")
    end
    local missing, err = LE.ReadMapLights("maps/nope.bsp")
    check(missing == nil and err:find("can't open"), "missing map explained")
end)

step("Helix chat commands", function()
    local registered = {}
    server.ix = { command = { Add = function(name, def) registered[name] = def end }, type = { string = 1, optional = 64 } }
    server.hook.Run("InitializedPlugins")
    check(registered.PowerOutage and registered.PowerRestore, "PowerOutage and PowerRestore registered")
    check(registered.PowerOutage.adminOnly, "admin only")
    local reply = registered.PowerRestore.OnRun(nil, admin, "1", "4A")
    check(reply and reply:find("restored") ~= nil, "PowerRestore works: " .. tostring(reply))
end)

for _, e in ipairs(M.errors) do print("logged: " .. e) end
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
