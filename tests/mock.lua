-- Minimal Garry's Mod environment for running the addon in plain Lua 5.1.
-- Includes a tiny software stencil/depth buffer: each "pixel" is a ray from the
-- camera to a known scene surface point, and draw calls apply real depth-test and
-- stencil rules to it. That lets tests check which surfaces end up darkened.

local M = {}
local ADDON_LUA = os.getenv("ADDON_LUA") or (HARNESS_DIR .. "../lua/")

---------------------------------------------------------------- GMod extensions
function math.Clamp(v, lo, hi) return math.min(math.max(v, lo), hi) end
function string.Trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end

local VEC = {}
VEC.__index = VEC
local function Vector(x, y, z)
    if type(x) == "table" then return setmetatable({ x = x.x, y = x.y, z = x.z }, VEC) end
    return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VEC)
end
VEC.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
VEC.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
VEC.__mul = function(a, b) if type(a) == "number" then a, b = b, a end return Vector(a.x * b, a.y * b, a.z * b) end
function VEC:Dot(o) return self.x * o.x + self.y * o.y + self.z * o.z end
function VEC:Cross(o) return Vector(self.y * o.z - self.z * o.y, self.z * o.x - self.x * o.z, self.x * o.y - self.y * o.x) end
function VEC:Length() return math.sqrt(self:Dot(self)) end
function VEC:DistToSqr(o) local d = self - o return d:Dot(d) end
function VEC:GetNormalized() local l = self:Length() return Vector(self.x / l, self.y / l, self.z / l) end
M.Vector = Vector

local COLOR = {}
local function Color(r, g, b, a) return setmetatable({ r = r, g = g, b = b, a = a or 255 }, COLOR) end

---------------------------------------------------------------- bit ops (8-bit)
local function band(a, b)
    local r, bit = 0, 1
    for _ = 1, 8 do
        if a % 2 == 1 and b % 2 == 1 then r = r + bit end
        a, b, bit = math.floor(a / 2), math.floor(b / 2), bit * 2
    end
    return r
end
local function bnot(a) return 255 - a end
local function bor(a, b) return a + b - band(a, b) end

---------------------------------------------------------------- shared world
M.queueToServer, M.queueToClients, M.pooled = {}, {}, {}
M.time = 100
M.errors = {}

function M.MakePlayer(name, admin)
    local p = { __valid = true, name = name, admin = admin, pos = Vector(0, 0, 0), chat = {} }
    function p:IsAdmin() return self.admin end
    function p:GetPos() return self.pos end
    function p:EyePos() return self.pos + Vector(0, 0, 64) end
    function p:WorldSpaceCenter() return self.pos + Vector(0, 0, 36) end
    function p:SteamID64() return "7656119" .. #name end
    function p:ChatPrint(m) table.insert(self.chat, m) end
    return p
end

function M.NewRealm(isServer, localPlayer)
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.SERVER, env.CLIENT = isServer, not isServer
    env.Vector, env.Color = Vector, Color
    env.color_white = Color(255, 255, 255)
    env.istable = function(v) return type(v) == "table" end
    env.isvector = function(v) return getmetatable(v) == VEC end
    env.IsValid = function(v) return type(v) == "table" and rawget(v, "__valid") == true end
    env.CurTime = function() return M.time end
    env.ErrorNoHalt = function(m) table.insert(M.errors, m) end
    env.AddCSLuaFile = function() end
    env.game = { GetMap = function() return M.mapName or "rp_test" end }
    env.include = function(path)
        local chunk = assert(loadfile(ADDON_LUA .. path))
        setfenv(chunk, env)
        return chunk()
    end
    env.util = { AddNetworkString = function(n) assert(isServer) M.pooled[n] = true end }
    env.bit = { bor = bor, band = band }
    env.print = function(...) env.printed = table.concat({ ... }, " ") end

    local hooks = {}
    env.hook = {
        Add = function(e, n, f) hooks[e] = hooks[e] or {} hooks[e][n] = f end,
        Run = function(e, ...)
            local names = {}
            for n in pairs(hooks[e] or {}) do table.insert(names, n) end
            table.sort(names)
            for _, n in ipairs(names) do
                local a, b = hooks[e][n](...)
                if a ~= nil then return a, b end
            end
        end
    }
    local commands = {}
    env.concommand = { Add = function(n, f) commands[n] = f end }
    env.RunCmd = function(ply, name, args) assert(commands[name], name)(ply, name, args or {}) end

    -- net with read/write type checking
    local receivers, out, inc = {}, nil, nil
    env.net = {
        Receive = function(n, f) receivers[n] = f end,
        Start = function(n) assert(M.pooled[n], "unpooled " .. n) out = { name = n, fields = {} } end,
        WriteUInt = function(v, bits) assert(v >= 0 and v < 2 ^ bits, "WriteUInt overflow") table.insert(out.fields, { "uint" .. bits, v }) end,
        WriteBool = function(v) assert(type(v) == "boolean") table.insert(out.fields, { "bool", v }) end,
        WriteFloat = function(v) assert(type(v) == "number") table.insert(out.fields, { "float", v }) end,
        Send = function(t) table.insert(M.queueToClients, { msg = out, target = t }) end,
        Broadcast = function() table.insert(M.queueToClients, { msg = out }) end,
        SendToServer = function() table.insert(M.queueToServer, { msg = out, sender = localPlayer }) end
    }
    local function reader(kind)
        return function(bits)
            local f = table.remove(inc.fields, 1)
            assert(f, "read past end of " .. inc.name)
            local want = kind == "uint" and ("uint" .. bits) or kind
            assert(f[1] == want, "net type mismatch: wrote " .. f[1] .. ", read " .. want)
            return f[2]
        end
    end
    env.net.ReadUInt, env.net.ReadBool, env.net.ReadFloat = reader("uint"), reader("bool"), reader("float")
    env.__deliver = function(msg, sender)
        inc = { name = msg.name, fields = { unpack(msg.fields) } }
        assert(receivers[msg.name], "no receiver " .. msg.name)(0, sender)
        assert(#inc.fields == 0, "unread fields left in " .. msg.name)
    end

    if not isServer then
        env.LocalPlayer = function() return localPlayer end
        env.EyePos = function() return M.eye or localPlayer:EyePos() end
        env.ScrW, env.ScrH = function() return 1920 end, function() return 1080 end
        env.sounds = {}
        env.CreateMaterial = function(name) return { name = name } end
        env.Material = function(name) return { name = name } end
        env.EyeAngles = function() return { Forward = function() return M.forward end } end
        env.STENCIL_KEEP, env.STENCIL_REPLACE, env.STENCIL_INCR, env.STENCIL_DECR = 1, 3, 7, 8
        env.STENCIL_EQUAL, env.STENCIL_NOTEQUAL, env.STENCIL_ALWAYS = 3, 6, 8
        env.MATERIAL_QUADS = 4
        env.drawCalls = 0
        env.dlights = {}
        env.DynamicLight = function(index) local d = {} env.dlights[index] = d return d end
        env.cam = {}
        env.sprites = {}

        -- Software stencil/depth buffer over M.pixels: { dir, dist, point, stencil, dark }
        local st = { enabled = false, write = 255, test = 255, ref = 0, cmp = 8, pass = 1, fail = 1, zfail = 1, colorOff = false, depthWriteOff = false, in2D = false }
        env.stencilState = st
        local function stencilPasses(px)
            if not st.enabled then return true end
            local a, b = band(st.ref, st.test), band(px.stencil, st.test)
            if st.cmp == 8 then return true end
            if st.cmp == 3 then return a == b end
            if st.cmp == 6 then return a ~= b end
            error("compare function not simulated: " .. st.cmp)
        end
        local function apply(px, op)
            if not st.enabled or op == 1 then return end
            local value
            if op == 3 then value = st.ref
            elseif op == 7 then value = (px.stencil + 1) % 256
            elseif op == 8 then value = (px.stencil - 1) % 256
            else error("stencil op not simulated: " .. op) end
            px.stencil = bor(band(px.stencil, bnot(st.write)), band(value, st.write))
        end
        local function touch(px, depthPass)
            if not stencilPasses(px) then apply(px, st.fail) return false end
            if not depthPass then apply(px, st.zfail) return false end
            apply(px, st.pass)
            return true
        end
        local function hitQuad(px, q)
            local n = (q[2] - q[1]):Cross(q[3] - q[1])
            local denom = n:Dot(px.dir)
            if math.abs(denom) < 1e-9 then return nil end
            local t = n:Dot(q[1] - M.eye) / denom
            if t <= 1 then return nil end -- behind the camera / near plane
            local hit = M.eye + px.dir * t
            local sign
            for i = 1, 4 do
                local a, b = q[i], q[i % 4 + 1]
                local s = (b - a):Cross(hit - a):Dot(n)
                if math.abs(s) > 1e-6 then
                    if sign ~= nil and (s > 0) ~= sign then return nil end
                    sign = s > 0
                end
            end
            return t
        end

        env.render = {
            SetMaterial = function(m) assert(m) end,
            SetStencilEnable = function(v) st.enabled = v end,
            ClearStencil = function() for _, px in ipairs(M.pixels or {}) do px.stencil = 0 end end,
            SetStencilWriteMask = function(v) st.write = v end,
            SetStencilTestMask = function(v) st.test = v end,
            SetStencilReferenceValue = function(v) st.ref = v end,
            SetStencilCompareFunction = function(v) st.cmp = v end,
            SetStencilPassOperation = function(v) st.pass = v end,
            SetStencilFailOperation = function(v) st.fail = v end,
            SetStencilZFailOperation = function(v) st.zfail = v end,
            OverrideColorWriteEnable = function(on, write) st.colorOff = on and not write end,
            OverrideDepthEnable = function(on, write) st.depthWriteOff = on and not write end,
            DrawQuad = function(a, b, c, d) env.mesh.Begin(4, 1) for _, v in ipairs({ a, b, c, d }) do env.mesh.Position(v) env.mesh.AdvanceVertex() end env.mesh.End() end,
            DrawSprite = function(pos, w, h, col) table.insert(env.sprites, { pos = pos, color = col }) end
        }
        local building
        env.mesh = {
            Begin = function(kind, count) assert(not building and kind == 4 and count > 0) building = { count = count, verts = {} } end,
            Position = function(v) building.pos = v end,
            Color = function() end,
            AdvanceVertex = function() table.insert(building.verts, building.pos) end,
            End = function()
                assert(#building.verts == building.count * 4, "mesh.Begin count doesn't match the vertices")
                assert(st.depthWriteOff, "stencil-marking geometry must not write depth")
                env.drawCalls = env.drawCalls + 1
                local v = building.verts
                building = nil
                for i = 1, #v, 4 do
                    local q = { v[i], v[i + 1], v[i + 2], v[i + 3] }
                    for _, px in ipairs(M.pixels or {}) do
                        local t = hitQuad(px, q)
                        if t then touch(px, t <= px.dist) end
                    end
                end
            end
        }
        env.cam.Start2D = function() st.in2D = true end
        env.cam.End2D = function() st.in2D = false end
        local drawColor
        env.surface = {
            SetDrawColor = function(r, g, b, a) drawColor = Color(r, g, b, a) end,
            DrawRect = function()
                assert(st.in2D, "DrawRect outside cam.Start2D")
                for _, px in ipairs(M.pixels or {}) do
                    if touch(px, true) and not st.colorOff and drawColor.a > 0 then
                        if drawColor.r == 0 and drawColor.g == 0 and drawColor.b == 0 then
                            -- Alpha blending black over the image.
                            px.dark = 1 - (1 - (px.dark or 0)) * (1 - drawColor.a / 255)
                        else
                            px.tint = (px.tint or 0) + drawColor.a / 255
                        end
                    end
                end
            end,
            PlaySound = function(s) table.insert(env.sounds, s) end
        }
    end

    return env
end

function M.Pump(server, clients)
    for _ = 1, 100 do
        local s = table.remove(M.queueToServer, 1)
        if s then server.__deliver(s.msg, s.sender) end
        local c = table.remove(M.queueToClients, 1)
        if c then
            for ply, realm in pairs(clients) do
                if not c.target or c.target == ply then realm.__deliver(c.msg) end
            end
        end
        if not s and not c then return end
    end
    error("message loop")
end

-- Pixels looking from `eye` at each scene point (the first surface along that ray).
-- The camera looks along `forward` (default: down, so nothing's behind it here).
function M.SetView(eye, scenePoints, forward)
    M.eye = eye
    M.forward = forward or Vector(0, 0, -1)
    M.pixels = {}
    for i, p in ipairs(scenePoints) do
        local d = p - eye
        M.pixels[i] = { dir = d:GetNormalized(), dist = d:Length(), point = p, stencil = 0 }
    end
end

return M
