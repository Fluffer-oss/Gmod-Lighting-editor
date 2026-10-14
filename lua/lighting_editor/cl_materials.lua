local LE = LightingEditor
local Config = LE.Config

-- Everything inside the ship that's lit, and how each kind is darkened. Changing
-- a material parameter costs nothing (no lightmap rebuild), so this can fade.
--
--  world  Lightmapped surfaces: walls, floors, brush doors. $color scales only
--         the light from the lightmap (flashlights are drawn in a separate pass
--         it doesn't touch); $envmaptint scales the cubemap reflections.
--  model  Static props, props, doors, NPCs: $color2 scales their lighting,
--         $envmaptint their cubemap reflections and $phongboost their highlights.
--         Model shaders convert $color2 and $envmaptint from gamma to linear
--         before using them (world shaders don't), so these get the value
--         that comes out as the same linear scale as the world: see LE.ModelTint.
--  glow   Anything that gives off its own light: self-illuminated, additive and
--         unlit materials, sprites, and Config.LightMaterials. Its texture is
--         swapped for black, which beats any material proxy that animates its
--         color (STM's bridge lights use one).
--
-- Only materials used inside the ship are touched: world materials with most of
-- their area near a section, and props and entities near one. The hull's
-- outside, the skybox and STM's exterior keep their own lighting.

local WORLD, MODEL, GLOW = "world", "model", "glow"
LE.MaterialKinds = { WORLD = WORLD, MODEL = MODEL, GLOW = GLOW }

-- name -> tracked material, or false for materials that are left alone.
LE.Tracked = LE.Tracked or {}
local trackedList = {}
for _, tracked in pairs(LE.Tracked) do
    if tracked then table.insert(trackedList, tracked) end
end

-- Current lighting: k = how much light is left (1 = normal), lightsOff = glow off.
LE.Lighting = LE.Lighting or { k = 1, lightsOff = false }

local function HasFlag(flags, bit)
    return math.floor(flags / bit) % 2 == 1
end
local SELFILLUM, ADDITIVE = 64, 128

local lightSet
local function IsListedLight(name)
    if not lightSet then
        lightSet = {}
        for _, listed in ipairs(Config.LightMaterials or {}) do lightSet[LE.NormalizePath(listed)] = true end
    end
    return lightSet[name] == true
end

local function AlertMaterial()
    local alert = Star_Trek and Star_Trek.Alert
    return alert and isstring(alert.AlertMaterial) and LE.NormalizePath(alert.AlertMaterial) or nil
end

-- The map compiler gives every brush material near a cubemap its own copy,
-- "maps/<map>/<name>_<x>_<y>_<z>", which is what the world actually draws.
-- This is the name it was copied from.
function LE.BaseMaterialName(name)
    local base = name:match("^maps/[^/]+/(.+)$")
    if not base then return name end
    return (base:gsub("_%-?%d+_%-?%d+_%-?%d+$", ""))
end

-- Which kind a material is, or nil to leave it alone.
function LE.ClassifyMaterial(name, mat)
    local base = LE.BaseMaterialName(name)
    for _, pattern in ipairs(Config.KeepMaterials or {}) do
        if name:find(pattern) or base:find(pattern) then return nil end
    end
    -- STM drives the alert light material itself.
    if base == AlertMaterial() then return nil end
    if IsListedLight(base) then return GLOW end

    local shader = string.lower(mat:GetShader() or "")
    if shader:find("water", 1, true) or shader:find("refract", 1, true) or shader:find("sky", 1, true) then
        return nil
    end
    local flags = mat:GetInt("$flags") or 0
    if HasFlag(flags, SELFILLUM) or HasFlag(flags, ADDITIVE) or (mat:GetInt("$emissiveblendenabled") or 0) ~= 0
        or shader:find("unlit", 1, true) or shader:find("sprite", 1, true) then
        return GLOW
    end
    if shader:find("lightmapped", 1, true) or shader:find("worldvertextransition", 1, true) then
        return WORLD
    end
    if shader:find("vertexlit", 1, true) or shader:find("eyes", 1, true) or shader:find("teeth", 1, true) then
        return MODEL
    end
    return nil
end

--------------------------------------------------------------------------------
-- Changing materials
--------------------------------------------------------------------------------

local blackTexture
hook.Add("PreRender", "LightingEditor.BlackTexture", function()
    if blackTexture then return end
    blackTexture = GetRenderTarget("lightingeditor_black", 4, 4)
    render.PushRenderTarget(blackTexture)
    render.Clear(0, 0, 0, 255)
    render.PopRenderTarget()
    LE.SetLighting(LE.Lighting.k, LE.Lighting.lightsOff)
end)

-- The value to give a model's $color2 or $envmaptint so that, after the shader
-- converts it to linear (GammaToLinear: x^2.2, values above 1 left as they
-- are), it scales the light by k, the same as the world's $color.
local GAMMA = 2.2
function LE.ModelTint(original, k)
    local linear = (original > 1 and original or original ^ GAMMA) * k
    return linear > 1 and linear or linear ^ (1 / GAMMA)
end

local function ScaleVector(original, k, kind)
    if kind ~= MODEL then return original * k end
    return Vector(LE.ModelTint(original.x, k), LE.ModelTint(original.y, k), LE.ModelTint(original.z, k))
end

local function Apply(tracked)
    local lighting = LE.Lighting
    local mat = tracked.mat

    if tracked.kind == GLOW then
        local off = lighting.lightsOff and blackTexture ~= nil
        if tracked.off == off then return end
        tracked.off = off
        if tracked.texture then
            mat:SetTexture("$basetexture", off and blackTexture or tracked.texture)
        end
        for param, original in pairs(tracked.vectors) do
            mat:SetVector(param, off and Vector(0, 0, 0) or original)
        end
        return
    end

    if tracked.k == lighting.k then return end
    tracked.k = lighting.k
    for param, original in pairs(tracked.vectors) do
        mat:SetVector(param, ScaleVector(original, lighting.k, tracked.kind))
    end
    -- $phongboost is used as it is: linear.
    for param, original in pairs(tracked.floats) do
        mat:SetFloat(param, original * lighting.k)
    end
end

local function Track(name)
    name = LE.NormalizePath(name)
    local existing = LE.Tracked[name]
    if existing ~= nil then return existing or nil end

    local mat = Material(name)
    if not mat or mat:IsError() then return nil end
    local kind = LE.ClassifyMaterial(name, mat)
    if not kind then
        LE.Tracked[name] = false
        return nil
    end

    local tracked = { name = name, mat = mat, kind = kind, vectors = {}, floats = {}, k = 1, off = false }
    local function Vec(param, default)
        local value = mat:GetVector(param)
        if value then
            tracked.vectors[param] = Vector(value)
        elseif default then
            tracked.vectors[param] = Vector(1, 1, 1)
        end
    end
    local hasEnvmap = (mat:GetString("$envmap") or "") ~= ""

    if kind == WORLD then
        Vec("$color", true)
        if hasEnvmap then Vec("$envmaptint", true) end
    elseif kind == MODEL then
        Vec("$color2", true)
        if hasEnvmap then Vec("$envmaptint", true) end
        if (mat:GetInt("$phong") or 0) ~= 0 then
            tracked.floats["$phongboost"] = mat:GetFloat("$phongboost") or 1
        end
    else
        if (mat:GetString("$basetexture") or "") ~= "" then
            tracked.texture = mat:GetTexture("$basetexture")
        else
            Vec("$color", true)
            Vec("$color2", false)
        end
        if hasEnvmap then Vec("$envmaptint", true) end
        if (mat:GetInt("$emissiveblendenabled") or 0) ~= 0 then Vec("$emissiveblendtint", true) end
    end

    LE.Tracked[name] = tracked
    table.insert(trackedList, tracked)
    Apply(tracked)
    return tracked
end
LE.TrackMaterial = Track

-- Sets how much light is left (k, 1 = normal) and whether glowing things are off.
function LE.SetLighting(k, lightsOff)
    LE.Lighting.k, LE.Lighting.lightsOff = k, lightsOff
    for _, tracked in ipairs(trackedList) do
        Apply(tracked)
    end
end

--------------------------------------------------------------------------------
-- Finding what to darken
--------------------------------------------------------------------------------

local function Inside(pos)
    return LE.NearSection(pos, Config.InteriorDistance)
end

-- The materials a model actually uses: for each texture, the first candidate path that exists.
local resolvedModels = {}
local function ModelMaterials(model)
    local key = LE.NormalizePath(model)
    if resolvedModels[key] then return resolvedModels[key] end
    local result = {}
    for _, candidates in ipairs(LE.ModelMaterialCandidates(key)) do
        for _, candidate in ipairs(candidates) do
            local mat = Material(candidate)
            if mat and not mat:IsError() then
                table.insert(result, candidate)
                break
            end
        end
    end
    resolvedModels[key] = result
    return result
end

-- The map: world faces and static props. Runs as a coroutine; `pause` yields
-- when this frame's time budget is used up.
local function ScanWorld(pause)
    while not LE.GetDecks() do coroutine.yield() end

    -- The listed light fixtures go out wherever they're used, found or not.
    for _, name in ipairs(Config.LightMaterials or {}) do Track(name) end

    local area = {}
    local ok = LE.ScanMap(function(name, center, faceArea)
        local entry = area[name]
        if not entry then
            entry = { inside = 0, total = 0 }
            area[name] = entry
        end
        faceArea = math.max(faceArea, 1)
        entry.total = entry.total + faceArea
        if Inside(center) then entry.inside = entry.inside + faceArea end
    end, function(model, pos)
        if Inside(pos) then
            for _, name in ipairs(ModelMaterials(model)) do
                Track(name)
            end
        end
    end, pause)

    if ok then
        for name, entry in pairs(area) do
            if entry.inside >= entry.total * 0.5 or IsListedLight(LE.BaseMaterialName(name)) then Track(name) end
            pause()
        end
    else
        -- Can't read the map: everything the world uses, minus Config.KeepMaterials.
        for _, name in ipairs(game.GetWorld():GetMaterials() or {}) do
            Track(name)
        end
    end
    LE.WorldScanned = true
end

-- Entities come and go, so they're checked every second: props, doors, NPCs,
-- weapons and brush entities near a section.
local seenEntities = setmetatable({}, { __mode = "k" })
local function ScanEntities()
    if not LE.GetDecks() then return end
    for _, ent in ipairs(ents.GetAll()) do
        local model = IsValid(ent) and ent:GetModel()
        if model and seenEntities[ent] ~= model and not Config.KeepClasses[ent:GetClass()] and not ent:IsPlayer()
            and Inside(ent:WorldSpaceCenter()) then
            seenEntities[ent] = model
            for _, name in ipairs(ent:GetMaterials() or {}) do
                Track(name)
            end
            local override = ent:GetMaterial()
            if override and override ~= "" then Track(override) end
        end
    end
end

local scan = coroutine.create(ScanWorld)
local deadline = 0
local function Pause()
    if SysTime() > deadline then coroutine.yield() end
end
local nextEntityScan = 0

hook.Add("Think", "LightingEditor.Scan", function()
    if scan and coroutine.status(scan) ~= "dead" then
        deadline = SysTime() + Config.ScanBudget
        local ok, err = coroutine.resume(scan, Pause)
        if not ok then
            ErrorNoHalt("[Lighting] Couldn't scan the map: " .. tostring(err) .. "\n")
            scan = nil
        end
    end
    if CurTime() >= nextEntityScan then
        nextEntityScan = CurTime() + 1
        ScanEntities()
    end
end)
