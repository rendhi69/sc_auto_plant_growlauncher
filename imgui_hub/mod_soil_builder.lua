-- ============================================================================
-- BOREN HUB IMGUI - MODUL AUTO BUILD SOIL FARM (ENGINE + UI)
-- File: imgui_hub/mod_soil_builder.lua
-- Fitur:
--   - Pasang Soil Block (default ID 8772) pola 3-Zigzag di baris Y=2,4..52 (X=2..97)
--   - Opsional pasang Wooden Platform (ID 102) di sisi X=1 & X=98
--   - Auto Restock Block dari List Storage
--   - Multi-World Queue (Name:DoorID:BlockID) + Save / Import / Export / Reset
-- ============================================================================

local SB = {
    id    = "build_soil",
    label = "Build Soil",
}

SB.CFG = {
    storage_raw    = "",
    loop_enabled   = false,
    default_block  = 8772, -- Fertile Soil Block
    platform_id    = 102,
    place_platform = false,
    enable_water   = false, -- Pasang Water Bucket (822) di pojok kiri & kanan atas-bawah
    water_id       = 822,
    water_left     = true,  -- Pojok Kiri (X = 0, Y = 0..53)
    water_right    = true,  -- Pojok Kanan (X = 99, Y = 0..53)
    place_mode     = "3zigzag", -- "3zigzag" | "1by1"
    place_delay    = 180,
    step_delay     = 110,
    warp_delay     = 3500,
    use_modfly     = true,
}

SB.STATE = {
    enabled      = false,
    running      = false,
    status_text  = "Idle",
    rows         = {},   -- { { name="W", door="D", block_id=8772, status="Ready" }, ... }
    selected_idx = 0,
    selected_st  = 0,
    logs         = {},
}

local HUB_REF = nil
local activeSub = "worlds"
local addWorldBuf = ""
local addBlockBuf = "8772"
local addStorageBuf = ""
local addStorageDoorBuf = ""
local uiNotice = ""
local CACHED_PATH = nil

local function safeInputText(id, curVal, maxLen)
    local s = tostring(curVal or "")
    local ok, r1, r2 = pcall(ImGui.InputText, id, s, maxLen or 256)
    if not ok then return false, s end
    if type(r1) == "boolean" and type(r2) == "string" then
        if r1 or r2 ~= s then return true, r2 end
        return false, s
    elseif type(r1) == "string" then
        if (r2 == true) or r1 ~= s then return true, r1 end
        return false, s
    elseif type(r2) == "string" and r2 ~= s then
        return true, r2
    end
    return false, s
end

-- ============================================================================
-- 1. SAFE HELPERS & PERSISTENCE
-- ============================================================================
local function trimStr(s)
    local out = tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
    return out
end

local function isSystemWindows()
    if package and package.config and package.config:sub(1, 1) == "\\" then return true end
    if os and type(os.getenv) == "function" then
        local ok, env = pcall(os.getenv, "OS")
        if ok and env and tostring(env):lower():find("windows", 1, true) then return true end
    end
    return false
end

local function getDataPath()
    if CACHED_PATH then return CACHED_PATH end
    if isSystemWindows() then CACHED_PATH = "boren_hub_soil_data.txt"; return CACHED_PATH end
    local dirs = {
        "/storage/emulated/0/Android/media/launcher.powerkuy.growlauncher/ScriptLua/",
        "/storage/emulated/0/Android/data/launcher.powerkuy.growlauncher/files/ScriptLua/",
        "/storage/emulated/0/Download/",
    }
    for _, d in ipairs(dirs) do
        local p = d .. "boren_hub_soil_data.txt"
        local okR, fR = pcall(io.open, p, "r")
        if okR and fR then fR:close(); CACHED_PATH = p; return p end
        local okW, fW = pcall(io.open, p, "a")
        if okW and fW then fW:close(); CACHED_PATH = p; return p end
    end
    CACHED_PATH = "boren_hub_soil_data.txt"
    return CACHED_PATH
end

local function addLogUI(msg)
    local clean = tostring(msg or ""):gsub("`.", "")
    local ts = ""
    if os and type(os.date) == "function" then
        local okD, d = pcall(os.date, "%H:%M:%S")
        if okD and d then ts = "[" .. d .. "] " end
    end
    local entry = ts .. "[SOIL] " .. clean
    table.insert(SB.STATE.logs, 1, entry)
    if #SB.STATE.logs > 60 then table.remove(SB.STATE.logs) end
    if HUB_REF and HUB_REF.addLog then HUB_REF.addLog(entry) end
end

local function addLog(msg)
    addLogUI(msg)
    if LogToConsole then pcall(LogToConsole, "`e[Boren Soil] `w" .. tostring(msg or "")) end
end

local function safeSleep(ms)
    ms = tonumber(ms) or 50
    if ms < 10 then ms = 10 end
    local fn = sleep or CSleep
    if fn then pcall(fn, ms) end
end

local function parseRowLine(raw)
    local s = trimStr(raw)
    if s == "" or s:sub(1, 1) == "#" then return nil end
    s = s:gsub("|", ":")
    local parts = {}
    local st = 1
    while true do
        local idx = s:find(":", st, true)
        if not idx then
            table.insert(parts, trimStr(s:sub(st)))
            break
        else
            table.insert(parts, trimStr(s:sub(st, idx - 1)))
            st = idx + 1
        end
    end
    local wName = (parts[1] or ""):upper()
    if wName == "" then return nil end
    local door = (parts[2] or ""):upper()
    local bid = math.floor(tonumber(parts[3]) or tonumber(SB.CFG.default_block) or 8772)
    if bid <= 0 then bid = 8772 end
    return { name = wName, door = door, block_id = bid, status = "Ready" }
end

local function formatRowLine(r)
    return string.format("%s:%s:%d", tostring(r.name or ""), tostring(r.door or ""), tonumber(r.block_id) or 8772)
end

local function parseStorageLine(raw)
    local s = trimStr(raw)
    if s == "" or s:sub(1, 1) == "#" then return nil end
    s = s:gsub("|", ":")
    local w, d = s:match("^([^:]+):(.*)$")
    if w then
        w = trimStr(w):upper(); d = trimStr(d):upper()
        if w == "" then return nil end
        return { name = w, door = d }
    end
    return { name = s:upper(), door = "" }
end

local function getStorageList()
    local list = {}
    local raw = trimStr(SB.CFG.storage_raw)
    if raw == "" then return list end
    for tok in raw:gmatch("[^,\r\n;]+") do
        local p = parseStorageLine(tok)
        if p then table.insert(list, p) end
    end
    return list
end

local function setStorageList(list)
    local out = {}
    for _, st in ipairs(list or {}) do
        if st and st.name and st.name ~= "" then
            table.insert(out, st.door ~= "" and (st.name .. ":" .. st.door) or st.name)
        end
    end
    SB.CFG.storage_raw = table.concat(out, ",")
    SB.saveData()
end

function SB.saveData()
    local lines = {
        "STORAGE=" .. tostring(SB.CFG.storage_raw or ""),
        "LOOP=" .. (SB.CFG.loop_enabled and "1" or "0"),
        "BLK=" .. tostring(tonumber(SB.CFG.default_block) or 8772),
        "PPLAT=" .. (SB.CFG.place_platform and "1" or "0"),
        "ENWTR=" .. (SB.CFG.enable_water and "1" or "0"),
        "WTRID=" .. tostring(tonumber(SB.CFG.water_id) or 822),
        "WTRL=" .. (SB.CFG.water_left and "1" or "0"),
        "WTRR=" .. (SB.CFG.water_right and "1" or "0"),
        "MODE=" .. tostring(SB.CFG.place_mode or "3zigzag"),
        "PDELAY=" .. tostring(tonumber(SB.CFG.place_delay) or 180),
        "STEPD=" .. tostring(tonumber(SB.CFG.step_delay) or 110),
        "MODFLY=" .. (SB.CFG.use_modfly and "1" or "0"),
    }
    for _, r in ipairs(SB.STATE.rows) do
        table.insert(lines, "ROW=" .. formatRowLine(r) .. "|" .. tostring(r.status or "Ready"))
    end
    local ok, f = pcall(io.open, getDataPath(), "w")
    if ok and f then f:write(table.concat(lines, "\n")); f:close() end
end

function SB.loadData()
    local ok, f = pcall(io.open, getDataPath(), "r")
    if not ok or not f then return end
    local txt = f:read("*a"); f:close()
    if not txt or txt == "" then return end
    SB.STATE.rows = {}
    for line in txt:gmatch("[^\r\n]+") do
        local k, v = line:match("^([A-Z]+)=(.*)$")
        if k == "STORAGE" then SB.CFG.storage_raw = trimStr(v)
        elseif k == "LOOP" then SB.CFG.loop_enabled = (v == "1")
        elseif k == "BLK" then SB.CFG.default_block = tonumber(v) or 8772
        elseif k == "PPLAT" then SB.CFG.place_platform = (v == "1")
        elseif k == "ENWTR" then SB.CFG.enable_water = (v == "1")
        elseif k == "WTRID" then SB.CFG.water_id = tonumber(v) or 822
        elseif k == "WTRL" then SB.CFG.water_left = (v ~= "0")
        elseif k == "WTRR" then SB.CFG.water_right = (v ~= "0")
        elseif k == "MODE" and (v == "3zigzag" or v == "1by1") then SB.CFG.place_mode = v
        elseif k == "PDELAY" then SB.CFG.place_delay = tonumber(v) or 180
        elseif k == "STEPD" then SB.CFG.step_delay = tonumber(v) or 110
        elseif k == "MODFLY" then SB.CFG.use_modfly = (v ~= "0")
        elseif k == "ROW" then
            local wd, st = v:match("^(.-)|(.*)$")
            local p = parseRowLine(wd or v)
            if p then p.status = (st and st ~= "") and st or "Ready"; table.insert(SB.STATE.rows, p) end
        end
    end
end

-- ============================================================================
-- 2. GAME HELPERS & SOIL BUILD ENGINE
-- ============================================================================
local function getLocalSafe()
    if not getLocal then return nil end
    local ok, p = pcall(getLocal)
    return (ok and p) and p or nil
end

local function getPlayerPos()
    local p = getLocalSafe()
    if p then
        local px = p.posX or (p.pos and p.pos.x) or 0
        local py = p.posY or (p.pos and p.pos.y) or 0
        return math.floor((px + 10) / 32), math.floor((py + 10) / 32)
    end
    return 0, 0
end

local function cleanWorldName(s)
    local out = tostring(s or ""):gsub("%z", ""):gsub("`.", ""):gsub("^%s+", ""):gsub("%s+$", ""):upper()
    return out
end

local function getCurrentWorldSafe()
    local fns = { getCurrentWorldName, GetWorldName, getWorld, getCurrentWorld, GetWorld }
    for _, fn in ipairs(fns) do
        if type(fn) == "function" then
            local ok, res = pcall(fn)
            if ok and res ~= nil then
                if type(res) == "string" then
                    local nm = cleanWorldName(res)
                    if nm ~= "" then return nm end
                elseif type(res) == "table" or type(res) == "userdata" then
                    local okN, nm = pcall(function() return res.name or res.worldName end)
                    if okN and type(nm) == "string" then
                        local c = cleanWorldName(nm)
                        if c ~= "" then return c end
                    end
                end
            end
        end
    end
    return ""
end

local function getTileSafe(tx, ty)
    if not getTile or tx < 0 or tx > 99 or ty < 0 or ty > 53 then return nil end
    local ok, t = pcall(getTile, tx, ty)
    return (ok and t) and t or nil
end

local function readInvItemFields(it)
    local t = type(it)
    if t ~= "table" and t ~= "userdata" then return nil, nil end
    local id, amt = nil, nil
    pcall(function() id = tonumber(it.id or it.itemid or it.itemID or it.item_id) end)
    pcall(function() amt = tonumber(it.amount or it.count or it.cnt) end)
    return id, amt
end

local function getInvCount(id)
    local targetID = tonumber(id) or 0
    if targetID <= 0 then return 0 end
    if growtopia and growtopia.checkInventoryCount then
        local ok, cnt = pcall(growtopia.checkInventoryCount, targetID)
        if ok and tonumber(cnt) and tonumber(cnt) > 0 then return tonumber(cnt) end
    end
    if getInventory then
        local ok, inv = pcall(getInventory)
        if ok and (type(inv) == "table" or type(inv) == "userdata") then
            local container = inv
            pcall(function()
                if inv.items ~= nil and (type(inv.items) == "table" or type(inv.items) == "userdata") then
                    container = inv.items
                end
            end)
            local total, seen = 0, 0
            pcall(function()
                for _, it in pairs(container) do
                    local iid, amt = readInvItemFields(it)
                    if iid and iid > 0 then
                        seen = seen + 1
                        if iid == targetID and (amt or 0) > 0 then total = total + amt end
                    end
                end
            end)
            if seen == 0 then
                local okLen, n = pcall(function() return #container end)
                if not okLen or not n or n <= 0 then pcall(function() n = container:size() end) end
                local maxI = (n and tonumber(n) and tonumber(n) > 0) and tonumber(n) or 400
                local misses = 0
                for i = 0, maxI do
                    local okI, it = pcall(function() return container[i] end)
                    local iid, amt = nil, nil
                    if okI then iid, amt = readInvItemFields(it) end
                    if iid and iid > 0 then
                        misses = 0
                        if iid == targetID and (amt or 0) > 0 then total = total + amt end
                    else
                        misses = misses + 1
                        if misses >= 50 and i > 5 then break end
                    end
                end
            end
            if total > 0 then return total end
        end
    end
    if growtopia and growtopia.checkInventory then
        local ok, has = pcall(growtopia.checkInventory, targetID)
        if ok and has == true then return 1 end
    end
    return 0
end

local function forEachWorldObject(fn)
    local getFn = getObjectList or getObjects or getWorldObjects
    if not getFn then return 0 end
    local ok, objs = pcall(getFn)
    if not ok or not objs then return 0 end
    local container = objs
    pcall(function()
        if type(objs) == "table" and objs.objects then container = objs.objects end
    end)
    local seen = 0
    local function processObj(obj)
        if not obj then return end
        local oid, uid, px, py = nil, nil, nil, nil
        pcall(function() oid = tonumber(obj.itemid or obj.itemId or obj.item_id) end)
        pcall(function() uid = tonumber(obj.id or obj.oid or obj.netid) end)
        pcall(function()
            if obj.pos then px = tonumber(obj.pos.x or obj.pos[1]); py = tonumber(obj.pos.y or obj.pos[2]) end
        end)
        if not px then pcall(function() px = tonumber(obj.x or obj.posX) end) end
        if not py then pcall(function() py = tonumber(obj.y or obj.posY) end) end
        if oid and oid > 0 and uid and px and py then
            seen = seen + 1
            fn(oid, uid, px, py)
        end
    end
    pcall(function() for _, o in pairs(container) do processObj(o) end end)
    if seen == 0 then
        local okLen, n = pcall(function() return #container end)
        if not okLen or not n or n <= 0 then pcall(function() n = container:size() end) end
        local maxI = (n and tonumber(n) and tonumber(n) > 0) and tonumber(n) or 1000
        local misses = 0
        for i = 0, maxI do
            local okI, o = pcall(function() return container[i] end)
            if okI and o then
                local prev = seen; processObj(o)
                if seen > prev then misses = 0 else misses = misses + 1 end
                if misses >= 50 and i > 10 then break end
            else
                misses = misses + 1
                if misses >= 50 and i > 10 then break end
            end
        end
    end
    return seen
end

local function applyCheats()
    if not editToggle then return end
    if SB.CFG.use_modfly then pcall(editToggle, "ModFly", true) end
    pcall(editToggle, "Anti Lava", true)
    pcall(editToggle, "No Lava", true)
end

local function isTileStandable(tx, ty)
    if tx < 0 or tx > 99 or ty < 0 or ty > 53 then return false end
    local t = getTileSafe(tx, ty)
    if not t then return false end
    local fg = tonumber(t.fg) or 0
    if fg == 0 or fg == 6 or fg == 12 or fg == 102 or fg == (tonumber(SB.CFG.platform_id) or 102) then
        return true
    end
    if t.collidable == true or fg == 2 or fg == 4 or fg == 8 or fg == 10 then
        return false
    end
    return true
end

local function moveSafeTo(tx, ty)
    if not SB.STATE.running then return false end
    tx = math.max(0, math.min(99, math.floor(tx or 0)))
    ty = math.max(0, math.min(53, math.floor(ty or 0)))
    local cx, cy = getPlayerPos()
    if cx == tx and cy == ty then return true end
    local pFn = FindPath or findPath
    if not pFn then return false end
    if SB.CFG.use_modfly and editToggle then pcall(editToggle, "ModFly", true) end

    local dist = math.max(math.abs(cx - tx), math.abs(cy - ty))
    pcall(pFn, tx, ty)
    local maxW = (dist <= 3) and math.max(160, (tonumber(SB.CFG.step_delay) or 110) * 3) or math.max(3000, math.min(20000, dist * 220))
    local waited, lastX, lastY, stuck = 0, cx, cy, 0
    while waited < maxW and SB.STATE.running do
        local sl = (dist <= 3) and 25 or 65
        safeSleep(sl); waited = waited + sl
        local nx, ny = getPlayerPos()
        if nx == tx and ny == ty then
            safeSleep(SB.CFG.step_delay or 50)
            return true
        end
        if nx == lastX and ny == lastY then
            stuck = stuck + 1
            if stuck == 18 then pcall(pFn, tx, ty)
            elseif stuck >= 35 then break end
        else
            stuck = 0; lastX, lastY = nx, ny
        end
    end
    local fx, fy = getPlayerPos()
    return (math.abs(fx - tx) <= 1 and math.abs(fy - ty) <= 1)
end

local function moveAdjacentForWater(tx, ty, prefDir)
    local dir = prefDir or ((tx < 50) and 1 or -1)
    local cands = {
        { tx + dir, ty },
        { tx, ty - 1 },
        { tx, ty + 1 },
        { tx + dir, ty - 1 },
        { tx + dir, ty + 1 },
    }
    for _, c in ipairs(cands) do
        if isTileStandable(c[1], c[2]) then
            local px, py = getPlayerPos()
            if px == c[1] and py == c[2] then return true end
            if moveSafeTo(c[1], c[2]) then
                local nx, ny = getPlayerPos()
                if math.abs(nx - tx) <= 2 and math.abs(ny - ty) <= 2 and not (nx == tx and ny == ty) then
                    return true
                end
            end
        end
    end
    local px, py = getPlayerPos()
    return (math.abs(px - tx) <= 2 and math.abs(py - ty) <= 2 and not (px == tx and py == ty))
end

local function warpToWorld(wName, doorID)
    wName = cleanWorldName(wName); doorID = cleanWorldName(doorID)
    if wName == "" then return false end
    if getCurrentWorldSafe() == wName and doorID == "" then applyCheats(); return true end
    local joinStr = (doorID ~= "") and (wName .. "|" .. doorID) or wName
    for _ = 1, 3 do
        if not SB.STATE.running then return false end
        if sendPacket then pcall(sendPacket, 3, "action|join_request\nname|" .. joinStr .. "\ninvitedWorld|0\n")
        elseif growtopia and growtopia.warpTo then pcall(growtopia.warpTo, joinStr) end
        local w, lim = 0, math.max(3500, tonumber(SB.CFG.warp_delay) or 4000)
        while w < lim and SB.STATE.running do
            safeSleep(250); w = w + 250
            if getCurrentWorldSafe() == wName then safeSleep(600); applyCheats(); return true end
        end
    end
    local finalW = getCurrentWorldSafe()
    if finalW == wName then applyCheats(); return true end
    addLog(string.format("[Warp Info] Target: %s | World aktif: %s", wName, finalW ~= "" and finalW or "EXIT"))
    return false
end

local function placePacket(tx, ty, itemID)
    if not sendPacketRaw then return false end
    local p = getLocalSafe()
    local px = (p and (p.posX or (p.pos and p.pos.x))) or (tx * 32)
    local py = (p and (p.posY or (p.pos and p.pos.y))) or (ty * 32)
    return pcall(sendPacketRaw, false, {
        type = 3, value = itemID, px = tx, py = ty, x = px, y = py,
        state = (px > tx * 32) and 48 or 32,
    })
end

local function restockItem(farmRow, itemID)
    if getInvCount(itemID) > 0 then return true end
    local storages = getStorageList()
    if #storages == 0 then
        addLog("[Soil] Stok block ID " .. tostring(itemID) .. " habis & Storage kosong!")
        farmRow.status = "No Block"
        return false
    end
    farmRow.status = "Restock..."
    SB.STATE.status_text = "Restock ID " .. tostring(itemID)
    for _, st in ipairs(storages) do
        if not SB.STATE.running then return false end
        if warpToWorld(st.name, st.door) then
            safeSleep(600)
            if editToggle then
                pcall(editToggle, "Anti Collect", false)
                pcall(editToggle, "Auto Collect", true)
            end
            forEachWorldObject(function(oid, uid, rx, ry)
                if not SB.STATE.running or getInvCount(itemID) >= 180 then return end
                if oid == itemID then
                    moveSafeTo(math.floor((rx + 10) / 32), math.floor((ry + 10) / 32))
                    if sendPacketRaw then pcall(sendPacketRaw, false, { type = 11, value = uid, x = rx, y = ry }) end
                    safeSleep(160)
                end
            end)
            if getInvCount(itemID) > 0 then
                return warpToWorld(farmRow.name, farmRow.door)
            end
        end
    end
    farmRow.status = "No Block"
    return false
end

local function isEmptyTile(tx, ty)
    local t = getTileSafe(tx, ty)
    return t and (tonumber(t.fg) or 0) == 0
end

-- Deteksi bit TILEFLAG_WATER (0x0400 = 1024) kompatibel Lua 5.1/5.4 tanpa operator bitwise
local function tileHasWater(t)
    if not t then return false end
    if t.water == true or t.hasWater == true then return true end
    local fl = tonumber(t.flag or t.flags) or 0
    return (math.floor(fl / 1024) % 2) == 1
end

-- VALIDASI KETAT PUT WATER 1x PER TILE (Anti-Spam & Anti-Ambil Balik!)
-- Put #1 memunculkan air (flag bit 1024 ON & stok Water Bucket berkurang 1).
-- Put #2 pada tile basah akan MENGAMBIL air balik, sehingga fungsi ini WAJIB menunggu
-- konfirmasi server (flag/water/stok) hingga 850ms sebelum berani retry maks 1x!
local function placeWaterOnceSafe(tx, ty, waterID, prefDir)
    if not SB.STATE.running then return false end
    if tx < 0 or tx > 99 or ty < 0 or ty > 53 then return false end
    local t = getTileSafe(tx, ty)
    if not t then return false end
    -- Skip jika tile tidak kosong (ada block/bedrock/door) atau SUDAH ada air!
    if (tonumber(t.fg) or 0) ~= 0 then return true end
    if tileHasWater(t) then return true end
    if getInvCount(waterID) <= 0 then return false end

    local pDelay = math.max(140, tonumber(SB.CFG.place_delay) or 180)

    local function attemptSingleWaterPut()
        local tPre = getTileSafe(tx, ty)
        if not tPre or (tonumber(tPre.fg) or 0) ~= 0 or tileHasWater(tPre) then return true end
        local flagBefore = tonumber(tPre.flag or tPre.flags) or 0
        local invBefore  = getInvCount(waterID)
        if invBefore <= 0 then return false end

        local px, py = getPlayerPos()
        if math.abs(px - tx) > 2 or math.abs(py - ty) > 2 or (px == tx and py == ty) then
            if not moveAdjacentForWater(tx, ty, prefDir) then return false end
        end

        -- Cek ulang sesaat sebelum kirim paket agar tidak menimpa tile yang baru saja tersinkron basah
        local tPre2 = getTileSafe(tx, ty)
        if tPre2 and tileHasWater(tPre2) then return true end

        placePacket(tx, ty, waterID)
        safeSleep(math.min(pDelay, 160))

        -- Polling konfirmasi hingga 850ms: begitu flag water aktif / flag berubah / bucket berkurang 1 -> STOP!
        local waited = 0
        while waited < 850 and SB.STATE.running do
            local tNow = getTileSafe(tx, ty)
            if tNow then
                if tileHasWater(tNow) then return true end
                local flagNow = tonumber(tNow.flag or tNow.flags) or 0
                if flagNow ~= flagBefore then return true end
            end
            if invBefore > 0 and getInvCount(waterID) < invBefore then
                return true
            end
            safeSleep(50); waited = waited + 50
        end
        return false
    end

    if attemptSingleWaterPut() then
        return true
    end

    -- Sebelum 1x retry terakhir, pastikan benar-benar masih kering & reposisi ulang
    if not SB.STATE.running then return false end
    moveAdjacentForWater(tx, ty, prefDir)
    safeSleep(150)
    local tCheck = getTileSafe(tx, ty)
    if tCheck and tileHasWater(tCheck) then return true end

    return attemptSingleWaterPut()
end

-- Pasang Water Pojok Kiri (X=0) & Pojok Kanan (X=99) dari atas sampai bawah (Y=0..53)
local function putWaterCorners(row)
    if not SB.CFG.enable_water then return true end
    local waterID = tonumber(SB.CFG.water_id) or 822
    local cols = {}
    if SB.CFG.water_left then table.insert(cols, { x = 0, dir = 1, label = "Kiri" }) end
    if SB.CFG.water_right then table.insert(cols, { x = 99, dir = -1, label = "Kanan" }) end
    if #cols == 0 then return true end

    for _, col in ipairs(cols) do
        if not SB.STATE.running then return false end
        row.status = "Water " .. col.label .. "..."
        SB.STATE.status_text = row.name .. " Water " .. col.label
        addLog(string.format("[Water] Pasang air pojok %s (X=%d, Y=0..53) — 1x tervalidasi/tile", col.label, col.x))
        for y = 0, 53 do
            if not SB.STATE.running then return false end
            local t = getTileSafe(col.x, y)
            if t and (tonumber(t.fg) or 0) == 0 and (not tileHasWater(t)) then
                if getInvCount(waterID) <= 0 then
                    if not restockItem(row, waterID) then
                        row.status = "No Water"
                        SB.saveData()
                        return false
                    end
                end
                placeWaterOnceSafe(col.x, y, waterID, col.dir)
            end
        end
    end
    return true
end

local function processSoilWorld(row)
    local blockID = tonumber(row.block_id) or tonumber(SB.CFG.default_block) or 8772
    row.status = "Warping..."
    SB.STATE.status_text = "Warp: " .. row.name
    if not warpToWorld(row.name, row.door) then
        row.status = "Inaccessible"; SB.saveData(); return false
    end
    safeSleep(500)

    -- 1. Pasang Water Pojok Kiri & Kanan (atas sampai bawah Y=0..53) jika aktif
    if SB.CFG.enable_water then
        if not putWaterCorners(row) then return false end
    end

    local pDelay = tonumber(SB.CFG.place_delay) or 180
    local goingRight = true

    -- Bangun baris genap Y = 2, 4, 6, ..., 52 pada rentang X = 2..97
    for buildY = 2, 52, 2 do
        if not SB.STATE.running then return false end
        local standY = math.max(0, buildY - 1)
        local hasEmpty = false
        for x = 2, 97 do
            if isEmptyTile(x, buildY) then hasEmpty = true; break end
        end

        if hasEmpty then
            row.status = "Build Y=" .. tostring(buildY)
            SB.STATE.status_text = row.name .. " Y=" .. tostring(buildY)
            if SB.CFG.place_mode == "3zigzag" then
                local startX = goingRight and 3 or 96
                local step = goingRight and 3 or -3
                local standX = startX
                while (goingRight and standX <= 97) or ((not goingRight) and standX >= 2) do
                    if not SB.STATE.running then return false end
                    local spots = {}
                    local xs = goingRight and { standX - 1, standX, standX + 1 } or { standX + 1, standX, standX - 1 }
                    for _, bx in ipairs(xs) do
                        if bx >= 2 and bx <= 97 and isEmptyTile(bx, buildY) then table.insert(spots, bx) end
                    end
                    if #spots > 0 then
                        if getInvCount(blockID) <= 0 then
                            if not restockItem(row, blockID) then SB.saveData(); return false end
                        end
                        if moveSafeTo(standX, standY) then
                            for _, bx in ipairs(spots) do
                                if not SB.STATE.running then return false end
                                if isEmptyTile(bx, buildY) then
                                    placePacket(bx, buildY, blockID)
                                    safeSleep(pDelay)
                                end
                            end
                        end
                    end
                    standX = standX + step
                end
            else
                local x1, x2, st = goingRight and 2 or 97, goingRight and 97 or 2, goingRight and 1 or -1
                for bx = x1, x2, st do
                    if not SB.STATE.running then return false end
                    if isEmptyTile(bx, buildY) then
                        if getInvCount(blockID) <= 0 then
                            if not restockItem(row, blockID) then SB.saveData(); return false end
                        end
                        if moveSafeTo(bx, standY) then
                            placePacket(bx, buildY, blockID)
                            safeSleep(pDelay)
                        end
                    end
                end
            end
            goingRight = not goingRight
        end
    end

    -- Opsional: Pasang Platform di X=1 & X=98
    if SB.CFG.place_platform then
        local platID = tonumber(SB.CFG.platform_id) or 102
        for _, px in ipairs({ 1, 98 }) do
            for py = 2, 52, 2 do
                if not SB.STATE.running then return false end
                if isEmptyTile(px, py) then
                    if getInvCount(platID) <= 0 then
                        if not restockItem(row, platID) then SB.saveData(); return false end
                    end
                    if moveSafeTo(px, math.max(0, py - 1)) then
                        placePacket(px, py, platID)
                        safeSleep(pDelay)
                    end
                end
            end
        end
    end

    row.status = "Done"
    SB.saveData()
    addLog("[Selesai] Build Soil " .. row.name .. " tuntas!")
    return true
end

local function mainLoop()
    SB.STATE.running = true
    applyCheats()
    addLog("Auto Build Soil dimulai.")
    while SB.STATE.running do
        for _, row in ipairs(SB.STATE.rows) do
            if not SB.STATE.running then break end
            if row.status ~= "Done" and row.status ~= "Inaccessible" then
                processSoilWorld(row)
                safeSleep(400)
            end
        end
        if not SB.STATE.running then break end
        if SB.CFG.loop_enabled and #SB.STATE.rows > 0 then
            for _, r in ipairs(SB.STATE.rows) do
                if r.status ~= "Inaccessible" then r.status = "Ready" end
            end
            SB.saveData()
            safeSleep(2500)
        else
            break
        end
    end
    SB.STATE.running = false; SB.STATE.enabled = false; SB.STATE.status_text = "Idle"
    addLog("Auto Build Soil berhenti.")
end

function SB.start()
    if SB.STATE.running then return end
    if #SB.STATE.rows == 0 then
        addLogUI("Daftar world Build Soil kosong!")
        SB.STATE.status_text = "List Kosong"
        SB.STATE.enabled = false
        return
    end
    SB.STATE.enabled = true
    local function safeRunner()
        local ok, err = xpcall(mainLoop, function(e)
            return tostring(e) .. "\n" .. (debug and debug.traceback and debug.traceback() or "")
        end)
        if not ok then
            addLog("`4[Soil Crash] `w" .. tostring(err))
            SB.STATE.running = false; SB.STATE.enabled = false; SB.STATE.status_text = "Error"
        end
    end
    if runCoroutine then pcall(runCoroutine, safeRunner)
    else coroutine.resume(coroutine.create(safeRunner)) end
end

function SB.stop()
    SB.STATE.running = false; SB.STATE.enabled = false; SB.STATE.status_text = "Stopped"
end

SB._test = {
    tileHasWater = tileHasWater,
    placeWaterOnceSafe = placeWaterOnceSafe,
    putWaterCorners = putWaterCorners,
}

-- ============================================================================
-- 3. UI RENDERER (List World | List Storage | Settings | Logs)
-- ============================================================================
local function autoBtn(label)
    local ok, res = pcall(ImGui.Button, label)
    return ok and (res == true)
end

local function availX()
    if ImGui and ImGui.GetContentRegionAvail then
        local ok, av = pcall(ImGui.GetContentRegionAvail)
        if ok and av then
            if type(av) == "number" and av > 40 then return av end
            local okX, x = pcall(function() return av.x end)
            if okX and type(x) == "number" and x > 40 then return x end
        end
    end
    return 480
end

local function renderWorldsSub()
    local w = availX()
    ImGui.Text("Enable:"); ImGui.SameLine()
    if autoBtn(SB.STATE.enabled and "  ON  ##sb_en" or "  OFF  ##sb_en") then
        if SB.STATE.enabled then SB.stop() else SB.start() end
    end
    ImGui.SameLine(); ImGui.Text(" | Loop:"); ImGui.SameLine()
    if autoBtn(SB.CFG.loop_enabled and "  ON  ##sb_lp" or "  OFF  ##sb_lp") then
        SB.CFG.loop_enabled = not SB.CFG.loop_enabled; SB.saveData()
    end
    ImGui.SameLine()
    if autoBtn("Remove Inaccessible##sb") then
        local kept, rem = {}, 0
        for _, r in ipairs(SB.STATE.rows) do
            if tostring(r.status):lower():find("inaccessible", 1, true) then rem = rem + 1
            else table.insert(kept, r) end
        end
        SB.STATE.rows = kept; SB.STATE.selected_idx = 0; SB.saveData()
        uiNotice = "Dihapus " .. tostring(rem) .. " world inaccessible."
    end

    ImGui.Text(string.format("Status: %s | World: %d | Storage: %d",
        tostring(SB.STATE.status_text), #SB.STATE.rows, #getStorageList()))
    if uiNotice ~= "" then ImGui.Text("Info: " .. uiNotice) end

    ImGui.Separator()

    if ImGui.BeginTable("BorenSoilTable", 4) then
        ImGui.TableSetupColumn("Name")
        ImGui.TableSetupColumn("Door ID")
        ImGui.TableSetupColumn("Block ID")
        ImGui.TableSetupColumn("Status")
        ImGui.TableHeadersRow()

        if #SB.STATE.rows == 0 then
            ImGui.TableNextRow()
            ImGui.TableSetColumnIndex(0); ImGui.Text("(Kosong)")
            ImGui.TableSetColumnIndex(1); ImGui.Text("-")
            ImGui.TableSetColumnIndex(2); ImGui.Text("8772")
            ImGui.TableSetColumnIndex(3); ImGui.Text("Tambah di bawah")
        else
            for i, r in ipairs(SB.STATE.rows) do
                ImGui.TableNextRow()
                ImGui.TableSetColumnIndex(0)
                local sel = (SB.STATE.selected_idx == i)
                if autoBtn((sel and "> " or "") .. tostring(r.name) .. "##sbr" .. tostring(i)) then
                    SB.STATE.selected_idx = sel and 0 or i
                end
                ImGui.TableSetColumnIndex(1); ImGui.Text(r.door ~= "" and r.door or "-")
                ImGui.TableSetColumnIndex(2); ImGui.Text(tostring(tonumber(r.block_id) or 8772))
                ImGui.TableSetColumnIndex(3); ImGui.Text(tostring(r.status or "Ready"))
            end
        end
        ImGui.EndTable()
    end

    ImGui.Separator()
    ImGui.Text("Tambah World Soil:")
    if ImGui.BeginTable("BorenSoilAddW", 2) then
        ImGui.TableSetupColumn("World:DoorID")
        ImGui.TableSetupColumn("Block ID")
        ImGui.TableHeadersRow()
        ImGui.TableNextRow()
        ImGui.TableSetColumnIndex(0)
        ImGui.PushItemWidth(math.max(120, math.floor(w * 0.56)))
        local chW, nvW = safeInputText("##sb_add_w", addWorldBuf, 256)
        ImGui.PopItemWidth()
        if chW then addWorldBuf = nvW end

        ImGui.TableSetColumnIndex(1)
        ImGui.PushItemWidth(math.max(80, math.floor(w * 0.34)))
        local chB, nvB = safeInputText("##sb_add_blk", addBlockBuf, 64)
        ImGui.PopItemWidth()
        if chB then addBlockBuf = nvB:gsub("[^0-9]", "") end
        ImGui.EndTable()
    end

    if autoBtn(" + Add World ##sb") then
        local rawW = trimStr(addWorldBuf)
        local p = nil
        if rawW ~= "" then
            local norm = rawW:gsub("|", ":")
            local colons = 0
            for _ in norm:gmatch(":") do colons = colons + 1 end
            if colons >= 2 then
                p = parseRowLine(norm)
            else
                local wPart, dPart = norm:match("^([^:]+):(.*)$")
                local wName = trimStr(wPart or norm):upper()
                local dId   = trimStr(dPart or ""):upper()
                local bid   = math.floor(tonumber(addBlockBuf) or tonumber(SB.CFG.default_block) or 8772)
                if bid <= 0 then bid = 8772 end
                if wName ~= "" then p = { name = wName, door = dId, block_id = bid, status = "Ready" } end
            end
        end
        if p then
            table.insert(SB.STATE.rows, p); addWorldBuf = ""; SB.saveData()
            addLogUI("World Soil ditambah: " .. formatRowLine(p))
            uiNotice = "Ditambahkan: " .. p.name .. " (ID " .. tostring(p.block_id) .. ")"
        else uiNotice = "Isi World:DoorID dulu!" end
    end
    ImGui.SameLine()
    if autoBtn(" + World Ini ##sb") then
        local curW = getCurrentWorldSafe()
        if curW ~= "" and curW ~= "EXIT" then addWorldBuf = curW .. ":"; uiNotice = "Terisi " .. curW .. ":"
        else uiNotice = "Masuk ke world dulu!" end
    end
    ImGui.SameLine()
    if autoBtn(" Paste ##sb_pw") then
        if ImGui.GetClipboardText then
            local okC, c = pcall(ImGui.GetClipboardText)
            if okC and type(c) == "string" and c ~= "" then addWorldBuf = c:match("^[^\r\n]+") or c; uiNotice = "Paste ke World:DoorID"
            else uiNotice = "Clipboard kosong." end
        end
    end
    ImGui.SameLine()
    if autoBtn(" - Hapus ##sb") then
        local idx = SB.STATE.selected_idx
        if idx < 1 or idx > #SB.STATE.rows then idx = #SB.STATE.rows end
        if idx >= 1 and idx <= #SB.STATE.rows then
            local rem = table.remove(SB.STATE.rows, idx)
            SB.STATE.selected_idx = 0; SB.saveData()
            uiNotice = "Dihapus: " .. tostring(rem and rem.name or "")
        end
    end
    ImGui.SameLine()
    if autoBtn(" Save ##sb") then SB.saveData(); uiNotice = "Tersimpan " .. tostring(#SB.STATE.rows) .. " world!" end

    if autoBtn(" Import ##sb") then
        local clip = ""
        if ImGui.GetClipboardText then local ok, c = pcall(ImGui.GetClipboardText); if ok and type(c) == "string" then clip = c end end
        local n = 0
        for line in clip:gmatch("[^\r\n]+") do
            local p = parseRowLine(line)
            if p then table.insert(SB.STATE.rows, p); n = n + 1 end
        end
        if n > 0 then SB.saveData(); uiNotice = "Import " .. tostring(n) .. " world!" else uiNotice = "Clipboard kosong." end
    end
    ImGui.SameLine()
    if autoBtn(" Export ##sb") then
        local out = {}
        for _, r in ipairs(SB.STATE.rows) do table.insert(out, formatRowLine(r)) end
        if ImGui.SetClipboardText then pcall(ImGui.SetClipboardText, table.concat(out, "\n")); uiNotice = "Export " .. tostring(#out) .. " world!" end
    end
    ImGui.SameLine()
    if autoBtn(" Reset Status ##sb") then
        for _, r in ipairs(SB.STATE.rows) do r.status = "Ready" end
        SB.saveData(); uiNotice = "Status di-reset ke Ready."
    end
end

local function renderStorageSub()
    local w = availX()
    local storages = getStorageList()
    ImGui.Text("Storage Block Soil / Platform (" .. tostring(#storages) .. "):")
    if uiNotice ~= "" then ImGui.Text("Info: " .. uiNotice) end

    if ImGui.BeginTable("BorenSoilStorTable", 2) then
        ImGui.TableSetupColumn("Storage World")
        ImGui.TableSetupColumn("Door ID")
        ImGui.TableHeadersRow()
        if #storages == 0 then
            ImGui.TableNextRow()
            ImGui.TableSetColumnIndex(0); ImGui.Text("(Kosong)")
            ImGui.TableSetColumnIndex(1); ImGui.Text("-")
        else
            for i, st in ipairs(storages) do
                ImGui.TableNextRow()
                ImGui.TableSetColumnIndex(0)
                local sel = (SB.STATE.selected_st == i)
                if autoBtn((sel and "> " or "") .. st.name .. "##sbst" .. tostring(i)) then
                    SB.STATE.selected_st = sel and 0 or i
                end
                ImGui.TableSetColumnIndex(1); ImGui.Text(st.door ~= "" and st.door or "-")
            end
        end
        ImGui.EndTable()
    end

    ImGui.Separator()
    ImGui.Text("Tambah Storage:")
    if ImGui.BeginTable("BorenSoilAddSt", 2) then
        ImGui.TableSetupColumn("World Storage")
        ImGui.TableSetupColumn("Door ID")
        ImGui.TableHeadersRow()
        ImGui.TableNextRow()
        ImGui.TableSetColumnIndex(0)
        ImGui.PushItemWidth(math.max(110, math.floor(w * 0.46)))
        local chSt, nvSt = safeInputText("##sb_add_st", addStorageBuf, 256)
        ImGui.PopItemWidth()
        if chSt then addStorageBuf = nvSt end

        ImGui.TableSetColumnIndex(1)
        ImGui.PushItemWidth(math.max(90, math.floor(w * 0.44)))
        local chStD, nvStD = safeInputText("##sb_add_std", addStorageDoorBuf, 128)
        ImGui.PopItemWidth()
        if chStD then addStorageDoorBuf = nvStD end
        ImGui.EndTable()
    end

    if autoBtn(" + Add Storage ##sb") then
        local wStr = trimStr(addStorageBuf)
        local dStr = trimStr(addStorageDoorBuf)
        local comb = (wStr:find(":", 1, true) or wStr:find("|", 1, true) or dStr == "") and wStr or (wStr .. ":" .. dStr)
        local p = parseStorageLine(comb)
        if p then
            table.insert(storages, p); setStorageList(storages); addStorageBuf = ""; addStorageDoorBuf = ""
            uiNotice = "Storage ditambah: " .. p.name
        else uiNotice = "Isi World Storage dulu!" end
    end
    ImGui.SameLine()
    if autoBtn(" - Hapus ##sbst") then
        local idx = SB.STATE.selected_st
        if idx < 1 or idx > #storages then idx = #storages end
        if idx >= 1 and idx <= #storages then
            table.remove(storages, idx); SB.STATE.selected_st = 0; setStorageList(storages); uiNotice = "Storage dihapus."
        end
    end
end

local numBufs = {}

local function renderNumInput(id, curVal, minV, maxV, step, unit, onChange)
    local key = tostring(id)
    if numBufs[key] == nil then numBufs[key] = tostring(curVal) end
    ImGui.PushItemWidth(95)
    local ch, nv = safeInputText("##" .. key, numBufs[key], 64)
    ImGui.PopItemWidth()
    if ch then
        local digits = nv:gsub("[^0-9]", "")
        numBufs[key] = digits
        local n = tonumber(digits)
        if n then
            onChange(math.max(minV, math.min(maxV, math.floor(n))))
        end
    end
    if unit and unit ~= "" then
        ImGui.SameLine(); ImGui.Text(unit)
    end
    if step and step > 0 then
        ImGui.SameLine()
        if autoBtn(" - ##m_" .. key) then
            local nv2 = math.max(minV, (tonumber(curVal) or minV) - step)
            numBufs[key] = tostring(nv2)
            onChange(nv2)
        end
        ImGui.SameLine()
        if autoBtn(" + ##p_" .. key) then
            local nv2 = math.min(maxV, (tonumber(curVal) or minV) + step)
            numBufs[key] = tostring(nv2)
            onChange(nv2)
        end
    end
end

local function renderOptRow(label, controlFn)
    ImGui.TableNextRow()
    ImGui.TableSetColumnIndex(0)
    ImGui.Text(label)
    ImGui.TableSetColumnIndex(1)
    ImGui.Text(":")
    ImGui.SameLine()
    controlFn()
end

local function renderSettingsSub()
    ImGui.Text("Pengaturan Build Soil")
    ImGui.Separator()

    if ImGui.BeginTable("BorenSoilSetOpts", 2) then
        renderOptRow("Mode Pasang", function()
            local is3z = (SB.CFG.place_mode == "3zigzag")
            if autoBtn(is3z and " 3-Zigzag (Cepat) ##sbm" or " 1-by-1 (Presisi) ##sbm") then
                SB.CFG.place_mode = is3z and "1by1" or "3zigzag"; SB.saveData()
            end
        end)
        renderOptRow("Pasang Platform (102)", function()
            if autoBtn(SB.CFG.place_platform and "  ON  ##sbp" or "  OFF  ##sbp") then
                SB.CFG.place_platform = not SB.CFG.place_platform; SB.saveData()
            end
        end)
        renderOptRow("Pasang Water Pojok (822)", function()
            if autoBtn(SB.CFG.enable_water and "  ON  ##sbw" or "  OFF  ##sbw") then
                SB.CFG.enable_water = not SB.CFG.enable_water; SB.saveData()
            end
        end)
        renderOptRow("Water Pojok Kiri (X=0)", function()
            if autoBtn(SB.CFG.water_left and "  ON  ##sbwl" or "  OFF  ##sbwl") then
                SB.CFG.water_left = not SB.CFG.water_left; SB.saveData()
            end
        end)
        renderOptRow("Water Pojok Kanan (X=99)", function()
            if autoBtn(SB.CFG.water_right and "  ON  ##sbwr" or "  OFF  ##sbwr") then
                SB.CFG.water_right = not SB.CFG.water_right; SB.saveData()
            end
        end)
        renderOptRow("ModFly", function()
            if autoBtn(SB.CFG.use_modfly and "  ON  ##sbmf" or "  OFF  ##sbmf") then
                SB.CFG.use_modfly = not SB.CFG.use_modfly; SB.saveData()
            end
        end)
        renderOptRow("Place Delay", function()
            renderNumInput("sb_pd", SB.CFG.place_delay, 60, 500, 20, "ms", function(v)
                SB.CFG.place_delay = v; SB.saveData()
            end)
        end)
        renderOptRow("Step Delay", function()
            renderNumInput("sb_wd", SB.CFG.step_delay, 40, 400, 10, "ms", function(v)
                SB.CFG.step_delay = v; SB.saveData()
            end)
        end)
        ImGui.EndTable()
    end
end

local function renderLogsSub()
    if autoBtn(" Clear Logs ##sb") then SB.STATE.logs = {} end
    ImGui.Separator()
    if #SB.STATE.logs == 0 then ImGui.Text("Belum ada log Build Soil.")
    else
        for i = 1, math.min(20, #SB.STATE.logs) do ImGui.TextWrapped(tostring(SB.STATE.logs[i])) end
    end
end

function SB.render(hub)
    if autoBtn(activeSub == "worlds" and "[ List World ]" or "List World") then activeSub = "worlds" end
    ImGui.SameLine()
    if autoBtn(activeSub == "storage" and "[ List Storage ]" or "List Storage") then activeSub = "storage" end
    ImGui.SameLine()
    if autoBtn(activeSub == "settings" and "[ Settings ]" or "Settings") then activeSub = "settings" end
    ImGui.SameLine()
    if autoBtn(activeSub == "logs" and "[ Logs ]" or "Logs") then activeSub = "logs" end
    ImGui.Separator()

    if activeSub == "worlds" then renderWorldsSub()
    elseif activeSub == "storage" then renderStorageSub()
    elseif activeSub == "settings" then renderSettingsSub()
    else renderLogsSub() end
end

function SB.init(hub)
    HUB_REF = hub
    SB.loadData()
end

return SB
