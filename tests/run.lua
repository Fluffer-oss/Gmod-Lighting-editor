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
local function Frame(realm, eye, points, forward)
    M.SetView(eye, points, forward)
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
    corridorFloorA = V(700, 128, 0),   -- 188 from the bridge: beyond its bleed
    corridorFloorB = V(640, 400, 0),
    engineFloor = V(950, 128, 0),      -- 182 from the corridor: beyond its bleed
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
    local tinted = false
    for _, px in ipairs(M.pixels) do if px.tint then tinted = true end end
    check(not tinted, "darkening only: no colored tint anywhere")
    check(#crewCl.sprites == 0 and next(crewCl.dlights) == nil, "no glow sprites or extra lights")
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

step("a whole deck goes dark, however many sections it has", function()
    local LE = crewCl.LightingEditor
    local decks = crewCl.Star_Trek.Sections.Decks
    -- A 6x6 grid of rooms around the viewer, all dark.
    local floors = {}
    for i = 0, 5 do
        for j = 0, 5 do
            local id = 2000 + i * 10 + j
            local x, y = 3000 + i * 300, j * 300
            decks[1].Sections[id] = { RealId = tostring(id), Name = "room", Areas = { area(x, y, 0, x + 300, y + 300, 128) } }
            LE.ClientOutages["1:" .. id] = { deck = 1, sectionId = id, out = true, changedAt = 0 }
            table.insert(floors, V(x + 150, y + 150, 0))
        end
    end
    M.time = 700
    crewCl.drawCalls = 0
    -- (Off the grid lines, or test rays run exactly along box edges, which a real GPU never double-counts but this mock would.)
    local d = Frame(crewCl, V(3911, 874, 61), floors)
    local all = true
    for i = 1, #floors do if math.abs(d[i] - DARK) > 1e-6 then all = false end end
    check(all, "all 36 rooms dark")
    local layers = LE.Config.BleedSteps + 1
    check(crewCl.drawCalls <= 2 * layers, "a few draw calls for the whole deck (" .. crewCl.drawCalls .. "), not some per section")
    check(balanced(crewCl), "render state restored")

    -- Past the box cap, the furthest boxes are the ones left out.
    local cap = LE.Config.MaxBoxesDrawn
    LE.Config.MaxBoxesDrawn = 9
    d = Frame(crewCl, V(3161, 124, 61), floors)
    LE.Config.MaxBoxesDrawn = cap
    local drawn = 0
    for i = 1, #floors do if d[i] > 0 then drawn = drawn + 1 end end
    check(math.abs(d[1] - DARK) < 1e-6 and d[#floors] == 0, "nearest room drawn, furthest not")
    check(drawn <= 9 + 8, "about the cap's worth of rooms darkened (" .. drawn .. ", counting bleed)")

    for id in pairs(decks[1].Sections) do if id >= 2000 then decks[1].Sections[id] = nil LE.ClientOutages["1:" .. id] = nil end end
end)

step("darkness bleeds past the section's boxes, fading out", function()
    crewCl.LightingEditor.ClientOutages = {}
    server.RunCmd(admin, "lighting_restore", { "ship" })
    server.RunCmd(admin, "lighting_outage", { "1", "1" })
    pump()
    M.time = 800
    local Config = crewCl.LightingEditor.Config
    local reach = Config.BoxPadding + Config.BleedDistance
    -- The bridge box is y 0..256; walk outward from its y = 0 side, in every direction.
    local offsets = { 2, 20, 50, 80, 110, reach - 2, reach + 10, 300 }
    local function walk(dir, base)
        local pts = {}
        for i, o in ipairs(offsets) do pts[i] = base + dir * o end
        return Frame(crewCl, V(256, 128, 64), pts)
    end
    for _, case in ipairs({
        { "-y", V(0, -1, 0), V(256, 0, 0) },
        { "-x", V(-1, 0, 0), V(0, 128, 0) },
        { "+z", V(0, 0, 1), V(256, 128, 128) },
        { "-z", V(0, 0, -1), V(256, 128, 0) }
    }) do
        local d = walk(case[2], case[3])
        check(d[1] > DARK * 0.9, case[1] .. ": just outside the box nearly fully dark (" .. d[1] .. ")")
        local falling = true
        for i = 2, 6 do if not (d[i] <= d[i - 1] and d[i] > 0) then falling = false end end
        check(falling, case[1] .. ": fades out with distance")
        check(d[7] == 0 and d[8] == 0, case[1] .. ": nothing past the bleed distance")
    end
end)

step("bleed into a neighbouring lit section; overlaps don't stack", function()
    M.time = 900
    -- Bridge (x < 512) dark, corridor (x 512..768) lit.
    local d = Frame(crewCl, V(256, 128, 64), { V(530, 128, 0), V(700, 128, 0) })
    check(d[1] > 0 and d[1] < DARK, "corridor floor near the dark bridge is dimmed")
    check(d[2] == 0, "corridor floor further in is lit")
    -- Both dark: the shared wall and the area around it are no darker than inside.
    server.RunCmd(admin, "lighting_outage", { "1", "4A" })
    pump()
    M.time = 1000
    local pts = { V(512, 128, 0), V(500, 128, 0), V(530, 128, 0), V(512, 128, 64), V(640, 400, 0) }
    d = Frame(crewCl, V(256, 128, 64), pts)
    local same = true
    for i = 1, #pts do if math.abs(d[i] - DARK) > 1e-6 then same = false end end
    check(same, "where two dark sections meet: exactly as dark as inside either")
end)

step("dark sections behind the camera aren't drawn", function()
    crewCl.drawCalls = 0
    Frame(crewCl, V(256, 1000, 64), { V(256, 1100, 0) }, V(0, 1, 0)) -- looking away from the ship
    check(crewCl.drawCalls == 0, "nothing drawn (" .. crewCl.drawCalls .. " draw calls)")
    crewCl.drawCalls = 0
    local d = Frame(crewCl, V(256, 1000, 64), { V(256, 128, 0) }, V(0, -1, 0)) -- looking at it
    check(crewCl.drawCalls > 0 and math.abs(d[1] - DARK) < 1e-6, "drawn when looking at it")
end)

step("sections at different darkness don't darken each other", function()
    local LE = crewCl.LightingEditor
    -- Bridge (and 4A) fully dark; engineering half way through its fade-in.
    LE.ClientOutages["1:500"] = { deck = 1, sectionId = 500, out = false, changedAt = M.time - LE.Config.FlickerInTime - LE.Config.FadeInTime / 2 }
    local engine = LE.SectionDarkness(LE.ClientOutages["1:500"], M.time)
    check(engine > 0 and engine < DARK, "engineering partly dark")
    local d = Frame(crewCl, V(256, 128, 64), { V(100, 128, 0), V(990, 128, 0) })
    check(math.abs(d[1] - DARK) < 1e-6, "bridge exactly as dark as before")
    check(math.abs(d[2] - engine) < 1e-6, "engineering exactly its own darkness")
    LE.ClientOutages["1:500"] = nil
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
