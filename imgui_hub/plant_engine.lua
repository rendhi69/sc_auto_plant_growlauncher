-- ============================================================================
-- BOREN HUB IMGUI - MODULAR AUTO PLANT & SPLICE ENGINE
-- File: imgui_hub/plant_engine.lua
-- ============================================================================

local Engine = {}

-- ============================================================================
-- 1. STATE & KONFIGURASI DEFAULT
-- ============================================================================
Engine.CFG = {
    storage_raw   = "",       -- Format: WORLD atau WORLD:DOOR (bisa dipisah koma untuk multi storage)
    loop_enabled  = false,    -- Toggle Loop
    plant_mode    = "3zigzag",-- "3zigzag" atau "1by1"
    plant_delay   = 180,      -- ms
    splice_delay  = 180,      -- ms
    step_delay    = 110,      -- ms
    warp_delay    = 5500,     -- ms (aman terhadap delay entering / lag pindah world)
    use_modfly    = true,
    ignore_gems   = true,
    auto_clear_failed_splice = true,
    font_scale    = 1.0,
}

Engine.STATE = {
    enabled              = false,
    running              = false,
    paused               = false,
    status_text          = "Idle",
    rows                 = {},   -- { { name="W", door="D", seed_id=4585, splice_id=0, status="Ready" }, ... }
    selected_idx         = 0,
    active_row_idx       = 0,
    blocked_tiles        = {},
    foreign_locked_tiles = {},
    plant_fail_count     = {},
    inv_cache            = {},
    logs                 = {},
    warp_event           = nil,
    hooks_installed      = false,
}

local HUB_REF = nil

-- ============================================================================
-- 2. SAFE ENVIRONMENT & PERSISTENCE (ANDROID & PC COMPATIBLE)
-- ============================================================================
local function isSystemWindows()
    if package and package.config and package.config:sub(1, 1) == "\\" then
        return true
    end
    if os and type(os.getenv) == "function" then
        local ok, env = pcall(os.getenv, "OS")
        if ok and env and tostring(env):lower():find("windows", 1, true) then
            return true
        end
    end
    return false
end

local CACHED_DATA_PATH = nil

local function getDataFilePath()
    if CACHED_DATA_PATH then return CACHED_DATA_PATH end
    if isSystemWindows() then
        CACHED_DATA_PATH = "boren_hub_plant_data.txt"
        return CACHED_DATA_PATH
    end
    local candidates = {
        "/storage/emulated/0/Android/media/launcher.powerkuy.growlauncher/ScriptLua/",
        "/storage/emulated/0/Android/data/launcher.powerkuy.growlauncher/files/ScriptLua/",
        "/storage/emulated/0/Download/",
    }
    for _, dir in ipairs(candidates) do
        local testPath = dir .. "boren_hub_plant_data.txt"
        local okR, fr = pcall(io.open, testPath, "r")
        if okR and fr then
            fr:close()
            CACHED_DATA_PATH = testPath
            return CACHED_DATA_PATH
        end
        local okW, fw = pcall(io.open, testPath, "a")
        if okW and fw then
            fw:close()
            CACHED_DATA_PATH = testPath
            return CACHED_DATA_PATH
        end
    end
    CACHED_DATA_PATH = "boren_hub_plant_data.txt"
    return CACHED_DATA_PATH
end

local function trimStr(s)
    local out = tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
    return out
end

-- Log khusus UI / thread OnDrawImGui (TIDAK memanggil LogToConsole agar tidak crash di render thread!)
local function addLogUI(msg)
    local line = tostring(msg or "")
    local clean = line:gsub("`.", "")
    local ts = ""
    if os and type(os.date) == "function" then
        local okD, d = pcall(os.date, "%H:%M:%S")
        if okD and d then ts = "[" .. d .. "] " end
    end
    table.insert(Engine.STATE.logs, 1, ts .. clean)
    if #Engine.STATE.logs > 80 then
        table.remove(Engine.STATE.logs)
    end
    if HUB_REF and HUB_REF.addLog then
        HUB_REF.addLog(ts .. clean)
    end
end

local function addLog(msg)
    addLogUI(msg)
    if LogToConsole then
        pcall(LogToConsole, "`e[Boren Hub] `w" .. tostring(msg or ""))
    end
end

Engine.addLog = addLog
Engine.addLogUI = addLogUI

local function safeSleep(ms)
    ms = tonumber(ms) or 50
    if ms < 10 then ms = 10 end
    local fn = sleep or CSleep
    if fn then pcall(fn, ms) end
end

local function ensureSeedID(id)
    id = math.floor(tonumber(id) or 0)
    if id <= 0 then return 0 end
    -- Di Growtopia, ID bibit (seed) selalu bilangan ganjil (block ID + 1)
    if id % 2 == 0 then return id + 1 end
    return id
end

-- Parse format: Name:DoorID:SeedID:SpliceID (mendukung pemisah : atau |, 1 s/d 4 bagian)
function Engine.parseRowLine(raw)
    local s = trimStr(raw)
    if s == "" or s:sub(1, 1) == "#" then return nil end
    s = s:gsub("|", ":")

    local parts = {}
    local start = 1
    while true do
        local idx = s:find(":", start, true)
        if not idx then
            table.insert(parts, trimStr(s:sub(start)))
            break
        else
            table.insert(parts, trimStr(s:sub(start, idx - 1)))
            start = idx + 1
        end
    end

    local wName = (parts[1] or ""):upper()
    if wName == "" then return nil end
    local dId = (parts[2] or ""):upper()
    local s1  = ensureSeedID(parts[3] or 0)
    local s2  = ensureSeedID(parts[4] or 0)
    if s2 == s1 then s2 = 0 end

    return {
        name      = wName,
        door      = dId,
        seed_id   = s1,
        splice_id = s2,
        status    = "Ready",
    }
end

function Engine.formatRowLine(row)
    return string.format("%s:%s:%d:%d",
        tostring(row.name or ""),
        tostring(row.door or ""),
        tonumber(row.seed_id) or 0,
        tonumber(row.splice_id) or 0
    )
end

function Engine.parseStorageLine(raw)
    local t = trimStr(raw)
    if t == "" or t:sub(1, 1) == "#" then return nil end
    local w, d = t:match("^([^:|]+)[:|](.*)$")
    if w then
        w = trimStr(w):upper()
        d = trimStr(d):upper()
        if w == "" then return nil end
        return { name = w, door = d }
    end
    return { name = t:upper(), door = "" }
end

function Engine.getStorageList()
    local list = {}
    local raw = trimStr(Engine.CFG.storage_raw)
    if raw == "" then return list end
    for token in raw:gmatch("[^,\r\n;]+") do
        local parsed = Engine.parseStorageLine(token)
        if parsed then table.insert(list, parsed) end
    end
    return list
end

function Engine.setStorageList(list)
    local out = {}
    for _, st in ipairs(list or {}) do
        if st and st.name and st.name ~= "" then
            if st.door and st.door ~= "" then
                table.insert(out, tostring(st.name):upper() .. ":" .. tostring(st.door):upper())
            else
                table.insert(out, tostring(st.name):upper())
            end
        end
    end
    Engine.CFG.storage_raw = table.concat(out, ",")
    Engine.saveData()
end

function Engine.saveData()
    local path = getDataFilePath()
    local lines = {}
    table.insert(lines, "STORAGE=" .. tostring(Engine.CFG.storage_raw or ""))
    table.insert(lines, "LOOP=" .. (Engine.CFG.loop_enabled and "1" or "0"))
    table.insert(lines, "MODE=" .. tostring(Engine.CFG.plant_mode or "3zigzag"))
    table.insert(lines, "PDELAY=" .. tostring(tonumber(Engine.CFG.plant_delay) or 180))
    table.insert(lines, "SDELAY=" .. tostring(tonumber(Engine.CFG.splice_delay) or 180))
    table.insert(lines, "STEPDELAY=" .. tostring(tonumber(Engine.CFG.step_delay) or 110))
    table.insert(lines, "MODFLY=" .. (Engine.CFG.use_modfly and "1" or "0"))
    table.insert(lines, "IGNOREGEMS=" .. (Engine.CFG.ignore_gems and "1" or "0"))
    table.insert(lines, "FONTSCALE=" .. tostring(tonumber(Engine.CFG.font_scale) or 1.0))
    for _, row in ipairs(Engine.STATE.rows) do
        table.insert(lines, "ROW=" .. Engine.formatRowLine(row) .. "|" .. tostring(row.status or "Ready"))
    end
    local ok, f = pcall(io.open, path, "w")
    if ok and f then
        f:write(table.concat(lines, "\n"))
        f:close()
    end
end

function Engine.loadData()
    local path = getDataFilePath()
    local ok, f = pcall(io.open, path, "r")
    if not ok or not f then return end
    local content = f:read("*a")
    f:close()
    if not content or content == "" then return end

    Engine.STATE.rows = {}
    for line in content:gmatch("[^\r\n]+") do
        local key, val = line:match("^([A-Z]+)=(.*)$")
        if key == "STORAGE" then Engine.CFG.storage_raw = trimStr(val)
        elseif key == "LOOP" then Engine.CFG.loop_enabled = (val == "1")
        elseif key == "MODE" and (val == "3zigzag" or val == "1by1") then Engine.CFG.plant_mode = val
        elseif key == "PDELAY" then Engine.CFG.plant_delay = tonumber(val) or 180
        elseif key == "SDELAY" then Engine.CFG.splice_delay = tonumber(val) or 180
        elseif key == "STEPDELAY" then Engine.CFG.step_delay = tonumber(val) or 110
        elseif key == "MODFLY" then Engine.CFG.use_modfly = (val ~= "0")
        elseif key == "IGNOREGEMS" then Engine.CFG.ignore_gems = (val ~= "0")
        elseif key == "FONTSCALE" then Engine.CFG.font_scale = tonumber(val) or 1.0
        elseif key == "ROW" then
            local rowData, rowStatus = val:match("^(.-)|(.*)$")
            local parsed = Engine.parseRowLine(rowData or val)
            if parsed then
                parsed.status = (rowStatus and rowStatus ~= "") and rowStatus or "Ready"
                table.insert(Engine.STATE.rows, parsed)
            end
        end
    end
end

-- ============================================================================
-- 3. HELPER GAME STATE, INVENTORY, TILE & LOCK SCANNER
-- ============================================================================
local function getLocalSafe()
    if not getLocal then return nil end
    local ok, me = pcall(getLocal)
    if ok and me then return me end
    return nil
end

local function getPlayerTilePos()
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
    if not getTile then return nil end
    if tx < 0 or tx > 99 or ty < 0 or ty > 59 then return nil end
    local ok, t = pcall(getTile, tx, ty)
    if ok and t then return t end
    return nil
end

local function hasAnyLoadedTiles()
    -- Cek Bedrock (Y=54..58 selalu ada di semua world GT: Dirt Farm, Soil Farm, Clear World, dll.)
    for _, cy in ipairs({ 55, 56, 54, 57, 24, 25, 52, 53, 23 }) do
        for _, cx in ipairs({ 50, 25, 75, 10, 90, 0 }) do
            local t = getTileSafe(cx, cy)
            if t and ((tonumber(t.fg) or 0) > 0 or (tonumber(t.bg) or 0) > 0) then
                return true
            end
        end
    end
    if getTiles then
        local ok, tiles = pcall(getTiles)
        if ok and tiles then
            local any = false
            pcall(function() for _ in pairs(tiles) do any = true; break end end)
            if any then return true end
        end
    end
    return false
end

local function isWorldProperlyLoaded(expectedWorld)
    local curW = getCurrentWorldSafe()
    if curW == "" or curW == "EXIT" then return false end
    local exp = cleanWorldName(expectedWorld)
    if exp ~= "" and curW ~= exp then return false end
    if hasAnyLoadedTiles() then return true end
    -- Fallback bila getTile berbeda tapi nama world & player lokal sudah aktif di world target
    if getLocalSafe() ~= nil then return true end
    return false
end

local function readInvItemFields(it)
    local tp = type(it)
    if tp ~= "table" and tp ~= "userdata" then return nil, nil end
    local id, amt = nil, nil
    pcall(function() id = tonumber(it.id or it.itemid or it.itemID or it.item_id) end)
    pcall(function() amt = tonumber(it.amount or it.count or it.cnt) end)
    return id, amt
end

local function forEachInvItem(fn)
    if not getInventory then return 0 end
    local ok, inv = pcall(getInventory)
    if not ok or inv == nil then return 0 end
    local tp = type(inv)
    if tp ~= "table" and tp ~= "userdata" then return 0 end
    local container = inv
    pcall(function()
        if inv.items ~= nil and (type(inv.items) == "table" or type(inv.items) == "userdata") then
            container = inv.items
        end
    end)
    local seen = 0
    pcall(function()
        for _, it in pairs(container) do
            local id, amt = readInvItemFields(it)
            if id and id > 0 then seen = seen + 1; fn(id, amt or 0) end
        end
    end)
    if seen == 0 then
        local okLen, n = pcall(function() return #container end)
        if not okLen or not n or n <= 0 then pcall(function() n = container:size() end) end
        local maxI = (n and tonumber(n) and tonumber(n) > 0) and tonumber(n) or 400
        local misses = 0
        for i = 0, maxI do
            local okI, it = pcall(function() return container[i] end)
            local id, amt = nil, nil
            if okI then id, amt = readInvItemFields(it) end
            if id and id > 0 then
                misses = 0; seen = seen + 1; fn(id, amt or 0)
            else
                misses = misses + 1
                if misses >= 50 and i > 5 then break end
            end
        end
    end
    return seen
end

local function syncInventoryCache()
    local map = {}
    local seen = forEachInvItem(function(id, amt)
        map[id] = (map[id] or 0) + (amt or 0)
    end)
    if seen > 0 then
        Engine.STATE.inv_cache = map
    end
end

local function getInvCount(itemID)
    itemID = tonumber(itemID) or 0
    if itemID <= 0 then return 0 end
    if growtopia and growtopia.checkInventoryCount then
        local ok, cnt = pcall(growtopia.checkInventoryCount, itemID)
        if ok and tonumber(cnt) and tonumber(cnt) > 0 then return tonumber(cnt) end
    end
    local total = 0
    forEachInvItem(function(id, amt)
        if id == itemID and amt > 0 then total = total + amt end
    end)
    if total > 0 then return total end
    if growtopia and growtopia.checkInventory then
        local ok, has = pcall(growtopia.checkInventory, itemID)
        if ok and has == true then return 1 end
    end
    if findItem then
        local ok, c = pcall(findItem, itemID)
        if ok and tonumber(c) then return tonumber(c) end
    end
    return Engine.STATE.inv_cache[itemID] or 0
end

-- Pastikan hasEnoughSeedInBackpack didefinisikan SEBELUM plantTileSection!
local function hasEnoughSeedInBackpack(s1, s2)
    s1 = tonumber(s1) or 0
    s2 = tonumber(s2) or 0
    local isSplice = (s1 > 0 and s2 > 0 and s1 ~= s2)
    if s1 <= 0 then return false end

    local bp1 = getInvCount(s1)
    local bp2 = isSplice and getInvCount(s2) or 999
    if bp1 > 0 and (not isSplice or bp2 > 0) then
        return true
    end

    syncInventoryCache()
    safeSleep(50)
    bp1 = getInvCount(s1)
    bp2 = isSplice and getInvCount(s2) or 999
    return (bp1 > 0 and (not isSplice or bp2 > 0))
end

local SUPPORT_ITEMS = {
    [2] = true, [4] = true, [8] = true, [10] = true, [14] = true, [20] = true, [22] = true,
    [102] = true, [104] = true, [448] = true, [1004] = true, [1684] = true, [3792] = true,
    [4584] = true, [5666] = true, [8640] = true, [9350] = true,
}

local function isSupportTile(t)
    if not t then return false end
    local fg = tonumber(t.fg) or 0
    if fg <= 0 then return false end
    if SUPPORT_ITEMS[fg] then return true end
    if t.collidable == true then return true end
    if fg == 6 or fg == 242 or fg == 202 or fg == 204 or fg == 206 or fg == 226 then return false end
    if fg % 2 == 0 and fg > 0 then return true end
    return false
end

local function isPermanentObstacle(t)
    if not t then return false end
    local fg = tonumber(t.fg) or 0
    return (fg == 6 or fg == 242 or fg == 202 or fg == 204 or fg == 206 or fg == 226 or fg == 828 or fg == 12 or fg == 18)
end

-- CATATAN PENTING GROWTOPIA:
-- JANGAN mengecek t.extra.fruitcount > 0 di sini! Di Growtopia, seed yang BARU
-- ditanam (belum di-splice!) langsung punya fruitcount 1..4 sejak detik ke-0.
-- Hanya cek readyharvest / canHarvest untuk memastikan pohon benar-benar matang!
local function isTileTree(t)
    if not t then return false end
    local fg = tonumber(t.fg) or 0
    if fg <= 0 then return false end
    if t.readyharvest == true then return true end
    if t.canHarvest and type(t.canHarvest) == "function" then
        local okH, resH = pcall(t.canHarvest, t)
        if okH and resH == true then return true end
    end
    return false
end

local function isLockOwnedByLocal(tLock)
    if not tLock then return false end
    local me = getLocalSafe()
    local myUserId = tonumber(me and (me.userID or me.userId)) or 0
    local okExtra, extra = pcall(function() return tLock.extra end)
    if okExtra and extra then
        local ownerId = 0
        pcall(function() ownerId = tonumber(extra.owner or extra.owner_signed) or 0 end)
        if myUserId > 0 and ownerId > 0 and ownerId == myUserId then return true end
        local isAdmin = false
        pcall(function()
            if extra.admin then
                for _, admId in ipairs(extra.admin) do
                    if myUserId > 0 and tonumber(admId) == myUserId then
                        isAdmin = true
                        break
                    end
                end
            end
        end)
        if isAdmin then return true end
    end
    return false
end

local function scanForeignLocksInWorld()
    Engine.STATE.foreign_locked_tiles = {}
    local foreignCount, lockedTiles = 0, 0
    for y = 0, 53 do
        for x = 0, 99 do
            local t = getTileSafe(x, y)
            local fg = tonumber(t and t.fg) or 0
            -- Hanya Small/Big/Huge/Builder Lock (JANGAN lock seluruh world karena WL)
            if fg == 202 or fg == 204 or fg == 206 or fg == 4994 then
                if not isLockOwnedByLocal(t) then
                    foreignCount = foreignCount + 1
                    local rad = (fg == 202 and 5) or (fg == 204 and 7) or 15
                    for cy = math.max(0, y - rad), math.min(53, y + rad) do
                        for cx = math.max(0, x - rad), math.min(99, x + rad) do
                            if math.abs(cx - x) + math.abs(cy - y) <= (rad + 1) then
                                local k = cx .. "_" .. cy
                                if not Engine.STATE.foreign_locked_tiles[k] then
                                    Engine.STATE.foreign_locked_tiles[k] = true
                                    lockedTiles = lockedTiles + 1
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    if foreignCount > 0 then
        addLog(string.format("[Lock Orang Lain] %d lock terdeteksi (%d petak dilewati).", foreignCount, lockedTiles))
    end
end

local function getTilePlantStatus(tx, ty, s1, s2)
    if tx < 0 or tx > 99 or ty < 0 or ty > 53 then return "INVALID" end
    local k = tx .. "_" .. ty
    if Engine.STATE.blocked_tiles[k] or Engine.STATE.foreign_locked_tiles[k] then return "INVALID" end
    if not isSupportTile(getTileSafe(tx, ty + 1)) then return "INVALID" end
    local tAt = getTileSafe(tx, ty)
    if isPermanentObstacle(tAt) then return "INVALID" end

    local fgAt = tonumber(tAt and tAt.fg) or 0
    local isSplice = (s1 > 0 and s2 > 0 and s1 ~= s2)
    if not isSplice then
        return (fgAt == 0) and "EMPTY" or "DONE"
    end
    if fgAt == 0 then return "EMPTY" end
    if fgAt == s1 then return isTileTree(tAt) and "DONE" or "NEEDS_SPLICE_2" end
    if fgAt == s2 then return isTileTree(tAt) and "DONE" or "NEEDS_SPLICE_1" end
    return "DONE"
end

local function isTilePlantable(tx, ty, s1, s2)
    local st = getTilePlantStatus(tx, ty, s1, s2)
    return (st == "EMPTY" or st == "NEEDS_SPLICE_2" or st == "NEEDS_SPLICE_1")
end

local function isTilePlanted(tx, ty, s1, s2)
    if tx < 0 or tx > 99 or ty < 0 or ty > 53 then return false end
    if not isSupportTile(getTileSafe(tx, ty + 1)) then return false end
    local tAt = getTileSafe(tx, ty)
    if not tAt or isPermanentObstacle(tAt) then return false end
    local fgAt = tonumber(tAt.fg) or 0
    if fgAt <= 0 then return false end
    if s1 > 0 and s2 > 0 and s1 ~= s2 then
        if getTilePlantStatus(tx, ty, s1, s2) == "DONE" then return true end
        if fgAt == s1 or fgAt == s2 or isTileTree(tAt) or (fgAt % 2 == 1) then return true end
        return false
    end
    return (fgAt == s1) or isTileTree(tAt) or (fgAt % 2 == 1)
end

local function countPlantableSpots(s1, s2)
    if not isWorldProperlyLoaded() then return -1 end
    local cnt = 0
    for y = 0, 53 do
        for x = 0, 99 do
            if isTilePlantable(x, y, s1, s2) then cnt = cnt + 1 end
        end
    end
    return cnt
end

-- ============================================================================
-- 4. NAVIGASI, WARP, RESTOCK & SMART RESUME
-- ============================================================================
local function applyCheatToggles()
    if not editToggle then return end
    if Engine.CFG.use_modfly then pcall(editToggle, "ModFly", true) end
    pcall(editToggle, "Anti Lava", true)
    pcall(editToggle, "No Lava", true)
end

local function moveSafeTo(tx, ty)
    if not Engine.STATE.running then return false end
    tx = math.max(0, math.min(99, math.floor(tx or 0)))
    ty = math.max(0, math.min(53, math.floor(ty or 0)))

    local curPx, curPy = getPlayerTilePos()
    if curPx and curPy and math.abs(curPx - tx) <= 1 and math.abs(curPy - ty) <= 1 then
        return true
    end

    local sx, sy = tx, ty
    local t = getTileSafe(tx, ty)
    if t and t.collidable then
        local tUp = getTileSafe(tx, ty - 1)
        if tUp and not tUp.collidable then sx, sy = tx, ty - 1 end
    end

    local pFn = FindPath or findPath
    if not pFn then return false end
    if Engine.CFG.use_modfly and editToggle then pcall(editToggle, "ModFly", true) end

    local startPx, startPy = getPlayerTilePos()
    local totalDist = math.max(math.abs((startPx or 0) - sx), math.abs((startPy or 0) - sy))

    if totalDist <= 3 then
        pcall(pFn, sx, sy)
        local maxWait = math.max(160, (tonumber(Engine.CFG.step_delay) or 110) * 3)
        local waited = 0
        while waited < maxWait and Engine.STATE.running do
            local px, py = getPlayerTilePos()
            if px and py and math.abs(px - sx) <= 1 and math.abs(py - sy) <= 1 then
                safeSleep(Engine.CFG.step_delay or 40)
                return true
            end
            safeSleep(25)
            waited = waited + 25
        end
        local fx, fy = getPlayerTilePos()
        return (fx and fy and math.abs(fx - sx) <= 1 and math.abs(fy - sy) <= 1)
    end

    pcall(pFn, sx, sy)
    local maxWaitFar = math.max(3000, math.min(25000, totalDist * 250))
    local waitedFar = 0
    local lastPx, lastPy = startPx, startPy
    local stuckTicks = 0

    while waitedFar < maxWaitFar and Engine.STATE.running do
        safeSleep(70)
        waitedFar = waitedFar + 70
        local nx, ny = getPlayerTilePos()
        if nx and ny then
            if math.abs(nx - sx) <= 1 and math.abs(ny - sy) <= 1 then
                safeSleep(Engine.CFG.step_delay or 60)
                return true
            end
            if nx == lastPx and ny == lastPy then
                stuckTicks = stuckTicks + 1
                if stuckTicks == 20 then
                    pcall(pFn, sx, sy)
                elseif stuckTicks >= 40 then
                    break
                end
            else
                stuckTicks = 0
                lastPx, lastPy = nx, ny
            end
        end
    end

    local fx, fy = getPlayerTilePos()
    return (fx and fy and math.abs(fx - sx) <= 1 and math.abs(fy - sy) <= 1)
end

local lastWarpSentMs = 0

local function nowMsSafe()
    if getTime then
        local ok, ms = pcall(getTime)
        if ok and tonumber(ms) then return math.floor(tonumber(ms)) end
    end
    if os and os.clock then
        local ok, c = pcall(os.clock)
        if ok and tonumber(c) then return math.floor(tonumber(c) * 1000) end
    end
    return 0
end

local function stripGTColors(s)
    return tostring(s or ""):gsub("`.", ""):gsub("%z", ""):gsub("^%s+", ""):gsub("%s+$", "")
end

-- Dengarkan pesan asli server Growtopia (OnConsoleMessage / OnTextOverlay / OnFailedToEnterWorld)
-- agar world yang sekadar delay "Entering..." / cooldown TIDAK PERNAH salah dikira Inaccessible!
function Engine.handleVariant(var)
    local ev = Engine.STATE.warp_event
    if not ev or type(var) ~= "table" and type(var) ~= "userdata" then return false end

    local v1, v2 = nil, nil
    pcall(function() v1 = var.v1 or var[0] end)
    pcall(function() v2 = var.v2 or var[1] end)
    local fn = tostring(v1 or "")

    if fn == "OnFailedToEnterWorld" then
        ev.failed = true
        ev.updated_ms = nowMsSafe()
        return false
    end

    if fn == "OnConsoleMessage" or fn == "OnTextOverlay" or fn == "OnAddNotification" then
        local rawMsg = stripGTColors(v2)
        if rawMsg == "" then return false end
        local low = rawMsg:lower()
        ev.last_msg = rawMsg
        ev.updated_ms = nowMsSafe()

        -- 1. Pesan PASTI Inaccessible (nuked / banned / tidak bisa dimasuki secara permanen)
        if low:find("that world is inaccessible", 1, true)
            or low:find("world is inaccessible", 1, true)
            or low:find("banned from", 1, true)
            or low:find("has been nuked", 1, true)
            or low:find("world is nuked", 1, true)
            or low:find("not allowed to enter", 1, true)
            or low:find("cannot enter this world", 1, true)
            or low:find("invalid world", 1, true)
            or (low:find("minimum level", 1, true) and low:find("world", 1, true))
            or (low:find("level ", 1, true) and low:find("required to enter", 1, true))
        then
            ev.inaccessible = true
            ev.inaccessible_reason = rawMsg
            ev.entering = false
            return false
        end

        -- 2. Pesan Cooldown / Rate Limit / Penuh sementara -> BUKAN Inaccessible!
        if low:find("please wait", 1, true)
            or low:find("wait a few", 1, true)
            or low:find("wait before", 1, true)
            or low:find("slow down", 1, true)
            or low:find("too fast", 1, true)
            or low:find("try again", 1, true)
            or low:find("world is full", 1, true)
            or low:find("too many", 1, true)
            or low:find("connecting", 1, true)
            or low:find("logging on", 1, true)
        then
            ev.cooldown = true
            ev.inaccessible = false
            return false
        end

        -- 3. Pesan sedang Entering -> tunggu sabar, jangan spam join_request lagi!
        if low:find("entering ", 1, true) or low:find("entering...", 1, true) then
            ev.entering = true
            ev.cooldown = false
            ev.inaccessible = false
            return false
        end
    end
    return false
end

local function waitWorldTilesReady(maxWaitMs)
    local tw = 0
    local lim = maxWaitMs or 6000
    while tw < lim and Engine.STATE.running and (not hasAnyLoadedTiles()) do
        safeSleep(150)
        tw = tw + 150
    end
    safeSleep(450)
end

-- Mengembalikan (ok: boolean, reason: "ok"|"inaccessible"|"timeout"|"stopped")
-- HANYA mengembalikan "inaccessible" jika server benar-benar menolak permanen (nuked/banned/inaccessible).
local function warpToWorld(worldName, doorID)
    worldName = cleanWorldName(worldName)
    doorID = cleanWorldName(doorID)
    if worldName == "" then return false, "inaccessible" end

    -- Jika sudah berada di world target tanpa Door ID, langsung lanjut!
    if getCurrentWorldSafe() == worldName and doorID == "" then
        waitWorldTilesReady(4500)
        applyCheatToggles()
        return true, "ok"
    end

    -- Jeda anti-spam minimal 1.2 detik sejak join_request sebelumnya agar tidak kena cooldown GT
    local tNow = nowMsSafe()
    if lastWarpSentMs > 0 and tNow > lastWarpSentMs then
        local since = tNow - lastWarpSentMs
        if since < 1200 then
            safeSleep(1200 - since)
        end
    end

    local prevWorld = getCurrentWorldSafe()
    local ev = {
        target = worldName,
        inaccessible = false,
        inaccessible_reason = "",
        cooldown = false,
        entering = false,
        failed = false,
        last_msg = "",
        updated_ms = nowMsSafe(),
    }
    Engine.STATE.warp_event = ev

    local joinStr = (doorID ~= "") and (worldName .. "|" .. doorID) or worldName
    local baseWaitMs = math.max(6000, tonumber(Engine.CFG.warp_delay) or 6000)
    local extWaitMs  = math.max(baseWaitMs + 6000, 12000)

    for attempt = 1, 4 do
        if not Engine.STATE.running then
            Engine.STATE.warp_event = nil
            return false, "stopped"
        end

        ev.failed = false
        ev.cooldown = false
        ev.entering = false
        lastWarpSentMs = nowMsSafe()

        if sendPacket then
            pcall(sendPacket, 3, "action|join_request\nname|" .. joinStr .. "\ninvitedWorld|0\n")
        elseif growtopia and growtopia.warpTo then
            pcall(growtopia.warpTo, joinStr)
        end

        local elapsed = 0
        local sawTransition = false
        while Engine.STATE.running do
            safeSleep(250)
            elapsed = elapsed + 250

            local curW = getCurrentWorldSafe()
            if curW == worldName then
                -- World sudah masuk! Tunggu tile selesai termuat hingga 6 detik agar tidak dianggap kosong/error
                Engine.STATE.status_text = "Loading: " .. worldName
                waitWorldTilesReady(6000)
                applyCheatToggles()
                Engine.STATE.warp_event = nil
                return true, "ok"
            end

            -- Server secara eksplisit menyatakan world Inaccessible / Banned / Nuked -> langsung berhenti
            if ev.inaccessible then
                addLog(string.format("[Inaccessible] %s ditolak server: %s", worldName, ev.inaccessible_reason))
                Engine.STATE.warp_event = nil
                return false, "inaccessible"
            end

            -- Deteksi sedang transisi/entering (sudah keluar dari world lama ke EXIT / sedang "Entering...")
            if ev.entering or (prevWorld ~= "" and prevWorld ~= "EXIT" and (curW == "" or curW == "EXIT")) then
                sawTransition = true
                Engine.STATE.status_text = "Entering: " .. worldName
            end

            -- Jika kena rate-limit/cooldown, tunggu jeda dulu sebelum attempt berikutnya
            if ev.cooldown and elapsed >= 1500 then
                addLog(string.format("[Warp Delay] Cooldown server saat masuk %s, menunggu 3.5 detik...", worldName))
                safeSleep(3500)
                break
            end

            -- Jika OnFailedToEnterWorld (tanpa pesan inaccessible), tunggu sebentar lalu coba ulang
            if ev.failed and (not ev.inaccessible) and elapsed >= 2000 then
                safeSleep(2200)
                break
            end

            -- Perpanjang waktu tunggu otomatis hingga 12 detik bila sedang Entering/Transisi (JANGAN spam join_request!)
            local curLimit = sawTransition and extWaitMs or baseWaitMs
            if elapsed >= curLimit then
                break
            end
        end

        if attempt < 4 and Engine.STATE.running then
            addLog(string.format("[Warp] Percobaan %d/4 masuk %s masih tertunda, mencoba ulang...", attempt, worldName))
            safeSleep(1800)
        end
    end

    local finalW = getCurrentWorldSafe()
    if finalW == worldName then
        waitWorldTilesReady(4500)
        applyCheatToggles()
        Engine.STATE.warp_event = nil
        return true, "ok"
    end
    if ev.inaccessible then
        Engine.STATE.warp_event = nil
        return false, "inaccessible"
    end

    addLog(string.format("[Warp Delay] Belum masuk ke %s (aktif: %s) — BUKAN Inaccessible, akan dicoba ulang.",
        worldName, finalW ~= "" and finalW or "EXIT"))
    Engine.STATE.warp_event = nil
    return false, "timeout"
end

local function parseStorageEntries()
    local list = {}
    local raw = trimStr(Engine.CFG.storage_raw)
    if raw == "" then return list end
    for token in raw:gmatch("[^,\r\n;]+") do
        local t = trimStr(token)
        if t ~= "" then
            local w, d = t:match("^([^:|]+)[:|](.*)$")
            if w then
                table.insert(list, { name = trimStr(w):upper(), door = trimStr(d):upper() })
            else
                table.insert(list, { name = t:upper(), door = "" })
            end
        end
    end
    return list
end

local function forEachWorldObject(fn)
    local getObjsFn = getObjectList or getObjects or getWorldObjects
    if not getObjsFn then return 0 end
    local ok, objs = pcall(getObjsFn)
    if not ok or not objs then return 0 end
    local container = objs
    pcall(function() if type(objs) == "table" and objs.objects then container = objs.objects end end)

    local function dispatch(obj)
        if not obj then return end
        local oid, uid, amt, rx, ry = nil, nil, 1, nil, nil
        pcall(function() oid = tonumber(obj.itemid or obj.itemId or obj.item_id) end)
        pcall(function() uid = tonumber(obj.id or obj.oid or obj.netid) end)
        pcall(function() amt = tonumber(obj.amount or obj.count) or 1 end)
        pcall(function()
            if obj.pos then rx = tonumber(obj.pos.x or obj.pos[1]); ry = tonumber(obj.pos.y or obj.pos[2]) end
        end)
        if not rx then pcall(function() rx = tonumber(obj.posX or obj.x) end) end
        if not ry then pcall(function() ry = tonumber(obj.posY or obj.y) end) end
        if oid and oid > 0 and uid and rx and ry then
            fn(oid, uid, amt, rx, ry)
        end
    end

    local seen = 0
    pcall(function()
        for _, obj in pairs(container) do seen = seen + 1; dispatch(obj) end
    end)
    if seen == 0 then
        local okLen, n = pcall(function() return #container end)
        if not okLen or not n or n <= 0 then pcall(function() n = container:size() end) end
        local maxI = (n and tonumber(n) and tonumber(n) > 0) and tonumber(n) or 1000
        local misses = 0
        for i = 0, maxI do
            local okI, obj = pcall(function() return container[i] end)
            if okI and obj then
                misses = 0; seen = seen + 1; dispatch(obj)
            else
                misses = misses + 1
                if misses >= 60 and i > 5 then break end
            end
        end
    end
    return seen
end

local function countFloatingItem(targetID)
    targetID = tonumber(targetID) or 0
    if targetID <= 0 then return 0 end
    local total = 0
    forEachWorldObject(function(oid, _, amt)
        if oid == targetID then total = total + (tonumber(amt) or 1) end
    end)
    return total
end

local function collectFloatingSeeds(targetID, targetAmount)
    targetID = tonumber(targetID) or 0
    if targetID <= 0 then return 0 end
    targetAmount = tonumber(targetAmount) or 200

    local collected = 0
    for pass = 1, 2 do
        if not Engine.STATE.running or getInvCount(targetID) >= targetAmount then break end
        local targets = {}
        forEachWorldObject(function(oid, uid, amt, rx, ry)
            if oid == targetID then
                table.insert(targets, { uid = uid, amt = amt, rx = rx, ry = ry })
            end
        end)
        if #targets == 0 then break end

        for _, t in ipairs(targets) do
            if not Engine.STATE.running or getInvCount(targetID) >= targetAmount then break end
            local beforeCnt = getInvCount(targetID)
            local ox = math.floor((t.rx + 10) / 32)
            local oy = math.floor((t.ry + 10) / 32)
            moveSafeTo(ox, oy)
            safeSleep(120)
            if sendPacketRaw then
                pcall(sendPacketRaw, false, { type = 11, value = t.uid, x = t.rx, y = t.ry })
            end
            safeSleep(220)
            syncInventoryCache()
            if getInvCount(targetID) <= beforeCnt and sendPacketRaw and Engine.STATE.running then
                pcall(sendPacketRaw, false, { type = 11, value = t.uid, x = t.rx, y = t.ry })
                safeSleep(260)
                syncInventoryCache()
            end
            collected = collected + (tonumber(t.amt) or 1)
        end
    end
    return collected
end

-- Tunggu sinkronisasi paket inventori dari server (maks 2.4 detik) setelah ambil seed di storage
local function waitForInventorySyncAfterCollect(s1, s2, floorDropped1, floorDropped2)
    local isSplice = (s1 > 0 and s2 > 0 and s1 ~= s2)
    for _ = 1, 12 do
        if not Engine.STATE.running then return false end
        syncInventoryCache()
        local bp1 = getInvCount(s1)
        local bp2 = isSplice and getInvCount(s2) or 999
        if bp1 > 0 and (not isSplice or bp2 > 0) then
            safeSleep(250)
            syncInventoryCache()
            return true
        end
        safeSleep(200)
    end

    -- Fallback lag berat: jika seed fisik di lantai storage BENAR-BENAR hilang terambil tapi getInventory() lambat sync
    if (floorDropped1 or 0) > 0 and getInvCount(s1) <= 0 then
        safeSleep(800)
        syncInventoryCache()
        if getInvCount(s1) <= 0 then
            Engine.STATE.inv_cache[s1] = math.min(200, floorDropped1)
            addLog(string.format("[Storage] Sinkronisasi tas tertunda, terdeteksi +%d seed (ID %d) terambil dari lantai.",
                Engine.STATE.inv_cache[s1], s1))
        end
    end
    if isSplice and (floorDropped2 or 0) > 0 and getInvCount(s2) <= 0 then
        safeSleep(600)
        syncInventoryCache()
        if getInvCount(s2) <= 0 then
            Engine.STATE.inv_cache[s2] = math.min(200, floorDropped2)
        end
    end

    return hasEnoughSeedInBackpack(s1, s2)
end

local function restockFromStorage(row, s1, s2)
    -- Cek tas dulu! Jika masih ada seed sisa di tas (misal 200 seed), JANGAN berhenti — tanam dulu!
    if hasEnoughSeedInBackpack(s1, s2) then
        return true
    end

    local storages = parseStorageEntries()
    if #storages == 0 then
        addLog("[Peringatan] Seed Storage kosong! Isi kolom Seed Storage terlebih dahulu.")
        row.status = "No Seed"
        return false
    end

    local isSplice = (s1 > 0 and s2 > 0 and s1 ~= s2)
    row.status = "Restocking..."
    Engine.STATE.status_text = "Restock Seed..."

    for _, st in ipairs(storages) do
        if not Engine.STATE.running then return false end
        addLog(string.format("[Storage] Mengambil seed di %s...", st.name))
        if warpToWorld(st.name, st.door) then
            safeSleep(700)
            if editToggle then
                pcall(editToggle, "Auto Collect", true)
                pcall(editToggle, "Anti Collect", false)
            end

            local floorBefore1 = countFloatingItem(s1)
            local floorBefore2 = isSplice and countFloatingItem(s2) or 0

            collectFloatingSeeds(s1, 200)
            if isSplice then collectFloatingSeeds(s2, 200) end

            local floorAfter1 = countFloatingItem(s1)
            local floorAfter2 = isSplice and countFloatingItem(s2) or 0
            local dropped1 = math.max(0, floorBefore1 - floorAfter1)
            local dropped2 = math.max(0, floorBefore2 - floorAfter2)

            if waitForInventorySyncAfterCollect(s1, s2, dropped1, dropped2) then
                local bp1 = getInvCount(s1)
                local bp2 = isSplice and getInvCount(s2) or 0
                addLog(string.format("[Storage] Seed di tas: %d%s. Kembali tanam ke %s...",
                    bp1, isSplice and (" & " .. tostring(bp2)) or "", row.name))
                local okBack, backReason = warpToWorld(row.name, row.door)
                if (not okBack) and backReason == "timeout" and Engine.STATE.running then
                    safeSleep(2500)
                    okBack, backReason = warpToWorld(row.name, row.door)
                end
                if okBack then
                    safeSleep(500)
                    scanForeignLocksInWorld()
                    return true
                elseif backReason == "inaccessible" then
                    row.status = "Inaccessible"
                    return false
                else
                    row.status = "Retry Warp"
                    return false
                end
            end
        end
    end

    -- Pengecekan akhir sebelum benar-benar berhenti: JANGAN pernah stop bila di tas ternyata ada seed!
    safeSleep(450)
    syncInventoryCache()
    if hasEnoughSeedInBackpack(s1, s2) then
        addLog(string.format("[Storage] Sisa seed di tas terdeteksi (%d). Kembali tanam ke %s dulu...",
            getInvCount(s1), row.name))
        local okBack2, backReason2 = warpToWorld(row.name, row.door)
        if (not okBack2) and backReason2 == "timeout" and Engine.STATE.running then
            safeSleep(2500)
            okBack2, backReason2 = warpToWorld(row.name, row.door)
        end
        if okBack2 then
            safeSleep(500)
            scanForeignLocksInWorld()
            return true
        elseif backReason2 ~= "inaccessible" then
            row.status = "Retry Warp"
            return false
        end
    end

    addLog("[Peringatan] Stok seed di tas (0) & semua storage habis!")
    row.status = "No Seed"
    return false
end

-- ============================================================================
-- 5. AKSI TANAM & SPLICE (RANGE-VERIFIED & SMART RESUME)
-- ============================================================================
local function sendPlantPacket(tx, ty, itemID)
    if not sendPacketRaw then return false end
    itemID = tonumber(itemID) or 0
    if itemID <= 0 then return false end
    local p = getLocalSafe()
    local px = (p and (p.posX or (p.pos and p.pos.x))) or (tx * 32)
    local py = (p and (p.posY or (p.pos and p.pos.y))) or (ty * 32)
    local state = (px > (tx * 32)) and 48 or 32
    local ok = pcall(sendPacketRaw, false, {
        type = 3, value = itemID, px = tx, py = ty, x = px, y = py, state = state,
    })
    if ok and Engine.STATE.inv_cache and (Engine.STATE.inv_cache[itemID] or 0) > 0 then
        Engine.STATE.inv_cache[itemID] = math.max(0, Engine.STATE.inv_cache[itemID] - 1)
    end
    return ok
end

local function sendPunchPacket(tx, ty)
    if not sendPacketRaw then return false end
    local p = getLocalSafe()
    local px = (p and (p.posX or (p.pos and p.pos.x))) or (tx * 32)
    local py = (p and (p.posY or (p.pos and p.pos.y))) or (ty * 32)
    local state = (px > (tx * 32)) and 48 or 32
    local ok = pcall(sendPacketRaw, false, {
        type = 3, value = 18, px = tx, py = ty, x = px, y = py, state = state,
    })
    return ok
end

-- Mengembalikan "OK" atau "RESTOCK" jika kehabisan salah satu seed di tengah section
local function plantTileSection(spotList, plantY, s1, s2)
    if not Engine.STATE.running or not spotList or #spotList == 0 then return "OK" end
    local isSplice = (s1 > 0 and s2 > 0 and s1 ~= s2)
    local delayPlant  = math.max(60, tonumber(Engine.CFG.plant_delay) or 180)
    local delaySplice = math.max(60, tonumber(Engine.CFG.splice_delay) or 180)
    local blocked     = Engine.STATE.blocked_tiles
    local failCounts  = Engine.STATE.plant_fail_count

    if not isSplice then
        for _, sx in ipairs(spotList) do
            if not Engine.STATE.running then break end
            local k = sx .. "_" .. plantY
            if not blocked[k] and getTilePlantStatus(sx, plantY, s1, s2) == "EMPTY" then
                if getInvCount(s1) <= 0 then return "RESTOCK" end
                sendPlantPacket(sx, plantY, s1)
                safeSleep(delayPlant)
            end
        end

        safeSleep(80)
        for _ = 1, 3 do
            local needRetry = false
            for _, sx in ipairs(spotList) do
                local k = sx .. "_" .. plantY
                if not blocked[k] and getTilePlantStatus(sx, plantY, s1, s2) == "EMPTY" then
                    if getInvCount(s1) <= 0 then return "RESTOCK" end
                    needRetry = true
                    sendPlantPacket(sx, plantY, s1)
                    safeSleep(delayPlant)
                    local tNow = getTileSafe(sx, plantY)
                    local cpx, cpy = getPlayerTilePos()
                    local isNear = cpx and cpy and math.abs(cpx - sx) <= 2 and math.abs(cpy - plantY) <= 2
                    if isNear and tNow and tonumber(tNow.fg) == 0 and getInvCount(s1) > 0 then
                        failCounts[k] = (failCounts[k] or 0) + 1
                        if failCounts[k] >= 4 then
                            blocked[k] = true
                            addLog(string.format("[Lock] Petak (%d, %d) terkunci, dilewati.", sx, plantY))
                        end
                    else
                        failCounts[k] = 0
                    end
                end
            end
            if not needRetry then break end
            safeSleep(90)
        end
        return "OK"
    end

    -- ========================================================================
    -- MODE SPLICE 2 SEED (STRICT STATE-VERIFIED + ANTI-UNSPLICED RECOVERY)
    -- ========================================================================
    local plantedInSection = {}
    local plantedAnyS1 = false

    -- Fase 1: Tanam seed 1 HANYA pada petak EMPTY (dan hanya jika stok s1 & s2 tersedia)
    for _, sx in ipairs(spotList) do
        if not Engine.STATE.running then break end
        local k = sx .. "_" .. plantY
        if not blocked[k] then
            local st = getTilePlantStatus(sx, plantY, s1, s2)
            if st == "EMPTY" then
                if getInvCount(s1) <= 0 or getInvCount(s2) <= 0 then return "RESTOCK" end
                sendPlantPacket(sx, plantY, s1)
                plantedInSection[sx] = true
                plantedAnyS1 = true
                safeSleep(delayPlant)
            end
        end
    end

    -- Tunggu cooldown server Growtopia agar s1 benar-benar terdaftar di tile sebelum timpa s2
    if plantedAnyS1 then
        safeSleep(math.max(delaySplice, 180))
    end

    -- Fase 2: Timpa seed pasangan sesuai status AKTUAL tile (JANGAN timpa s2 ke petak EMPTY!)
    for _, sx in ipairs(spotList) do
        if not Engine.STATE.running then break end
        local k = sx .. "_" .. plantY
        if not blocked[k] then
            local st = getTilePlantStatus(sx, plantY, s1, s2)
            if st == "NEEDS_SPLICE_2" then
                if getInvCount(s2) <= 0 then return "RESTOCK" end
                sendPlantPacket(sx, plantY, s2)
                plantedInSection[sx] = true
                safeSleep(delayPlant)
            elseif st == "NEEDS_SPLICE_1" then
                if getInvCount(s1) <= 0 then return "RESTOCK" end
                sendPlantPacket(sx, plantY, s1)
                plantedInSection[sx] = true
                safeSleep(delayPlant)
            elseif st == "EMPTY" then
                -- Packet s1 sebelumnya ter-drop -> tanam s1 dulu, tunggu delaySplice, baru timpa s2!
                if getInvCount(s1) <= 0 or getInvCount(s2) <= 0 then return "RESTOCK" end
                sendPlantPacket(sx, plantY, s1)
                plantedInSection[sx] = true
                safeSleep(math.max(delaySplice, 180))
                sendPlantPacket(sx, plantY, s2)
                safeSleep(delayPlant)
            end
        end
    end

    -- Fase 3: Verifikasi ketat hingga 5x retry sampai SEMUA petak berubah menjadi hasil splice
    -- (fg ~= 0 dan fg ~= s1 dan fg ~= s2), bukan masih tertinggal sebagai seed mentah s1/s2!
    local verifyWait = math.max(180, delaySplice)
    safeSleep(verifyWait)

    for _ = 1, 5 do
        if not Engine.STATE.running then break end
        local allDone = true
        for _, sx in ipairs(spotList) do
            if not Engine.STATE.running then break end
            local k = sx .. "_" .. plantY
            if not blocked[k] then
                local tNow = getTileSafe(sx, plantY)
                local fgNow = tonumber(tNow and tNow.fg) or 0
                local st = getTilePlantStatus(sx, plantY, s1, s2)

                if st == "NEEDS_SPLICE_2" then
                    if getInvCount(s2) <= 0 then return "RESTOCK" end
                    allDone = false
                    sendPlantPacket(sx, plantY, s2)
                    safeSleep(math.max(delayPlant, 160))

                elseif st == "NEEDS_SPLICE_1" then
                    if getInvCount(s1) <= 0 then return "RESTOCK" end
                    allDone = false
                    sendPlantPacket(sx, plantY, s1)
                    safeSleep(math.max(delayPlant, 160))

                elseif st == "EMPTY" then
                    if getInvCount(s1) <= 0 or getInvCount(s2) <= 0 then return "RESTOCK" end
                    allDone = false
                    sendPlantPacket(sx, plantY, s1)
                    plantedInSection[sx] = true
                    safeSleep(math.max(delaySplice, 180))
                    sendPlantPacket(sx, plantY, s2)
                    safeSleep(math.max(delayPlant, 160))

                    local tChk = getTileSafe(sx, plantY)
                    local cpx, cpy = getPlayerTilePos()
                    local isNear = cpx and cpy and math.abs(cpx - sx) <= 2 and math.abs(cpy - plantY) <= 2
                    if isNear and tChk and tonumber(tChk.fg) == 0 and getInvCount(s1) > 0 and getInvCount(s2) > 0 then
                        failCounts[k] = (failCounts[k] or 0) + 1
                        if failCounts[k] >= 4 then
                            blocked[k] = true
                            addLog(string.format("[Lock] Petak (%d, %d) terkunci, dilewati.", sx, plantY))
                        end
                    else
                        failCounts[k] = 0
                    end

                elseif st == "DONE" and plantedInSection[sx] and Engine.CFG.auto_clear_failed_splice
                    and (fgNow == s1 or fgNow == s2) and isTileTree(tNow)
                then
                    -- Recovery otomatis: seed cepat-tumbuh yg baru kita tanam telanjur bertunas sebelum ter-splice
                    allDone = false
                    sendPunchPacket(sx, plantY)
                    safeSleep(math.max(delayPlant, 180))
                end
            end
        end
        if allDone then break end
        safeSleep(verifyWait)
    end
    return "OK"
end

local function findRowPlantPlan(plantY, curPx, s1, s2)
    local planted, plantable, plantableSet = {}, {}, {}
    for x = 0, 99 do
        if isTilePlantable(x, plantY, s1, s2) then
            table.insert(plantable, x)
            plantableSet[x] = true
        elseif isTilePlanted(x, plantY, s1, s2) then
            table.insert(planted, x)
        end
    end
    if #plantable == 0 then return nil, nil, nil, 0 end
    curPx = tonumber(curPx) or 0

    if #planted == 0 then
        if curPx >= 50 then return false, plantable[#plantable], nil, #plantable
        else return true, plantable[1], nil, #plantable end
    end

    local minPlanted, maxPlanted = planted[1], planted[#planted]
    local rightP, leftP = {}, {}
    for _, px in ipairs(plantable) do
        if px > maxPlanted then table.insert(rightP, px)
        elseif px < minPlanted then table.insert(leftP, px) end
    end

    if #rightP > 0 and #rightP >= #leftP then return true, rightP[1], maxPlanted, #plantable end
    if #leftP > 0 and #leftP > #rightP then return false, leftP[#leftP], minPlanted, #plantable end

    if curPx >= 50 then return false, plantable[#plantable], maxPlanted, #plantable
    else return true, plantable[1], minPlanted, #plantable end
end

local function executePlantRow(row, plantY, goingRight, startX, s1, s2)
    if Engine.CFG.plant_mode == "3zigzag" then
        local firstStandX = goingRight and 1 or 97
        if startX then
            local k = math.floor(startX / 3)
            firstStandX = math.max(1, math.min(97, k * 3 + 1))
        end

        if not moveSafeTo(firstStandX, plantY) and Engine.STATE.running then
            safeSleep(150)
            moveSafeTo(firstStandX, plantY)
        end

        local standX = firstStandX
        local step = goingRight and 3 or -3
        while (goingRight and standX <= 97) or ((not goingRight) and standX >= 1) do
            if not Engine.STATE.running then return false end
            local a = goingRight and (standX - 1) or (standX + 1)
            local b = standX
            local c = goingRight and (standX + 1) or (standX - 1)

            local need = (a >= 0 and a <= 99 and isTilePlantable(a, plantY, s1, s2))
                      or isTilePlantable(b, plantY, s1, s2)
                      or (c >= 0 and c <= 99 and isTilePlantable(c, plantY, s1, s2))

            if need then
                if not hasEnoughSeedInBackpack(s1, s2) then
                    if countPlantableSpots(s1, s2) == 0 then return true end
                    if not restockFromStorage(row, s1, s2) then return false end
                end
                local moved = moveSafeTo(standX, plantY)
                local cpx, cpy = getPlayerTilePos()
                if moved or (cpx and cpy and math.abs(cpx - standX) <= 2 and math.abs(cpy - plantY) <= 2) then
                    local spots = {}
                    if a >= 0 and a <= 99 and isTilePlantable(a, plantY, s1, s2) then table.insert(spots, a) end
                    if isTilePlantable(b, plantY, s1, s2) then table.insert(spots, b) end
                    if c >= 0 and c <= 99 and isTilePlantable(c, plantY, s1, s2) then table.insert(spots, c) end
                    if #spots > 0 then
                        local res = plantTileSection(spots, plantY, s1, s2)
                        if res == "RESTOCK" then
                            if not restockFromStorage(row, s1, s2) then return false end
                            -- Jangan geser standX dulu! Ulangi section yang sama agar tidak ada seed tertinggal!
                            standX = standX - step
                        end
                    end
                end
            end
            standX = standX + step
        end

        -- Tangani tepi x=98/99 atau x=0
        local edgeList = goingRight and { 98, 99 } or { 0 }
        local edgeTarget = goingRight and 98 or 0
        for _ = 1, 2 do
            local edgeSpots = {}
            for _, ex in ipairs(edgeList) do
                if isTilePlantable(ex, plantY, s1, s2) then table.insert(edgeSpots, ex) end
            end
            if #edgeSpots == 0 then break end
            if not hasEnoughSeedInBackpack(s1, s2) then
                if not restockFromStorage(row, s1, s2) then return false end
            end
            if moveSafeTo(edgeTarget, plantY) then
                local resE = plantTileSection(edgeSpots, plantY, s1, s2)
                if resE ~= "RESTOCK" then break end
            else
                break
            end
        end
    else
        -- Mode 1 by 1
        local bX = startX or (goingRight and 0 or 99)
        local eX = goingRight and 99 or 0
        local step = goingRight and 1 or -1
        moveSafeTo(bX, plantY)
        local curX = bX
        while (goingRight and curX <= eX) or ((not goingRight) and curX >= eX) do
            if not Engine.STATE.running then return false end
            if isTilePlantable(curX, plantY, s1, s2) then
                if not hasEnoughSeedInBackpack(s1, s2) then
                    if not restockFromStorage(row, s1, s2) then return false end
                end
                if moveSafeTo(curX, plantY) then
                    local res1 = plantTileSection({ curX }, plantY, s1, s2)
                    if res1 == "RESTOCK" then
                        if not restockFromStorage(row, s1, s2) then return false end
                        curX = curX - step
                    end
                end
            end
            curX = curX + step
        end
    end
    return true
end

local function processWorldRow(row)
    local s1 = ensureSeedID(row.seed_id)
    local s2 = ensureSeedID(row.splice_id)
    if s1 <= 0 then
        row.status = "No Seed ID"
        addLog("[Skip] World " .. row.name .. " tidak memiliki Seed ID valid.")
        return false
    end

    Engine.STATE.blocked_tiles = {}
    Engine.STATE.plant_fail_count = {}
    row.status = "Warping..."
    Engine.STATE.status_text = "Warp: " .. row.name

    local okWarp, warpReason = warpToWorld(row.name, row.door)
    if not okWarp then
        if not Engine.STATE.running or warpReason == "stopped" then
            row.status = "Ready"
            return false
        elseif warpReason == "inaccessible" then
            row.status = "Inaccessible"
            addLog("[Inaccessible] World " .. row.name .. " tidak dapat diakses (ditolak server)!")
            Engine.saveData()
            return false
        else
            row.status = "Retry Warp"
            addLog("[Warp Delay] Masuk ke " .. row.name .. " tertunda/lag — BUKAN Inaccessible, akan dicoba ulang.")
            Engine.saveData()
            return false
        end
    end

    safeSleep(500)
    syncInventoryCache()
    scanForeignLocksInWorld()

    local initHoles = countPlantableSpots(s1, s2)
    if initHoles < 0 then
        -- Tile mungkin masih memuat setelah entering -> tunggu ekstra hingga 4.5 detik sebelum mundur!
        local lw = 0
        while lw < 4500 and Engine.STATE.running and initHoles < 0 do
            safeSleep(300)
            lw = lw + 300
            if isWorldProperlyLoaded(row.name) then
                scanForeignLocksInWorld()
                initHoles = countPlantableSpots(s1, s2)
            end
        end
    end
    if initHoles == 0 then
        row.status = "Done"
        addLog("[Info] World " .. row.name .. " sudah penuh tertanam.")
        Engine.saveData()
        return true
    elseif initHoles < 0 then
        row.status = "Retry Warp"
        addLog("[Loading Delay] Tile world " .. row.name .. " belum selesai dimuat — bukan Inaccessible, akan dicoba ulang.")
        Engine.saveData()
        return false
    end

    if not hasEnoughSeedInBackpack(s1, s2) then
        if not restockFromStorage(row, s1, s2) then
            return false
        end
    end

    row.status = "Planting..."
    local maxPasses = (s2 > 0 and s1 ~= s2) and 3 or 2
    for sweepPass = 1, maxPasses do
        if not Engine.STATE.running then return false end
        local activeRows = {}
        for y = 0, 53 do
            for x = 0, 99 do
                if isTilePlantable(x, y, s1, s2) then
                    table.insert(activeRows, y)
                    break
                end
            end
        end
        if #activeRows == 0 then break end
        if sweepPass > 1 then
            addLog(string.format("[Sweep %d/%d] Membersihkan %d baris yang masih ada petak kosong / belum ter-splice...",
                sweepPass, maxPasses, #activeRows))
        end

        for idx, plantY in ipairs(activeRows) do
            if not Engine.STATE.running then return false end
            if not isWorldProperlyLoaded(row.name) then
                row.status = "Disconnected"
                return false
            end
            local curPx = getPlayerTilePos()
            local goingRight, startX, lastSeedX, holes = findRowPlantPlan(plantY, curPx, s1, s2)
            -- Pada sweep pembersihan (pass > 1), sapu seluruh baris dari ujung ke ujung agar petak di tengah ikut tuntas!
            if sweepPass > 1 and goingRight ~= nil then
                startX = goingRight and 0 or 99
            end
            if goingRight ~= nil then
                Engine.STATE.status_text = string.format("%s Y=%d (%d/%d)", row.name, plantY, idx, #activeRows)
                row.status = string.format("Y=%d (%d/%d)", plantY, idx, #activeRows)
                addLog(string.format("[Plant] %s Y=%d [%s] Mulai X=%d (Last: %s | Sisa: %d)",
                    row.name, plantY, goingRight and "L->R" or "R->L", startX or 0, tostring(lastSeedX or "Fresh"), holes or 0))
                if not executePlantRow(row, plantY, goingRight, startX, s1, s2) then
                    return false
                end
            end
        end
        safeSleep(250)
    end

    local rem = countPlantableSpots(s1, s2)
    if rem == 0 then
        row.status = "Done"
        addLog("[Selesai] World " .. row.name .. " 100% tuntas!")
        Engine.saveData()
        return true
    else
        row.status = string.format("Sisa %d", rem)
        Engine.saveData()
        return false
    end
end

-- ============================================================================
-- 6. MAIN COROUTINE LOOP & CONTROLS
-- ============================================================================
local function mainPlantLoop()
    Engine.STATE.running = true
    applyCheatToggles()
    addLog("Auto Plant dimulai.")

    local retryPass = 0
    while Engine.STATE.running do
        local ranAny = false
        for idx, row in ipairs(Engine.STATE.rows) do
            if not Engine.STATE.running then break end
            if row.status ~= "Done" and row.status ~= "Inaccessible" then
                ranAny = true
                Engine.STATE.active_row_idx = idx
                processWorldRow(row)
                Engine.saveData()
                safeSleep(400)
            end
        end

        if not Engine.STATE.running then break end

        -- Cek apakah ada world yang hanya tertunda entering/delay ("Retry Warp")
        local pendingRetry = 0
        for _, row in ipairs(Engine.STATE.rows) do
            if row.status == "Retry Warp" then pendingRetry = pendingRetry + 1 end
        end

        if pendingRetry > 0 and retryPass < 3 then
            retryPass = retryPass + 1
            addLog(string.format("[Retry Warp %d/3] %d world tertunda saat entering, mencoba ulang dalam 3 detik...",
                retryPass, pendingRetry))
            Engine.STATE.status_text = string.format("Retry Warp (%d/3)...", retryPass)
            safeSleep(3000)
        elseif Engine.CFG.loop_enabled and #Engine.STATE.rows > 0 then
            retryPass = 0
            addLog("[Loop] Semua antrean selesai, mengulang dari awal dalam 3 detik...")
            Engine.STATE.status_text = "Loop Waiting..."
            for _, row in ipairs(Engine.STATE.rows) do
                if row.status ~= "Inaccessible" then row.status = "Ready" end
            end
            Engine.saveData()
            safeSleep(3000)
        else
            break
        end
    end

    Engine.STATE.running = false
    Engine.STATE.enabled = false
    Engine.STATE.active_row_idx = 0
    Engine.STATE.status_text = "Idle"
    addLog("Auto Plant berhenti.")
end

function Engine.start()
    if Engine.STATE.running then return end
    if #Engine.STATE.rows == 0 then
        addLogUI("[Peringatan] Daftar world kosong! Tambahkan Name:ID:SeedID:SpliceID dulu.")
        Engine.STATE.status_text = "List Kosong"
        Engine.STATE.enabled = false
        return
    end
    Engine.STATE.enabled = true

    local function safeRunner()
        local ok, err = xpcall(mainPlantLoop, function(e)
            return tostring(e) .. "\n" .. (debug and debug.traceback and debug.traceback() or "")
        end)
        if not ok then
            addLog("`4[Crash Error] `w" .. tostring(err))
            Engine.STATE.running = false
            Engine.STATE.enabled = false
            Engine.STATE.status_text = "Error"
        end
    end

    if runCoroutine then
        pcall(runCoroutine, safeRunner)
    else
        local co = coroutine.create(safeRunner)
        coroutine.resume(co)
    end
end

function Engine.stop()
    Engine.STATE.running = false
    Engine.STATE.enabled = false
    Engine.STATE.status_text = "Stopped"
end

function Engine.removeInaccessible()
    local kept = {}
    local removed = 0
    for _, row in ipairs(Engine.STATE.rows) do
        local st = tostring(row.status or ""):lower()
        if st:find("inaccessible", 1, true) or st:find("no seed id", 1, true) then
            removed = removed + 1
        else
            table.insert(kept, row)
        end
    end
    Engine.STATE.rows = kept
    Engine.STATE.selected_idx = 0
    Engine.saveData()
    addLogUI(string.format("[Clean] Menghapus %d world inaccessible.", removed))
    return removed
end

function Engine.resetAllStatus()
    for _, row in ipairs(Engine.STATE.rows) do
        row.status = "Ready"
    end
    Engine.saveData()
    addLogUI("[Reset] Seluruh status world di-reset ke 'Ready'.")
end

function Engine.init(hub)
    HUB_REF = hub
    Engine.loadData()
end

return Engine
