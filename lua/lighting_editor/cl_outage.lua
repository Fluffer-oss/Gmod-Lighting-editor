local LE = LightingEditor
local Config = LE.Config

-- A section without power is darkened on screen, not in the map's baked
-- lighting: every frame, the stencil buffer marks the pixels whose surface lies
-- inside the dark sections' boxes (world, props, players alike), and only those
-- pixels are darkened. A few draw calls in all, however many sections are dark,
-- so turning power off or on never rebuilds lightmaps and never freezes the game.

LE.ClientOutages = LE.ClientOutages or {}

local VolumeMaterial = CreateMaterial("lightingeditor_volume", "UnlitGeneric", {
    ["$basetexture"] = "vgui/white",
    ["$vertexcolor"] = 1,
    ["$nocull"] = 1
})

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

--------------------------------------------------------------------------------
-- Marking dark pixels in the stencil buffer
--------------------------------------------------------------------------------

-- Shadow-volume counting: every box face that's behind a pixel's surface counts
-- +1 if it faces away from the camera and -1 if it faces it. A surface inside a
-- box has exactly one more such back face than front faces; outside every box,
-- they cancel. So a nonzero stencil means "inside at least one box", however
-- many boxes overlap, and wherever the camera is.
--
-- Bleed: STM's boxes rarely cover a room exactly, so the darkness also spreads
-- past them in every direction. The boxes are drawn again in a few layers, each
-- a bit bigger, and each layer darkens its pixels by an equal share: fully dark
-- inside the boxes, fading out to nothing Config.BleedDistance past them.

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

-- All the given quads in one draw call.
local function DrawQuads(quads)
    if #quads == 0 then return end
    mesh.Begin(MATERIAL_QUADS, #quads)
    for _, q in ipairs(quads) do
        for i = 1, 4 do
            mesh.Position(q[i])
            mesh.Color(255, 255, 255, 255)
            mesh.AdvanceVertex()
        end
    end
    mesh.End()
end

-- Marks every pixel whose surface is inside any of the boxes (grown by `pad`).
local function MarkBoxes(boxes, pad, eye)
    local grow = Vector(pad, pad, pad)
    local front, back = {}, {}
    for _, box in ipairs(boxes) do
        for _, face in ipairs(BoxFaces(box.Min - grow, box.Max + grow)) do
            local isFront = face.sign > 0 and eye[face.axis] > face.outside or face.sign < 0 and eye[face.axis] < face.outside
            table.insert(isFront and front or back, face.quad)
        end
    end

    render.ClearStencil()
    render.SetStencilWriteMask(255)
    render.SetStencilTestMask(255)
    render.SetStencilReferenceValue(0)
    render.SetStencilCompareFunction(STENCIL_ALWAYS)
    render.SetStencilPassOperation(STENCIL_KEEP)
    render.SetStencilFailOperation(STENCIL_KEEP)

    render.SetStencilZFailOperation(STENCIL_INCR)
    DrawQuads(back)
    render.SetStencilZFailOperation(STENCIL_DECR)
    DrawQuads(front)
end

-- Darkens the boxes to `darkness`, with the bleed around them.
local function DrawDarkness(boxes, darkness, eye)
    local steps = math.max(0, math.floor(Config.BleedSteps))
    local layers = steps + 1
    -- Layers stack multiplicatively: `layers` of them make exactly `darkness`.
    local alpha = 1 - (1 - darkness) ^ (1 / layers)

    render.SetStencilEnable(true)
    render.SetMaterial(VolumeMaterial)
    for layer = 0, steps do
        local pad = Config.BoxPadding + (steps > 0 and Config.BleedDistance * layer / steps or 0)

        render.OverrideColorWriteEnable(true, false)
        render.OverrideDepthEnable(true, false)
        MarkBoxes(boxes, pad, eye)
        render.OverrideDepthEnable(false, false)
        render.OverrideColorWriteEnable(false, false)

        render.SetStencilWriteMask(0)
        render.SetStencilCompareFunction(STENCIL_NOTEQUAL)
        render.SetStencilZFailOperation(STENCIL_KEEP)
        FullScreen(Color(0, 0, 0, 255 * alpha))
    end
    render.SetStencilEnable(false)
end

--------------------------------------------------------------------------------
-- Frame
--------------------------------------------------------------------------------

-- Whether the box (with its bleed) is entirely behind the camera.
local function BehindCamera(box, reach, eye, forward)
    for _, x in ipairs({ box.Min.x - reach, box.Max.x + reach }) do
        for _, y in ipairs({ box.Min.y - reach, box.Max.y + reach }) do
            for _, z in ipairs({ box.Min.z - reach, box.Max.z + reach }) do
                if (x - eye.x) * forward.x + (y - eye.y) * forward.y + (z - eye.z) * forward.z > 0 then
                    return false
                end
            end
        end
    end
    return true
end

-- The boxes of every dark section in view, grouped by how dark they are right
-- now (sections flicker separately, then all settle at the same darkness). The
-- nearest Config.MaxBoxesDrawn boxes are drawn; a whole deck is usually far fewer.
local function DarkGroups(eye, forward, now)
    local reach = Config.BoxPadding + Config.BleedDistance
    local boxes = {}
    for _, entry in pairs(LE.ClientOutages) do
        local section = LE.GetSection(entry.deck, entry.sectionId)
        local darkness = section and LE.SectionDarkness(entry, now) or 0
        if darkness > 0.005 then
            for _, box in ipairs(section.Areas or {}) do
                local distance = LE.DistanceToBox(box, eye)
                if distance < Config.SectionDrawDistance + reach and not BehindCamera(box, reach, eye, forward) then
                    table.insert(boxes, { box = box, darkness = darkness, distance = distance })
                end
            end
        end
    end
    table.sort(boxes, function(a, b) return a.distance < b.distance end)

    local groups, byDarkness = {}, {}
    for i = 1, math.min(#boxes, Config.MaxBoxesDrawn) do
        local item = boxes[i]
        local group = byDarkness[item.darkness]
        if not group then
            group = { darkness = item.darkness, boxes = {} }
            byDarkness[item.darkness] = group
            table.insert(groups, group)
        end
        table.insert(group.boxes, item.box)
    end
    return groups
end

hook.Add("PostDrawTranslucentRenderables", "LightingEditor.Outages", function(drawingDepth, drawingSkybox, drawing3DSkybox)
    if drawingDepth or drawingSkybox or drawing3DSkybox then return end

    local eye = EyePos()
    for _, group in ipairs(DarkGroups(eye, EyeAngles():Forward(), CurTime())) do
        DrawDarkness(group.boxes, group.darkness, eye)
    end
end)
