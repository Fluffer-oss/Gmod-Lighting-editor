-- Builds real binary game files (map, model, texture) for the tests, in the
-- formats the engine uses, so the addon's readers are tested on actual bytes.
local F = {}

local function I32(v)
    if v < 0 then v = v + 4294967296 end
    local b = {}
    for i = 1, 4 do b[i] = string.char(v % 256) v = math.floor(v / 256) end
    return table.concat(b)
end
local function U16(v) if v < 0 then v = v + 65536 end return string.char(v % 256, math.floor(v / 256) % 256) end
local function F32(x)
    if x == 0 then return "\0\0\0\0" end
    local sign = x < 0 and 1 or 0
    local m, e = math.frexp(math.abs(x))          -- x = m * 2^e, 0.5 <= m < 1
    local mantissa = math.floor((m * 2 - 1) * 8388608 + 0.5)
    local exponent = e - 1 + 127
    local bits = sign * 2147483648 + exponent * 8388608 + mantissa
    return I32(bits >= 2147483648 and bits - 4294967296 or bits)
end
local function Pad(s, n) return s .. string.rep("\0", n - #s) end
F.I32, F.U16, F.F32 = I32, U16, F32

-- faces: { material, flags, area, verts = { {x,y,z}, ... } }
-- props: { model, pos = {x,y,z} }
function F.Map(faces, props)
    local names, nameIndex = {}, {}
    local texinfos, texdatas = {}, {}
    local vertexes, edges, surfedges, faceBytes = {}, { U16(0) .. U16(0) }, {}, {}
    local nverts, nedges = 0, 1
    for _, face in ipairs(faces) do
        if not nameIndex[face.material] then
            table.insert(names, face.material)
            nameIndex[face.material] = #names - 1
        end
        -- One texdata and texinfo per face keeps it simple.
        local data = #texdatas
        texdatas[#texdatas + 1] = F32(0.5) .. F32(0.5) .. F32(0.5) .. I32(nameIndex[face.material]) .. I32(64) .. I32(64) .. I32(64) .. I32(64)
        local info = #texinfos
        texinfos[#texinfos + 1] = string.rep("\0", 64) .. I32(face.flags or 0) .. I32(data)

        local first = #surfedges
        local base = nverts
        for _, v in ipairs(face.verts) do
            vertexes[#vertexes + 1] = F32(v[1]) .. F32(v[2]) .. F32(v[3])
            nverts = nverts + 1
        end
        for i = 0, #face.verts - 1 do
            local a, b = base + i, base + (i + 1) % #face.verts
            -- Alternate edge directions to exercise negative surfedges.
            if i % 2 == 0 then
                edges[#edges + 1] = U16(a) .. U16(b)
                surfedges[#surfedges + 1] = I32(nedges)
            else
                edges[#edges + 1] = U16(b) .. U16(a)
                surfedges[#surfedges + 1] = I32(-nedges)
            end
            nedges = nedges + 1
        end
        faceBytes[#faceBytes + 1] = U16(0) .. "\0\0" .. I32(first) .. U16(#face.verts) .. U16(info) .. U16(-1) .. U16(0)
            .. "\0\0\0\0" .. I32(0) .. F32(face.area or 100) .. string.rep("\0", 28)
    end

    local strData, strTable, offset = {}, {}, 0
    for _, name in ipairs(names) do
        strTable[#strTable + 1] = I32(offset)
        strData[#strData + 1] = name .. "\0"
        offset = offset + #name + 1
    end

    local lumps = {
        [2] = table.concat(texdatas), [3] = table.concat(vertexes), [6] = table.concat(texinfos),
        [7] = table.concat(faceBytes), [12] = table.concat(edges), [13] = table.concat(surfedges),
        [43] = table.concat(strData), [44] = table.concat(strTable)
    }

    -- Static props in the "sprp" game lump (version 10, 76-byte props).
    local models, modelIndex = {}, {}
    for _, prop in ipairs(props or {}) do
        if not modelIndex[prop.model] then
            table.insert(models, prop.model)
            modelIndex[prop.model] = #models - 1
        end
    end
    local sprp = { I32(#models) }
    for _, model in ipairs(models) do sprp[#sprp + 1] = Pad(model, 128) end
    sprp[#sprp + 1] = I32(0)
    sprp[#sprp + 1] = I32(#(props or {}))
    for _, prop in ipairs(props or {}) do
        sprp[#sprp + 1] = Pad(F32(prop.pos[1]) .. F32(prop.pos[2]) .. F32(prop.pos[3]) .. string.rep("\0", 12) .. U16(modelIndex[prop.model]), 76)
    end
    local sprpBytes = table.concat(sprp)

    -- Lay out: header, then each lump; the game lump points at sprp data placed last.
    local header = 8 + 64 * 16
    local body, directory = {}, {}
    local at = header
    for i = 0, 63 do
        local data = lumps[i]
        if i == 35 then data = "GAMELUMP_PLACEHOLDER" end
        if data and data ~= "GAMELUMP_PLACEHOLDER" then
            directory[i] = { at, #data }
            body[#body + 1] = data
            at = at + #data
        end
    end
    local gameLumpAt = at
    local gameLump = I32(1) .. I32(0x73707270) .. U16(0) .. U16(10) .. I32(gameLumpAt + 4 + 16) .. I32(#sprpBytes)
    directory[35] = { gameLumpAt, #gameLump }
    body[#body + 1] = gameLump .. sprpBytes

    local dir = {}
    for i = 0, 63 do
        local d = directory[i] or { 0, 0 }
        dir[#dir + 1] = I32(d[1]) .. I32(d[2]) .. I32(0) .. "\0\0\0\0"
    end
    return "VBSP" .. I32(20) .. table.concat(dir) .. table.concat(body)
end

-- A model whose textures are `textures` under the folders `folders`.
function F.Model(textures, folders)
    local headerSize = 220
    local textureAt = headerSize
    local folderOffsetsAt = textureAt + #textures * 64
    local stringsAt = folderOffsetsAt + #folders * 4
    local strings, stringAt = {}, stringsAt
    local function AddString(s)
        local at = stringAt
        strings[#strings + 1] = s .. "\0"
        stringAt = stringAt + #s + 1
        return at
    end
    local textureBytes = {}
    for i, name in ipairs(textures) do
        local structAt = textureAt + (i - 1) * 64
        textureBytes[i] = Pad(I32(AddString(name) - structAt), 64)
    end
    local folderBytes = {}
    for i, folder in ipairs(folders) do folderBytes[i] = I32(AddString(folder)) end

    local header = "IDST" .. I32(48) .. string.rep("\0", 196)
        .. I32(#textures) .. I32(textureAt) .. I32(#folders) .. I32(folderOffsetsAt)
    assert(#header == headerSize)
    return header .. table.concat(textureBytes) .. table.concat(folderBytes) .. table.concat(strings)
end

-- A texture whose average color is r, g, b.
function F.Texture(r, g, b)
    return "VTF\0" .. I32(7) .. I32(2) .. I32(80) .. U16(64) .. U16(64) .. I32(0) .. U16(1) .. U16(0) .. I32(0)
        .. F32(r) .. F32(g) .. F32(b) .. string.rep("\0", 36)
end

return F
