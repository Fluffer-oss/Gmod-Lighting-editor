local LE = LightingEditor
local Config = LE.Config

-- A section without power is darkened on screen, not in the map's baked
-- lighting: every frame, the stencil buffer marks the pixels whose surface lies
-- inside that section's boxes (world, props, players alike), and only those
-- pixels are darkened and washed red. A few draw calls per section, so turning
-- power off or on never rebuilds lightmaps and never freezes the game.

LE.ClientOutages = LE.ClientOutages or {}

local VolumeMaterial = CreateMaterial("lightingeditor_volume", "UnlitGeneric", {
    ["$basetexture"] = "vgui/white",
    ["$vertexcolor"] = 1,
    ["$nocull"] = 1
})
local GlowMaterial = Material("sprites/light_glow02_add")

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local function RequestState()
    net.Start(LE.NetRequest)
    net.SendToServer()
end

local function PlaySoundIfNear(deck, sectionId, soundPath)
    local section = LE.GetSection(deck, sectionId)
    local ply = LocalPlayer()
    if section and IsValid(ply) and soundPath and soundPath ~= ""
        and LE.DistanceToSection(section, ply:EyePos()) < Config.SoundDistance then
        surface.PlaySound(soundPath)
    end
end

net.Receive(LE.NetState, function()
    local incoming = {}
    for _ = 1, net.ReadUInt(12) do
        local entry = {
            deck = net.ReadUInt(8),
            sectionId = net.ReadUInt(16),
            out = net.ReadBool(),
            changedAt = net.ReadFloat()
        }
        incoming[LE.SectionKey(entry.deck, entry.sectionId)] = entry
    end

    for key, entry in pairs(incoming) do
        local previous = LE.ClientOutages[key]
        local isNewChange = not previous or previous.out ~= entry.out
        -- Only play the sound for changes happening now, not for a joiner's catch-up.
        if isNewChange and CurTime() - entry.changedAt < 1 then
            PlaySoundIfNear(entry.deck, entry.sectionId, entry.out and Config.Sounds.Out or Config.Sounds.Restore)
        end
    end

    LE.ClientOutages = incoming
end)

hook.Add("InitPostEntity", "LightingEditor.RequestState", RequestState)
if IsValid(LocalPlayer()) then RequestState() end

--------------------------------------------------------------------------------
-- How dark a section is right now (0 = normal, Config.DarkLevel = no power)
--------------------------------------------------------------------------------

-- A fixed stutter pattern, like a light style ("m" = on, "a" = off).
local FLICKER = "mmamammmmammamamaaamammmaaaam"

local function Flicker(t, seed)
    local index = (math.floor(t * 18) + seed) % #FLICKER + 1
    return FLICKER:sub(index, index) == "a"
end

function LE.SectionDarkness(entry, now)
    local t = now - entry.changedAt
    local seed = entry.sectionId % 7
    local dark = Config.DarkLevel

    if entry.out then
        if t < Config.FlickerOutTime then
            return Flicker(t, seed) and dark or 0
        end
        return dark * math.min(1, (t - Config.FlickerOutTime) / Config.FadeOutTime + 0.6)
    end

    if t < Config.FlickerInTime then
        return Flicker(t, seed) and dark or dark * 0.4
    end
    return dark * 0.4 * math.max(0, 1 - (t - Config.FlickerInTime) / Config.FadeInTime)
end

local function EmergencyPulse(entry, now)
    if not entry.out then return 0 end
    local t = now - entry.changedAt - Config.FlickerOutTime
    if t <= 0 then return 0 end
    local fadeIn = math.min(1, t / Config.FadeOutTime)
    return fadeIn * (0.55 + 0.45 * math.sin(now * math.pi * 2 / Config.PulsePeriod))
end

--------------------------------------------------------------------------------
-- Marking a section's pixels in the stencil buffer
--------------------------------------------------------------------------------

-- Bit layout: bits 0-6 are scratch for the box being tested, bit 7 means
-- "this pixel's surface is inside the section".
local INSIDE_BIT = 128
local SCRATCH = 127

local function FullScreen(color)
    cam.Start2D()
    surface.SetDrawColor(color.r, color.g, color.b, color.a)
    surface.DrawRect(0, 0, ScrW(), ScrH())
    cam.End2D()
end

-- The six faces of an axis-aligned box, each with which side of it is "outside".
local function BoxFaces(min, max)
    local x1, y1, z1, x2, y2, z2 = min.x, min.y, min.z, max.x, max.y, max.z
    return {
        { axis = "x", outside = x2, sign = 1,  quad = { Vector(x2, y1, z1), Vector(x2, y2, z1), Vector(x2, y2, z2), Vector(x2, y1, z2) } },
        { axis = "x", outside = x1, sign = -1, quad = { Vector(x1, y1, z1), Vector(x1, y1, z2), Vector(x1, y2, z2), Vector(x1, y2, z1) } },
        { axis = "y", outside = y2, sign = 1,  quad = { Vector(x1, y2, z1), Vector(x1, y2, z2), Vector(x2, y2, z2), Vector(x2, y2, z1) } },
        { axis = "y", outside = y1, sign = -1, quad = { Vector(x1, y1, z1), Vector(x2, y1, z1), Vector(x2, y1, z2), Vector(x1, y1, z2) } },
        { axis = "z", outside = z2, sign = 1,  quad = { Vector(x1, y1, z2), Vector(x2, y1, z2), Vector(x2, y2, z2), Vector(x1, y2, z2) } },
        { axis = "z", outside = z1, sign = -1, quad = { Vector(x1, y1, z1), Vector(x1, y2, z1), Vector(x2, y2, z1), Vector(x2, y1, z1) } }
    }
end

local function DrawFaces(faces)
    for _, face in ipairs(faces) do
        local q = face.quad
        render.DrawQuad(q[1], q[2], q[3], q[4], color_white)
    end
end

-- Sets INSIDE_BIT on every pixel whose visible surface is inside the box.
-- Faces facing away from the camera ("back") are behind any surface that's inside
-- the box or in front of it: their depth test fails there. Faces toward the camera
-- ("front") are in front of any surface that's inside or behind the box: their
-- depth test passes there. Inside = both. With the camera inside the box there
-- are no front faces, so the first test alone decides.
local function MarkBox(min, max, eye)
    local pad = Config.BoxPadding
    min = min - Vector(pad, pad, pad)
    max = max + Vector(pad, pad, pad)

    local front, back = {}, {}
    for _, face in ipairs(BoxFaces(min, max)) do
        local isFront = face.sign > 0 and eye[face.axis] > face.outside or face.sign < 0 and eye[face.axis] < face.outside
        table.insert(isFront and front or back, face)
    end

    -- Clear the scratch bits.
    render.SetStencilWriteMask(SCRATCH)
    render.SetStencilTestMask(0)
    render.SetStencilReferenceValue(0)
    render.SetStencilCompareFunction(STENCIL_ALWAYS)
    render.SetStencilPassOperation(STENCIL_REPLACE)
    render.SetStencilZFailOperation(STENCIL_REPLACE)
    FullScreen(color_white)

    -- Back faces whose depth test fails: the surface is in front of the box's far side.
    render.SetStencilReferenceValue(1)
    render.SetStencilPassOperation(STENCIL_KEEP)
    render.SetStencilZFailOperation(STENCIL_REPLACE)
    DrawFaces(back)

    local insideValue = 1
    if #front > 0 then
        -- ...and front faces whose depth test passes: it's also behind the near side.
        render.SetStencilTestMask(SCRATCH)
        render.SetStencilCompareFunction(STENCIL_EQUAL)
        render.SetStencilPassOperation(STENCIL_INCR)
        render.SetStencilZFailOperation(STENCIL_KEEP)
        DrawFaces(front)
        insideValue = 2
    end

    -- Promote "inside this box" to the section's inside bit.
    render.SetStencilTestMask(SCRATCH)
    render.SetStencilCompareFunction(STENCIL_EQUAL)
    render.SetStencilWriteMask(INSIDE_BIT)
    render.SetStencilReferenceValue(INSIDE_BIT + insideValue)
    render.SetStencilPassOperation(STENCIL_REPLACE)
    render.SetStencilZFailOperation(STENCIL_KEEP)
    FullScreen(color_white)
end

local function DrawSectionDarkness(section, darkness, pulse, eye)
    render.SetStencilEnable(true)
    render.ClearStencil()
    render.SetStencilFailOperation(STENCIL_KEEP)

    render.SetMaterial(VolumeMaterial)
    render.OverrideColorWriteEnable(true, false)
    render.OverrideDepthEnable(true, false)
    for _, area in ipairs(section.Areas or {}) do
        MarkBox(area.Min, area.Max, eye)
    end
    render.OverrideDepthEnable(false, false)
    render.OverrideColorWriteEnable(false, false)

    render.SetStencilWriteMask(0)
    render.SetStencilTestMask(INSIDE_BIT)
    render.SetStencilReferenceValue(INSIDE_BIT)
    render.SetStencilCompareFunction(STENCIL_EQUAL)
    render.SetStencilPassOperation(STENCIL_KEEP)
    render.SetStencilZFailOperation(STENCIL_KEEP)

    FullScreen(Color(0, 0, 0, 255 * darkness))
    if pulse > 0 then
        local c = Config.EmergencyColor
        FullScreen(Color(c.r, c.g, c.b, 255 * Config.EmergencyTint * pulse))
    end

    render.SetStencilEnable(false)
end

--------------------------------------------------------------------------------
-- Frame
--------------------------------------------------------------------------------

-- The dark sections worth drawing this frame: nearest first, capped.
local function ActiveSections(eye, now)
    local active = {}
    for _, entry in pairs(LE.ClientOutages) do
        local section = LE.GetSection(entry.deck, entry.sectionId)
        if section then
            local darkness = LE.SectionDarkness(entry, now)
            local distance = LE.DistanceToSection(section, eye)
            if darkness > 0.005 and distance < Config.SectionDrawDistance then
                table.insert(active, { entry = entry, section = section, darkness = darkness, distance = distance })
            end
        end
    end
    table.sort(active, function(a, b) return a.distance < b.distance end)
    for i = #active, Config.MaxSectionsDrawn + 1, -1 do
        active[i] = nil
    end
    return active
end

local DrawnThisFrame = {}

hook.Add("PostDrawTranslucentRenderables", "LightingEditor.Outages", function(drawingDepth, drawingSkybox, drawing3DSkybox)
    if drawingDepth or drawingSkybox or drawing3DSkybox then return end

    local eye, now = EyePos(), CurTime()
    DrawnThisFrame = ActiveSections(eye, now)

    for _, item in ipairs(DrawnThisFrame) do
        item.pulse = EmergencyPulse(item.entry, now)
        DrawSectionDarkness(item.section, item.darkness, item.pulse, eye)
    end

    -- Red glows on the dead section's light fixtures, drawn after the darkening.
    local glows = 0
    render.SetMaterial(GlowMaterial)
    for _, item in ipairs(DrawnThisFrame) do
        if item.pulse > 0 then
            local c = Config.EmergencyColor
            local color = Color(c.r, c.g, c.b, 255 * item.pulse)
            for _, light in ipairs(LE.GetSectionLights(item.entry.deck, item.entry.sectionId)) do
                if glows >= Config.MaxFixtureGlows then break end
                render.DrawSprite(light.pos, Config.FixtureGlowSize, Config.FixtureGlowSize, color)
                glows = glows + 1
            end
        end
    end
end)

-- A few real (dynamic) red lights at the nearest dead fixtures, so the
-- emergency lighting actually lights the room around them.
hook.Add("Think", "LightingEditor.EmergencyLights", function()
    if #DrawnThisFrame == 0 then return end

    local eye = EyePos()
    local candidates = {}
    for _, item in ipairs(DrawnThisFrame) do
        if item.pulse and item.pulse > 0 then
            for _, light in ipairs(LE.GetSectionLights(item.entry.deck, item.entry.sectionId)) do
                table.insert(candidates, { pos = light.pos, pulse = item.pulse, dist = eye:DistToSqr(light.pos) })
            end
        end
    end
    table.sort(candidates, function(a, b) return a.dist < b.dist end)

    local c = Config.EmergencyColor
    for i = 1, math.min(#candidates, Config.MaxEmergencyLights) do
        local dlight = DynamicLight(4200 + i)
        if dlight then
            dlight.pos = candidates[i].pos
            dlight.r, dlight.g, dlight.b = c.r, c.g, c.b
            dlight.brightness = 0.6 + candidates[i].pulse
            dlight.size = Config.EmergencyLightSize
            dlight.decay = 0
            dlight.dietime = CurTime() + 0.2
        end
    end
end)
