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
    warp_delay    = 3500,     -- ms
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

local function isTileTree(t)
    if not t then return false end
    local fg = tonumber(t.fg) or 0
    if fg <= 0 then return false end
    if t.readyharvest == true then return true end
    if t.canHarvest and type(t.canHarvest) == "function" then
        local okH, resH = pcall(t.canHarvest, t)
        if okH and resH == true then return true end
    end
    if t.extra and type(t.extra) == "table" then
        local fruits = tonumber(t.extra.fruitcount) or 0
        if fruits > 0 then return true end
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

local function warpToWorld(worldName, doorID)
    worldName = cleanWorldName(worldName)
    doorID = cleanWorldName(doorID)
    if worldName == "" then return false end

    -- Jika sudah berada di world target tanpa Door ID, langsung lanjut!
    if getCurrentWorldSafe() == worldName and doorID == "" then
        local tw = 0
        while tw < 1500 and Engine.STATE.running and (not hasAnyLoadedTiles()) do
            safeSleep(150); tw = tw + 150
        end
        applyCheatToggles()
        return true
    end

    local joinStr = (doorID ~= "") and (worldName .. "|" .. doorID) or worldName
    for attempt = 1, 3 do
        if not Engine.STATE.running then return false end
        if sendPacket then
            pcall(sendPacket, 3, "action|join_request\nname|" .. joinStr .. "\ninvitedWorld|0\n")
        elseif growtopia and growtopia.warpTo then
            pcall(growtopia.warpTo, joinStr)
        end

        local waitMs = math.max(3500, tonumber(Engine.CFG.warp_delay) or 4000)
        local elapsed = 0
        while elapsed < waitMs and Engine.STATE.running do
            safeSleep(250)
            elapsed = elapsed + 250
            if getCurrentWorldSafe() == worldName then
                -- World sudah masuk! Tunggu tile selesai termuat maksimal 2 detik, lalu langsung jalan!
                local tw = 0
                while tw < 2000 and Engine.STATE.running and (not hasAnyLoadedTiles()) do
                    safeSleep(150); tw = tw + 150
                end
                safeSleep(450)
                applyCheatToggles()
                return true
            end
        end
    end

    local finalW = getCurrentWorldSafe()
    if finalW == worldName then
        applyCheatToggles()
        return true
    end
    addLog(string.format("[Warp Info] Target: %s | World aktif sekarang: %s", worldName, finalW ~= "" and finalW or "EXIT"))
    return false
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
                if warpToWorld(row.name, row.door) then
                    safeSleep(500)
                    scanForeignLocksInWorld()
                    return true
                else
                    row.status = "Inaccessible"
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
        if warpToWorld(row.name, row.door) then
            safeSleep(500)
            scanForeignLocksInWorld()
            return true
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

local function plantTileSection(spotList, plantY, s1, s2)
    if not Engine.STATE.running or not spotList or #spotList == 0 then return true end
    local isSplice = (s1 > 0 and s2 > 0 and s1 ~= s2)
    local delayPlant  = tonumber(Engine.CFG.plant_delay) or 180
    local delaySplice = tonumber(Engine.CFG.splice_delay) or 180
    local blocked     = Engine.STATE.blocked_tiles
    local failCounts  = Engine.STATE.plant_fail_count

    if not isSplice then
        for _, sx in ipairs(spotList) do
            if not Engine.STATE.running then break end
            local k = sx .. "_" .. plantY
            if not blocked[k] and getTilePlantStatus(sx, plantY, s1, s2) == "EMPTY" then
                sendPlantPacket(sx, plantY, s1)
                safeSleep(delayPlant)
            end
        end

        safeSleep(60)
        for _ = 1, 3 do
            local needRetry = false
            for _, sx in ipairs(spotList) do
                local k = sx .. "_" .. plantY
                if not blocked[k] and getTilePlantStatus(sx, plantY, s1, s2) == "EMPTY" then
                    needRetry = true
                    sendPlantPacket(sx, plantY, s1)
                    safeSleep(delayPlant)
                    local tNow = getTileSafe(sx, plantY)
                    local cpx, cpy = getPlayerTilePos()
                    local isNear = cpx and cpy and math.abs(cpx - sx) <= 2 and math.abs(cpy - plantY) <= 2
                    if isNear and tNow and tonumber(tNow.fg) == 0 and hasEnoughSeedInBackpack(s1, s2) then
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
            safeSleep(80)
        end
        return true
    end

    -- Mode Splice 2 Seed
    local plantedS1 = {}
    for _, sx in ipairs(spotList) do
        if not Engine.STATE.running then break end
        local k = sx .. "_" .. plantY
        if not blocked[k] and getTilePlantStatus(sx, plantY, s1, s2) == "EMPTY" then
            sendPlantPacket(sx, plantY, s1)
            plantedS1[sx] = true
            safeSleep(delayPlant)
        end
    end

    safeSleep(delaySplice)

    for _, sx in ipairs(spotList) do
        if not Engine.STATE.running then break end
        local k = sx .. "_" .. plantY
        if not blocked[k] then
            local st = getTilePlantStatus(sx, plantY, s1, s2)
            if plantedS1[sx] or st == "NEEDS_SPLICE_2" or st == "EMPTY" then
                sendPlantPacket(sx, plantY, s2)
                safeSleep(delayPlant)
            elseif st == "NEEDS_SPLICE_1" then
                sendPlantPacket(sx, plantY, s1)
                safeSleep(delayPlant)
            end
        end
    end

    safeSleep(120)
    for _ = 1, 3 do
        if not Engine.STATE.running then break end
        local allDone = true
        for _, sx in ipairs(spotList) do
            local k = sx .. "_" .. plantY
            if not blocked[k] then
                local st = getTilePlantStatus(sx, plantY, s1, s2)
                if st == "NEEDS_SPLICE_2" then
                    allDone = false; sendPlantPacket(sx, plantY, s2); safeSleep(delayPlant)
                elseif st == "NEEDS_SPLICE_1" then
                    allDone = false; sendPlantPacket(sx, plantY, s1); safeSleep(delayPlant)
                elseif st == "EMPTY" then
                    allDone = false
                    sendPlantPacket(sx, plantY, s1); safeSleep(delaySplice)
                    sendPlantPacket(sx, plantY, s2); safeSleep(delayPlant)
                    local tNow = getTileSafe(sx, plantY)
                    local cpx, cpy = getPlayerTilePos()
                    local isNear = cpx and cpy and math.abs(cpx - sx) <= 2 and math.abs(cpy - plantY) <= 2
                    if isNear and tNow and tonumber(tNow.fg) == 0 and hasEnoughSeedInBackpack(s1, s2) then
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
        end
        if allDone then break end
        safeSleep(100)
    end
    return true
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
                    if #spots > 0 then plantTileSection(spots, plantY, s1, s2) end
                end
            end
            standX = standX + step
        end

        -- Tangani tepi x=98/99 atau x=0
        local edgeList = goingRight and { 98, 99 } or { 0 }
        local edgeTarget = goingRight and 98 or 0
        local edgeSpots = {}
        for _, ex in ipairs(edgeList) do
            if isTilePlantable(ex, plantY, s1, s2) then table.insert(edgeSpots, ex) end
        end
        if #edgeSpots > 0 then
            if not hasEnoughSeedInBackpack(s1, s2) then
                if not restockFromStorage(row, s1, s2) then return false end
            end
            if moveSafeTo(edgeTarget, plantY) then
                plantTileSection(edgeSpots, plantY, s1, s2)
            end
        end
    else
        -- Mode 1 by 1
        local bX = startX or (goingRight and 0 or 99)
        local eX = goingRight and 99 or 0
        local step = goingRight and 1 or -1
        moveSafeTo(bX, plantY)
        for curX = bX, eX, step do
            if not Engine.STATE.running then return false end
            if isTilePlantable(curX, plantY, s1, s2) then
                if not hasEnoughSeedInBackpack(s1, s2) then
                    if not restockFromStorage(row, s1, s2) then return false end
                end
                if moveSafeTo(curX, plantY) then
                    plantTileSection({ curX }, plantY, s1, s2)
                end
            end
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

    if not warpToWorld(row.name, row.door) then
        row.status = "Inaccessible"
        addLog("[Inaccessible] Gagal masuk ke world " .. row.name .. "!")
        Engine.saveData()
        return false
    end

    safeSleep(500)
    syncInventoryCache()
    scanForeignLocksInWorld()

    local initHoles = countPlantableSpots(s1, s2)
    if initHoles == 0 then
        row.status = "Done"
        addLog("[Info] World " .. row.name .. " sudah penuh tertanam.")
        Engine.saveData()
        return true
    elseif initHoles < 0 then
        row.status = "Inaccessible"
        return false
    end

    if not hasEnoughSeedInBackpack(s1, s2) then
        if not restockFromStorage(row, s1, s2) then
            return false
        end
    end

    row.status = "Planting..."
    local activeRows = {}
    for y = 0, 53 do
        for x = 0, 99 do
            if isTilePlantable(x, y, s1, s2) then
                table.insert(activeRows, y)
                break
            end
        end
    end

    for idx, plantY in ipairs(activeRows) do
        if not Engine.STATE.running then return false end
        if not isWorldProperlyLoaded(row.name) then
            row.status = "Disconnected"
            return false
        end
        local curPx = getPlayerTilePos()
        local goingRight, startX, lastSeedX, holes = findRowPlantPlan(plantY, curPx, s1, s2)
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

        if Engine.CFG.loop_enabled and #Engine.STATE.rows > 0 then
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
