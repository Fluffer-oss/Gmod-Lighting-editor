local LE = LightingEditor

-- Reads what the client can't ask the engine for: which material every world
-- face uses and where it is, where the static props are, which materials a
-- model uses, and a texture's average color. All straight from the game files,
-- read-only; protected maps work as long as the game itself can load them.

local function U16(s, i) local a, b = s:byte(i, i + 1) return a + b * 256 end
local function I16(s, i) local v = U16(s, i) return v >= 32768 and v - 65536 or v end
local function I32(s, i)
    local a, b, c, d = s:byte(i, i + 3)
    local v = a + b * 256 + c * 65536 + d * 16777216
    return v >= 2147483648 and v - 4294967296 or v
end
local function F32(s, i)
    local b1, b2, b3, b4 = s:byte(i, i + 3)
    local sign = b4 > 127 and -1 or 1
    local exponent = (b4 % 128) * 2 + math.floor(b3 / 128)
    local mantissa = (b3 % 128) * 65536 + b2 * 256 + b1
    if exponent == 0 then return sign * math.ldexp(mantissa, -149) end
    if exponent == 255 then return 0 end
    return sign * math.ldexp(1 + mantissa / 8388608, exponent - 127)
end
local function CString(s, i)
    local stop = s:find("\0", i, true)
    return s:sub(i, (stop or #s + 1) - 1)
end

LE.Bytes = { U16 = U16, I16 = I16, I32 = I32, F32 = F32 }

local function NormalizePath(path)
    path = string.lower(path):gsub("\\", "/"):gsub("/+", "/")
    return (path:gsub("^/", ""):gsub("%.vmt$", ""))
end
LE.NormalizePath = NormalizePath

local LUMP_TEXDATA, LUMP_VERTEXES, LUMP_TEXINFO, LUMP_FACES = 2, 3, 6, 7
local LUMP_EDGES, LUMP_SURFEDGES, LUMP_GAME = 12, 13, 35
local LUMP_TEXDATA_STRING_DATA, LUMP_TEXDATA_STRING_TABLE, LUMP_FACES_HDR = 43, 44, 58
-- Faces that aren't drawn as lit surfaces: 2D sky, sky, nodraw, skip.
local function Skipped(flags)
    for _, bit in ipairs({ 0x2, 0x4, 0x80, 0x200 }) do
        if math.floor(flags / bit) % 2 == 1 then return true end
    end
    return false
end
local SPRP = 0x73707270                      -- "sprp"

-- Scans the current map. Calls onFace(materialName, center, area) for every
-- drawn world face and onStaticProp(modelPath, origin) for every static prop.
-- `pause` is called now and then so the caller can spread the work over frames.
-- Returns false and a reason if the map can't be read.
function LE.ScanMap(onFace, onStaticProp, pause)
    local f = file.Open("maps/" .. game.GetMap() .. ".bsp", "rb", "GAME")
    if not f then return false, "map file not readable" end

    local header = f:Read(8 + 64 * 16)
    if not header or #header < 8 + 64 * 16 or header:sub(1, 4) ~= "VBSP" then
        f:Close()
        return false, "not a Source map"
    end
    local function Lump(index)
        local base = 9 + index * 16
        local offset, length = I32(header, base), I32(header, base + 4)
        if length <= 0 then return "", offset end
        f:Seek(offset)
        return f:Read(length) or "", offset
    end

    local stringData, stringTable = Lump(LUMP_TEXDATA_STRING_DATA), Lump(LUMP_TEXDATA_STRING_TABLE)
    local texdata, texinfo = Lump(LUMP_TEXDATA), Lump(LUMP_TEXINFO)
    local vertexes, edges, surfedges = Lump(LUMP_VERTEXES), Lump(LUMP_EDGES), Lump(LUMP_SURFEDGES)
    local faces = Lump(LUMP_FACES)
    if #faces == 0 then faces = Lump(LUMP_FACES_HDR) end
    pause()

    local texdataNames = {}
    for i = 0, #texdata / 32 - 1 do
        local nameIndex = I32(texdata, i * 32 + 13)
        texdataNames[i] = NormalizePath(CString(stringData, I32(stringTable, nameIndex * 4 + 1) + 1))
    end

    local function Vertex(index)
        local at = index * 12 + 1
        return F32(vertexes, at), F32(vertexes, at + 4), F32(vertexes, at + 8)
    end

    for i = 0, #faces / 56 - 1 do
        local at = i * 56
        local firstEdge, edgeCount = I32(faces, at + 5), I16(faces, at + 9)
        local info = I16(faces, at + 11)
        if info >= 0 and edgeCount > 0 then
            local infoAt = info * 72
            local flags, data = I32(texinfo, infoAt + 65), I32(texinfo, infoAt + 69)
            local name = texdataNames[data]
            if name and not Skipped(flags) then
                local x, y, z = 0, 0, 0
                for e = 0, edgeCount - 1 do
                    local surfedge = I32(surfedges, (firstEdge + e) * 4 + 1)
                    local edgeAt = math.abs(surfedge) * 4 + 1
                    local vx, vy, vz = Vertex(surfedge >= 0 and U16(edges, edgeAt) or U16(edges, edgeAt + 2))
                    x, y, z = x + vx, y + vy, z + vz
                end
                onFace(name, Vector(x / edgeCount, y / edgeCount, z / edgeCount), F32(faces, at + 25))
            end
        end
        if i % 500 == 0 then pause() end
    end

    -- Static props live in the "sprp" game lump.
    local gameLump = Lump(LUMP_GAME)
    for g = 0, (#gameLump >= 4 and I32(gameLump, 1) or 0) - 1 do
        local at = 5 + g * 16
        local compressed = U16(gameLump, at + 4) % 2 == 1
        if I32(gameLump, at) == SPRP and not compressed then
            f:Seek(I32(gameLump, at + 8))
            local sprp = f:Read(I32(gameLump, at + 12)) or ""
            local dictCount = I32(sprp, 1)
            local models = {}
            for d = 0, dictCount - 1 do
                models[d] = NormalizePath(CString(sprp, 5 + d * 128))
            end
            local p = 5 + dictCount * 128
            p = p + 4 + I32(sprp, p) * 2 -- leaf list
            local propCount = I32(sprp, p)
            p = p + 4
            local size = propCount > 0 and (#sprp - p + 1) / propCount or 0
            if size >= 26 and size == math.floor(size) then
                for n = 0, propCount - 1 do
                    local propAt = p + n * size
                    local model = models[U16(sprp, propAt + 24)]
                    if model then
                        onStaticProp(model, Vector(F32(sprp, propAt), F32(sprp, propAt + 4), F32(sprp, propAt + 8)))
                    end
                    if n % 500 == 0 then pause() end
                end
            end
        end
    end

    f:Close()
    return true
end

-- The materials a model can use (every skin), as candidate paths: each texture
-- name under each of the model's material folders. Callers keep the ones that exist.
local modelCache = {}
function LE.ModelMaterialCandidates(model)
    model = NormalizePath(model)
    if modelCache[model] then return modelCache[model] end

    local result = {}
    modelCache[model] = result
    local f = file.Open(model, "rb", "GAME")
    if not f then return result end

    local function ReadAt(offset, length)
        f:Seek(offset)
        return f:Read(length) or ""
    end
    local header = ReadAt(0, 220)
    if #header == 220 and header:sub(1, 4) == "IDST" then
        local textureCount, textureOffset = I32(header, 205), I32(header, 209)
        local folderCount, folderOffset = I32(header, 213), I32(header, 217)
        local folders = {}
        local folderOffsets = ReadAt(folderOffset, folderCount * 4)
        for i = 0, folderCount - 1 do
            folders[#folders + 1] = CString(ReadAt(I32(folderOffsets, i * 4 + 1), 256), 1)
        end
        for i = 0, math.min(textureCount, 256) - 1 do
            local at = textureOffset + i * 64
            local name = CString(ReadAt(at + I32(ReadAt(at, 4), 1), 256), 1)
            local candidates = {}
            for _, folder in ipairs(folders) do
                candidates[#candidates + 1] = NormalizePath(folder .. "/" .. name)
            end
            result[#result + 1] = candidates
        end
    end
    f:Close()
    return result
end

-- A texture's average color (0-1 per channel), from the reflectivity value the
-- texture compiler stores in every .vtf. nil if it can't be read.
local colorCache = {}
function LE.TextureColor(texture)
    if not texture or texture == "" then return nil end
    texture = NormalizePath(texture):gsub("%.vtf$", "")
    if colorCache[texture] ~= nil then return colorCache[texture] or nil end

    local color = false
    local f = file.Open("materials/" .. texture .. ".vtf", "rb", "GAME")
    if f then
        local header = f:Read(48) or ""
        if #header >= 44 and header:sub(1, 4) == "VTF\0" then
            color = Vector(F32(header, 33), F32(header, 37), F32(header, 41))
        end
        f:Close()
    end
    colorCache[texture] = color
    return color or nil
end
