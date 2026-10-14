local LE = LightingEditor

-- Reads the positions and colors of the map's baked lights straight out of the
-- map's .bsp (the "worldlights" lump), so emergency lighting can sit on the real
-- light fixtures without anyone placing them. Point and spot lights only.
--
-- BSP layout: "VBSP", version, then 64 lumps of { offset, length, version, fourCC }.
-- Lump 15 = worldlights (LDR), lump 54 = worldlights (HDR); a map may have
-- either or both. Each light is 88 bytes (lump version 0) or 100 bytes
-- (version 1 adds a 12-byte shadow offset after the normal).

local LUMP_WORLDLIGHTS = 15
local LUMP_WORLDLIGHTS_HDR = 54
local EMIT_POINT, EMIT_SPOTLIGHT = 1, 2

local function ReadVector(f)
    return Vector(f:ReadFloat(), f:ReadFloat(), f:ReadFloat())
end

local function ReadLump(f, index)
    f:Seek(8 + index * 16)
    return f:ReadLong(), f:ReadLong(), f:ReadLong() -- offset, length, version
end

function LE.ReadMapLights(path)
    local f = file.Open(path, "rb", "GAME")
    if not f then return nil, "can't open " .. path end

    local lights = {}
    local ok, err = pcall(function()
        if f:Read(4) ~= "VBSP" then error("not a BSP file") end

        local offset, length, version = ReadLump(f, LUMP_WORLDLIGHTS)
        if length <= 0 then
            offset, length, version = ReadLump(f, LUMP_WORLDLIGHTS_HDR)
        end
        if length <= 0 then return end

        -- Some maps store lumps LZMA-compressed; the engine unpacks them, Lua can't.
        f:Seek(offset)
        if f:Read(4) == "LZMA" then error("this map's light data is compressed") end

        local size = version == 1 and 100 or 88
        for i = 0, math.floor(length / size) - 1 do
            local base = offset + i * size
            f:Seek(base)
            local origin = ReadVector(f)
            local intensity = ReadVector(f)
            f:Seek(base + (version == 1 and 48 or 36) + 4) -- skip normal (+shadow offset) and cluster
            local emitType = f:ReadLong()

            if emitType == EMIT_POINT or emitType == EMIT_SPOTLIGHT then
                local peak = math.max(intensity.x, intensity.y, intensity.z, 1e-6)
                table.insert(lights, {
                    pos = origin,
                    color = Color(255 * intensity.x / peak, 255 * intensity.y / peak, 255 * intensity.z / peak)
                })
            end
        end
    end)
    f:Close()

    if not ok then return nil, err end
    return lights
end

-- Lights grouped by Star Trek section, built once the sections have synced.
local MapLights
local SectionLights

function LE.GetSectionLights(deck, sectionId)
    if not SectionLights then
        if not LE.GetDecks() then return {} end

        if not MapLights then
            local lights, err = LE.ReadMapLights("maps/" .. game.GetMap() .. ".bsp")
            MapLights = lights or {}
            if err then
                ErrorNoHalt("[Lighting Editor] Couldn't read this map's lights (" .. tostring(err) .. "); emergency lights disabled.\n")
            end
        end

        SectionLights = {}
        for _, light in ipairs(MapLights) do
            local lightDeck, lightSection = LE.FindSection(light.pos)
            if lightDeck then
                local key = LE.SectionKey(lightDeck, lightSection)
                SectionLights[key] = SectionLights[key] or {}
                table.insert(SectionLights[key], light)
            end
        end
    end

    return SectionLights[LE.SectionKey(deck, sectionId)] or {}
end
