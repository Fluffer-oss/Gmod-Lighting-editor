local LE = LightingEditor
local Config = LE.Config

-- STM's own light sources keep working when the power's out, and give off real
-- light: LCARS screens and force fields. Each is a dynamic light (the nearest
-- Config.Emitters.MaxLights of them). While a deck is dark, the surfaces they
-- light are dimmed along with everything else, so their brightness is raised
-- to make up for some of it, at most Config.Emitters.MaxBoost times. Not all
-- of it: static props can't receive dynamic light, so lighting the walls much
-- more than the props around them would leave the props as black cutouts.

local BASE_INDEX = 0x4C450 -- dynamic light slots used here: BASE_INDEX + 0 .. MaxLights - 1

local function Unit(color)
    return Vector(color.r / 255, color.g / 255, color.b / 255)
end

--------------------------------------------------------------------------------
-- LCARS screens
--------------------------------------------------------------------------------

-- The average color of what a window shows: its elements' colors, or the red
-- alert palette while it's in that style.
local function WindowColor(window, lcars)
    if window.CurrentStyle == "LCARS_RED" and lcars.ColorRed then
        return Unit(lcars.ColorRed)
    end
    local sum, count = Vector(0, 0, 0), 0
    for _, element in pairs(window.Elements or {}) do
        local color = istable(element) and element.Color
        if istable(color) and color.r then
            sum = sum + Unit(color)
            count = count + 1
        end
    end
    if count > 0 then return sum * (1 / count) end
    return Unit(lcars.ColorOrange or Color(202, 151, 50))
end

local function LCARSEmitters(out)
    local lcars = Star_Trek and Star_Trek.LCARS
    local settings = Config.Emitters.LCARS
    if not (lcars and lcars.ActiveInterfaces and settings) then return end

    for _, interface in pairs(lcars.ActiveInterfaces) do
        local open = interface.AnimPos or 1
        if IsValid(interface.Ent) and open > 0 then
            for _, window in pairs(interface.Windows or {}) do
                local scale = window.WScale
                if window.WPosG and window.WAngG and scale and scale > 0 then
                    local width, height = (window.WWidth or 0) / scale, (window.WHeight or 0) / scale
                    if width > 0 and height > 0 then
                        -- A screen lights what's in front of it, more the bigger it is.
                        local normal = window.WAngG:Up()
                        local size = math.sqrt(width * height)
                        table.insert(out, {
                            pos = window.WPosG + normal * math.min(size * 0.5, 16),
                            color = WindowColor(window, lcars),
                            brightness = settings.Brightness * open,
                            radius = math.Clamp(size * settings.RadiusPerUnit, settings.MinRadius, settings.MaxRadius),
                            dir = normal
                        })
                    end
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Force fields
--------------------------------------------------------------------------------

-- A material's color: its texture's average color, tinted by $color and $color2.
local function MaterialColor(name)
    local mat = Material(name)
    if not mat or mat:IsError() then return nil end
    local color = LE.TextureColor(mat:GetString("$basetexture"))
    if not color then return nil end
    for _, param in ipairs({ "$color", "$color2" }) do
        local tint = mat:GetVector(param)
        if tint then color = Vector(color.x * tint.x, color.y * tint.y, color.z * tint.z) end
    end
    return color
end

-- Scaled so the brightest channel is 1: the light's hue, not the texture's darkness.
local function Saturate(color)
    local peak = math.max(color.x, color.y, color.z)
    if peak <= 0 then return nil end
    return color * (1 / peak)
end

local fieldColors = {}
local function ForceFieldEmitters(out)
    local settings = Config.Emitters.ForceFields
    if not settings then return end

    for _, ent in ipairs(ents.FindByClass("force_field")) do
        if IsValid(ent) and not ent:GetNoDraw() then
            local name = ent:GetMaterial()
            if not name or name == "" then name = (ent:GetMaterials() or {})[1] end
            if name then
                if fieldColors[name] == nil then
                    local color = MaterialColor(name)
                    fieldColors[name] = color and Saturate(color) or false
                end
                local color = fieldColors[name] or Vector(0.4, 0.7, 1)
                local tint = ent:GetColor()
                color = Vector(color.x * tint.r / 255, color.y * tint.g / 255, color.z * tint.b / 255)

                local extent = (ent:OBBMaxs() - ent:OBBMins()):Length() * 0.5
                table.insert(out, {
                    pos = ent:WorldSpaceCenter(),
                    color = color,
                    brightness = settings.Brightness * (tint.a / 255),
                    radius = math.Clamp(extent * settings.RadiusScale, settings.MinRadius, settings.MaxRadius)
                })
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Lighting them
--------------------------------------------------------------------------------

function LE.CollectEmitters()
    local out = {}
    LCARSEmitters(out)
    ForceFieldEmitters(out)
    return out
end

local emitters, nextCollect = {}, 0

hook.Add("Think", "LightingEditor.Emitters", function()
    local now = CurTime()
    local eye = EyePos()
    local settings = Config.Emitters

    -- Screens open and close and fields go up and down; a few times a second is plenty.
    if now >= nextCollect then
        nextCollect = now + 0.25
        emitters = {}
        local maxDistance = settings.Distance
        for _, emitter in ipairs(LE.CollectEmitters()) do
            emitter.distance = emitter.pos:Distance(eye)
            if emitter.distance - emitter.radius < maxDistance then table.insert(emitters, emitter) end
        end
        table.sort(emitters, function(a, b) return a.distance < b.distance end)
    end

    -- Make up for some of the darkness on the surfaces they light.
    local boost = math.min(1 / math.max(LE.LightLeft(1 - (LE.CurrentDarkness or 0), LE.MaterialKinds.WORLD), 0.01), settings.MaxBoost)

    for i = 1, math.min(#emitters, settings.MaxLights) do
        local emitter = emitters[i]
        local light = DynamicLight(BASE_INDEX + i - 1)
        if light then
            light.pos = emitter.pos
            light.r = math.floor(emitter.color.x * 255 + 0.5)
            light.g = math.floor(emitter.color.y * 255 + 0.5)
            light.b = math.floor(emitter.color.z * 255 + 0.5)
            light.brightness = emitter.brightness * boost
            light.size = emitter.radius
            light.decay = emitter.radius * 4
            light.dietime = now + 0.25
            if emitter.dir then
                light.dir = emitter.dir
                light.innerangle = 60
                light.outerangle = 170
            end
        end
    end
end)
