-- ============================================================================
-- AUTO PLANT & SPLICE - BOREN STORE (GROWLAUNCHER)
-- ============================================================================

local SCRIPT_NAME    = "Auto Plant & Splice"
local SCRIPT_VERSION = "2.0.0"
local SCRIPT_AUTHOR  = "Boren Store"
local PREF_FILE      = "boren_auto_plant_prefs.json"

-- ============================================================================
-- 1. PREFERENCES & DEFAULT CONFIGURATION
-- ============================================================================
local pref = nil
if preferences and preferences.new then
    pcall(function() pref = preferences:new(PREF_FILE) end)
elseif Preferences and Preferences.new then
    pcall(function() pref = Preferences:new(PREF_FILE) end)
end

local function savePrefs(cfg)
    if not pref then return end
    pcall(function()
        for k, v in pairs(cfg) do
            if type(v) ~= "function" and type(v) ~= "userdata" then
                pref:set(k, v)
            end
        end
        if pref.save then pref:save() end
    end)
end

local function loadPref(key, default)
    if not pref then return default end
    local ok, val = pcall(function() return pref:get(key, default) end)
    if ok and val ~= nil then return val end
    return default
end

local CFG = {
    -- Mode & Fitur Tanam
    plant_mode          = loadPref("plant_mode", "3zigzag"),    -- "3zigzag"| "1by1"
    splice_mode         = loadPref("splice_mode", false),       -- true = splice 2 seed | false = 1 seed
    seed_1_id           = tonumber(loadPref("seed_1_id", 3)) or 3,       -- Default Dirt Seed
    seed_1_name         = tostring(loadPref("seed_1_name", "Dirt Seed")),
    seed_2_id           = tonumber(loadPref("seed_2_id", 15)) or 15,     -- Default Rock Seed
    seed_2_name         = tostring(loadPref("seed_2_name", "Rock Seed")),

    -- Delay & Kecepatan (ms)
    plant_delay         = tonumber(loadPref("plant_delay", 90)) or 90,
    splice_delay        = tonumber(loadPref("splice_delay", 100)) or 100,
    step_delay          = tonumber(loadPref("step_delay", 110)) or 110,
    warp_delay          = tonumber(loadPref("warp_delay", 3500)) or 3500,

    -- Restock & Storage Settings
    min_seed_bp         = tonumber(loadPref("min_seed_bp", 3)) or 3,      -- Sisa seed di BP untuk memicu ambil ke storage
    target_seed_bp      = tonumber(loadPref("target_seed_bp", 150)) or 150,-- Target ambil seed di storage
    active_storage_idx  = tonumber(loadPref("active_storage_idx", 1)) or 1,
    collect_range       = tonumber(loadPref("collect_range", 3)) or 3,

    -- Toggles & Keamanan
    ignore_gems         = loadPref("ignore_gems", true),        -- Abaikan gems (ID 112)
    use_modfly          = loadPref("use_modfly", true),
    auto_reconnect      = loadPref("auto_reconnect", true),
    anti_lava           = loadPref("anti_lava", true),

    -- World Lists
    world_list          = loadPref("world_list", {}),           -- Antrean World Farm
    storage_world_list  = loadPref("storage_world_list", {}),   -- Antrean World Storage Seed

    -- Buffer Input Manual
    manual_world_text   = loadPref("manual_world_text", ""),
    manual_door_text    = loadPref("manual_door_text", ""),
    manual_storage_text = loadPref("manual_storage_text", ""),
    manual_stor_door    = loadPref("manual_stor_door", ""),

    -- File Storage Paten di Folder Download HP
    world_file_name     = loadPref("world_file_name", "boren_plant_worlds.txt"),
    storage_file_name   = loadPref("storage_file_name", "boren_plant_storage.txt"),
}

-- Pastikan list berupa table
if type(CFG.world_list) ~= "table" then CFG.world_list = {} end
if type(CFG.storage_world_list) ~= "table" then CFG.storage_world_list = {} end

-- ============================================================================
-- 2. RUNTIME STATE & LOGGER
-- ============================================================================
local STATE = {
    running             = false,
    paused              = false,
    current_step        = "Idle",
    status_text         = "Bot Siap",
    active_world_idx    = 1,
    active_farm_world   = "",
    active_farm_door    = "",
    saved_farm_x        = nil,
    saved_farm_y        = nil,
    active_storage_idx  = 1,
    anti_take_active    = false,
    hooks_installed     = false,
    logs                = {},
    error_logs          = {},
    error_count         = 0,
    cached_inv          = {},
    buf_world_name      = "",
    buf_world_door      = "",
    buf_storage_name    = "",
    buf_storage_door    = "",
    buf_seed_1_id       = CFG.seed_1_id,
    buf_seed_2_id       = CFG.seed_2_id,
    console_errors_only = false,
    suppress_dialog     = false,
    reconnecting        = false,
}

-- Forward Declarations
local updatePowerStatusList
local updateSeedStatusDisplay
local updateWorldDisplayList
local updateStorageDisplayList
local updateFileInfoDisplayList
local updateBagDisplayList
local syncInventoryCache
local updateLogDisplayList
local openWorldListManagerDialog
local openEditWorldEntryDialog
local openStorageListManagerDialog
local openEditStorageEntryDialog
local openPasteWorldListDialog
local openCopyAllWorldsDialog
local parseAndValidateWorldBatch
local parseAndValidateStorageBatch
local resolvePickedItemID

-- JSON Encoder Sederhana
local function jsonEncode(val)
    local t = type(val)
    if t == "table" then
        local isArr = true
        local maxI = 0
        for k, _ in pairs(val) do
            if type(k) ~= "number" or k <= 0 or math.floor(k) ~= k then
                isArr = false
                break
            end
            if k > maxI then maxI = k end
        end
        if isArr and maxI == #val then
            local parts = {}
            for i = 1, #val do
                table.insert(parts, jsonEncode(val[i]))
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            local parts = {}
            for k, v in pairs(val) do
                table.insert(parts, string.format("%s:%s", jsonEncode(tostring(k)), jsonEncode(v)))
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    elseif t == "string" then
        local s = val:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t')
        return '"' .. s .. '"'
    elseif t == "number" or t == "boolean" then
        return tostring(val)
    else
        return "null"
    end
end

local function addLog(msg)
    local timestamp = os.date("%H:%M:%S")
    local textStr = tostring(msg)
    local entry = string.format("[%s] %s", timestamp, textStr)
    table.insert(STATE.logs, 1, entry)
    if #STATE.logs > 60 then table.remove(STATE.logs) end

    local low = textStr:lower()
    if low:find("error") or low:find("gagal") or low:find("warn") or low:find("habis") then
        STATE.error_count = (STATE.error_count or 0) + 1
        table.insert(STATE.error_logs, 1, entry)
        if #STATE.error_logs > 40 then table.remove(STATE.error_logs) end
    end

    if LogToConsole then
        pcall(LogToConsole, "`9[Boren Plant] `0" .. textStr)
    end
end

local function setStatus(step, detail)
    STATE.current_step = step or STATE.current_step
    if detail then
        STATE.status_text = detail
        addLog(step .. " -> " .. detail)
    else
        STATE.status_text = step
        addLog(step)
    end
    if updatePowerStatusList then pcall(updatePowerStatusList) end
end

local function persistConfig()
    savePrefs(CFG)
end

-- ============================================================================
-- 3. ITEM & INVENTORY HELPERS
-- ============================================================================
local SEED_NAMES = {
    [3]   = "Dirt Seed",
    [5]   = "Grass Seed",
    [11]  = "Lava Seed",
    [15]  = "Rock Seed",
    [17]  = "Cave Background Seed",
    [27]  = "Wood Block Seed",
    [103] = "Wooden Platform Seed",
    [340] = "Chandelier Seed",
    [4585]= "Pepper Tree Seed",
    [5667]= "Laser Grid Seed",
}

local function getItemNameSafe(itemID)
    itemID = tonumber(itemID) or 0
    if itemID <= 0 then return "" end
    if SEED_NAMES[itemID] then return SEED_NAMES[itemID] end

    if getItemInfoByID then
        local ok, info = pcall(getItemInfoByID, itemID)
        if ok and info and info.name and info.name ~= "" then
            return tostring(info.name)
        end
    end

    if growtopia and growtopia.getItemName then
        local ok, n = pcall(growtopia.getItemName, itemID)
        if ok and n and n ~= "" then
            return tostring(n)
        end
    end

    if item_info_manager and item_info_manager.getItemName then
        local ok, n = pcall(item_info_manager.getItemName, itemID)
        if ok and n and n ~= "" then
            return tostring(n)
        end
    end

    if ItemInfo and ItemInfo.getItem then
        local ok, info = pcall(ItemInfo.getItem, itemID)
        if ok and info and info.name and info.name ~= "" then
            return tostring(info.name)
        end
    end

    return ""
end

local function ensureSeedID(itemID)
    itemID = math.floor(tonumber(itemID) or 0)
    if itemID <= 0 then return 0 end

    -- Kasus 1: ID sudah ganjil (identifikasi standar Seed di Growtopia)
    -- Contoh: Dirt Seed = 3, Lava Seed = 5, Rock Seed = 11, Cave Seed = 15, Pepper Seed = 4585, Laser Grid Seed = 5667
    if itemID % 2 == 1 then
        return itemID
    end

    -- Kasus 2: ID genap (User memilih Block / Tree di tas backpack, bukan Seed-nya)
    -- Sesuai standar Lucifer (Farhad Auto Harvest / Lucifer scripts):
    -- Rumus resmi Growtopia: SeedID = BlockID + 1 !
    -- Contoh: Cave Background (14) -> Cave Seed (15)
    --         Pepper Tree (4584) -> Pepper Seed (4585)
    --         Dirt (2) -> Dirt Seed (3)
    --         Rock (10) -> Rock Seed (11)
    --         Laser Grid (5666) -> Laser Grid Seed (5667)
    return itemID + 1
end

local function resolveSeedName(itemID)
    itemID = tonumber(itemID) or 0
    if itemID <= 0 then return "None" end
    local name = getItemNameSafe(itemID)
    if name ~= "" then return name end
    if itemID % 2 == 1 then
        local blockName = getItemNameSafe(itemID - 1)
        if blockName ~= "" then
            return blockName .. " Seed"
        end
        return "Seed #" .. tostring(itemID)
    end
    return "Item #" .. tostring(itemID)
end

local function isSeedByName(itemID)
    itemID = tonumber(itemID) or 0
    if itemID <= 1 or itemID == 112 then return false, "" end -- ID 112 = Gems

    local name = getItemNameSafe(itemID)
    if name ~= "" then
        -- Cek kata "seed" di dalam nama barang (case-insensitive)
        if name:lower():find("seed", 1, true) then
            return true, name
        end
    end

    -- Khusus jika terdaftar di tabel SEED_NAMES kita
    if SEED_NAMES[itemID] and SEED_NAMES[itemID]:lower():find("seed", 1, true) then
        return true, SEED_NAMES[itemID]
    end

    return false, name
end

local function getInventorySafe()
    local inv = nil
    if getInventory then
        local ok, res = pcall(getInventory)
        if ok and type(res) == "table" then inv = res end
    end
    if not inv and getInventoryItems then
        local ok, res = pcall(getInventoryItems)
        if ok and type(res) == "table" then inv = res end
    end
    if not inv and growtopia and growtopia.getInventory then
        local ok, res = pcall(growtopia.getInventory)
        if ok and type(res) == "table" then inv = res end
    end
    return inv or {}
end

local function getInvCount(itemID)
    itemID = tonumber(itemID) or 0
    if itemID <= 0 then return 0 end

    -- 1. Metode cepat C++ Growlauncher (Paling akurat & live)
    if growtopia and growtopia.checkInventoryCount then
        local ok, cnt = pcall(growtopia.checkInventoryCount, itemID)
        if ok and type(cnt) == "number" and cnt >= 0 then
            return cnt
        end
    end

    -- 2. Scan tabel inventory fallback (dengan penggabungan seluruh slot)
    local inv = getInventorySafe()
    local total = 0
    for _, it in pairs(inv) do
        local id = tonumber(it.id or it.itemid or it.itemID) or 0
        if id == itemID then
            total = total + (tonumber(it.amount or it.count) or 0)
        end
    end
    return total
end

local function cleanItemName(name)
    if type(name) ~= "string" then return "" end
    return name:gsub("`.", ""):gsub("^%s+", ""):gsub("%s+$", "")
end

resolvePickedItemID = function(value)
    if not value or value == "" or value == 0 or value == "0" then return nil end
    if type(value) == "table" then
        value = value.id or value.itemID or value.itemid or value.value or value.name
    end
    local num = tonumber(value)
    if num and num > 0 then
        return math.floor(num)
    end
    if type(value) == "string" and value ~= "" then
        local cleanVal = cleanItemName(value)
        if cleanVal == "" or #cleanVal < 2 then return nil end

        local sNum = tonumber(cleanVal)
        if sNum and sNum > 0 then
            return math.floor(sNum)
        end

        local embeddedId = cleanVal:match("%((%d+)%)") or cleanVal:match("#(%d+)")
        if embeddedId and tonumber(embeddedId) and tonumber(embeddedId) > 0 then
            return math.floor(tonumber(embeddedId))
        end

        local cleanLow = cleanVal:lower()
        for sId, sName in pairs(SEED_NAMES) do
            if sName and (sName:lower() == cleanLow or sName:lower() == cleanLow .. " seed") then
                return sId
            end
        end

        local function tryLookup(str)
            if not str or str == "" or #str < 2 then return nil end
            -- 1. API C++ Resmi GrowLauncher: getItemInfoByName
            if getItemInfoByName then
                local ok, info = pcall(getItemInfoByName, str)
                if ok and info and tonumber(info.id) and tonumber(info.id) > 0 then
                    return tonumber(info.id)
                end
            end
            -- 2. API C++ Resmi GrowLauncher: itemInfoManager.getItemInfoByName
            if itemInfoManager and itemInfoManager.getItemInfoByName then
                local ok, info = pcall(itemInfoManager.getItemInfoByName, str)
                if ok and info and tonumber(info.id) and tonumber(info.id) > 0 then
                    return tonumber(info.id)
                end
            end
            -- 3. Fallback findItemID
            if findItemID then
                local ok, id = pcall(findItemID, str)
                if ok and tonumber(id) and tonumber(id) > 0 then
                    return tonumber(id)
                end
            end
            -- 4. Fallback growtopia.getItemID
            if growtopia and growtopia.getItemID then
                local ok, id = pcall(growtopia.getItemID, str)
                if ok and tonumber(id) and tonumber(id) > 0 then
                    return tonumber(id)
                end
            end
            return nil
        end

        local lookedUp = tryLookup(cleanVal)
        if lookedUp and lookedUp > 0 then
            return lookedUp
        end
        if not cleanLow:find("seed", 1, true) then
            local lookedUpSeed = tryLookup(cleanVal .. " Seed")
            if lookedUpSeed and lookedUpSeed > 0 then
                return lookedUpSeed
            end
        end
    end
    return nil
end

syncInventoryCache = function()
    local inv = getInventorySafe()
    local map = {}
    for _, it in pairs(inv) do
        local id = tonumber(it.id or it.itemid or it.itemID) or 0
        if id > 0 then
            local cnt = getInvCount(id)
            if cnt > 0 then
                map[id] = {
                    id = id,
                    name = resolveSeedName(id),
                    amount = cnt
                }
            end
        end
    end
    local c = {}
    for _, it in pairs(map) do
        table.insert(c, it)
    end
    table.sort(c, function(a, b) return a.amount > b.amount end)
    STATE.cached_inv = c
    if updateBagDisplayList then pcall(updateBagDisplayList) end
end

-- ============================================================================
-- 4. STATUS TAGS & WORLD LIST HELPERS
-- ============================================================================
local function getWorldEntryStatusTag(entry)
    if entry and entry.done then return "DONE" end
    if STATE.running and entry and (STATE.active_farm_world == entry.name or entry.status == "PROSES") then
        return "PROSES"
    end
    return "ANTRI"
end

local function buildWorldDisplayRows()
    local wList = {}
    for i, entry in ipairs(CFG.world_list) do
        local st = getWorldEntryStatusTag(entry)
        local dInfo = (entry.door and entry.door ~= "") and ("Door: " .. entry.door) or "White Door"
        table.insert(wList, { string.format("%d. %s [%s]", i, entry.name, st), dInfo })
    end
    if #wList == 0 then
        table.insert(wList, { "Antrean World Farm Kosong", "Ketik Nama World lalu klik + Tambah World" })
    end
    return wList
end

local function buildStorageDisplayRows()
    local sList = {}
    for i, entry in ipairs(CFG.storage_world_list) do
        local activeTag = (i == STATE.active_storage_idx) and " [AKTIF]" or ""
        local dInfo = (entry.door and entry.door ~= "") and ("Door: " .. entry.door) or "White Door"
        table.insert(sList, { string.format("%d. %s%s", i, entry.name, activeTag), dInfo })
    end
    if #sList == 0 then
        table.insert(sList, { "Antrean World Gudang Kosong", "Ketik Nama Gudang lalu klik + Tambah Gudang" })
    end
    return sList
end

updateWorldDisplayList = function()
    if not editValue then return end
    pcall(editValue, "ap_world_display_list", jsonEncode(buildWorldDisplayRows()))
end

updateStorageDisplayList = function()
    if not editValue then return end
    pcall(editValue, "ap_storage_display_list", jsonEncode(buildStorageDisplayRows()))
end

local function isWorldInList(wList, worldName)
    local wTarget = tostring(worldName or ""):upper():gsub("%s+", "")
    if wTarget == "" or type(wList) ~= "table" then return false end
    for _, e in ipairs(wList) do
        if type(e) == "table" and tostring(e.name or ""):upper():gsub("%s+", "") == wTarget then
            return true
        end
    end
    return false
end

-- ============================================================================
-- 5. QUICK PASTE BATCH VALIDATOR (FARM & STORAGE)
-- ============================================================================
local function parseWorldEntryToken(token)
    token = tostring(token or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if token == "" then return nil end
    local w, d = token:match("^([^:|]+)[:|](.*)$")
    if not w then
        w = token
        d = ""
    end
    w = w:gsub("%s+", ""):upper()
    d = d:gsub("^%s+", ""):gsub("%s+$", "")
    if w == "" then return nil end
    return { name = w, door = d, done = false, status = "ANTRI" }
end

parseAndValidateWorldBatch = function(rawText, replaceMode)
    if type(rawText) ~= "string" or rawText == "" then
        return 0, 0, 0, "Teks kosong! Silakan tempel daftar world terlebih dahulu."
    end
    local cleaned = rawText:gsub("[\"\'%[%]%(%)]", " "):gsub("\t", " ")
    local tokens = {}
    for part in cleaned:gmatch("[^\r\n;,]+") do
        local trimmed = part:gsub("^%s+", ""):gsub("%s+$", "")
        if trimmed ~= "" then table.insert(tokens, trimmed) end
    end
    if #tokens == 0 then
        return 0, 0, 0, "Tidak ada data world yang valid ditemukan."
    end

    local candidateList = {}
    local seen = {}
    local dups = 0
    local ignored = 0

    for _, token in ipairs(tokens) do
        local normToken = token:gsub("%s*[:|]%s*", ":")
        local parsed = parseWorldEntryToken(normToken)
        if parsed and parsed.name ~= "" then
            local validName = parsed.name:match("^([%w_]+)$")
            if validName and #validName >= 1 and #validName <= 24 then
                parsed.name = validName:upper()
                if seen[parsed.name] then
                    dups = dups + 1
                else
                    seen[parsed.name] = true
                    table.insert(candidateList, parsed)
                end
            else
                ignored = ignored + 1
            end
        else
            ignored = ignored + 1
        end
    end

    if #candidateList == 0 then
        return 0, dups, ignored, "Tidak ada world valid yang dapat ditambahkan."
    end

    local added = 0
    if replaceMode then
        CFG.world_list = {}
        STATE.active_world_idx = 1
        for _, e in ipairs(candidateList) do
            table.insert(CFG.world_list, e)
            added = added + 1
        end
    else
        for _, e in ipairs(candidateList) do
            if not isWorldInList(CFG.world_list, e.name) then
                table.insert(CFG.world_list, e)
                added = added + 1
            else
                dups = dups + 1
            end
        end
    end

    persistConfig()
    updateWorldDisplayList()
    local summary = string.format("Berhasil input %d World Farm! (Duplikat: %d | Dilewati: %d | Total: %d)",
        added, dups, ignored, #CFG.world_list)
    return added, dups, ignored, summary
end

parseAndValidateStorageBatch = function(rawText, replaceMode)
    if type(rawText) ~= "string" or rawText == "" then
        return 0, 0, 0, "Teks kosong! Silakan tempel daftar world storage terlebih dahulu."
    end
    local cleaned = rawText:gsub("[\"\'%[%]%(%)]", " "):gsub("\t", " ")
    local tokens = {}
    for part in cleaned:gmatch("[^\r\n;,]+") do
        local trimmed = part:gsub("^%s+", ""):gsub("%s+$", "")
        if trimmed ~= "" then table.insert(tokens, trimmed) end
    end
    if #tokens == 0 then
        return 0, 0, 0, "Tidak ada data world storage yang valid ditemukan."
    end

    local candidateList = {}
    local seen = {}
    local dups = 0
    local ignored = 0

    for _, token in ipairs(tokens) do
        local normToken = token:gsub("%s*[:|]%s*", ":")
        local parsed = parseWorldEntryToken(normToken)
        if parsed and parsed.name ~= "" then
            local validName = parsed.name:match("^([%w_]+)$")
            if validName and #validName >= 1 and #validName <= 24 then
                parsed.name = validName:upper()
                if seen[parsed.name] then
                    dups = dups + 1
                else
                    seen[parsed.name] = true
                    table.insert(candidateList, parsed)
                end
            else
                ignored = ignored + 1
            end
        else
            ignored = ignored + 1
        end
    end

    if #candidateList == 0 then
        return 0, dups, ignored, "Tidak ada world storage valid yang dapat ditambahkan."
    end

    local added = 0
    if replaceMode then
        CFG.storage_world_list = {}
        for _, e in ipairs(candidateList) do
            table.insert(CFG.storage_world_list, e)
            added = added + 1
        end
    else
        for _, e in ipairs(candidateList) do
            if not isWorldInList(CFG.storage_world_list, e.name) then
                table.insert(CFG.storage_world_list, e)
                added = added + 1
            else
                dups = dups + 1
            end
        end
    end

    persistConfig()
    updateStorageDisplayList()
    local summary = string.format("Berhasil input %d World Storage! (Duplikat: %d | Dilewati: %d | Total: %d)",
        added, dups, ignored, #CFG.storage_world_list)
    return added, dups, ignored, summary
end

-- ============================================================================
-- 6. FILE BACKUP PATEN (FOLDER DOWNLOAD HP / PC)
-- ============================================================================
local function isSystemWindows()
    return (package.config and package.config:sub(1, 1) == "\\")
end

local function resolveFilePath(rawFileName, defaultName)
    local fn = tostring(rawFileName or defaultName):gsub("^%s+", ""):gsub("%s+$", "")
    if fn == "" then fn = defaultName end
    if not fn:lower():match("%.txt$") then fn = fn .. ".txt" end

    if fn:sub(1, 1) == "/" or fn:match("^%a:[/\\]") then
        local dir = fn:match("^(.*[/\\])") or ""
        local nameOnly = fn:sub(#dir + 1)
        return fn, dir, nameOnly
    end

    local dir = ""
    if isSystemWindows() then
        local userProfile = os.getenv("USERPROFILE")
        if userProfile and userProfile ~= "" then
            dir = userProfile:gsub("\\", "/") .. "/Downloads/"
        else
            dir = ""
        end
    else
        dir = "/storage/emulated/0/Download/"
    end

    if dir ~= "" and not (dir:sub(-1) == "/" or dir:sub(-1) == "\\") then
        dir = dir .. "/"
    end
    return dir .. fn, dir, fn
end

local function checkFileStatus(fullPath)
    if not io or not io.open then return false, "I/O module tidak aktif", 0 end
    local okF, fh = pcall(io.open, fullPath, "r")
    if not okF or not fh then return false, "File belum ada", 0 end
    local count = 0
    for line in fh:lines() do
        local cl = line:gsub("%s+", "")
        if cl ~= "" and not cl:match("^#") and not cl:match("^//") then
            count = count + 1
        end
    end
    fh:close()
    return true, string.format("Ada (%d world)", count), count
end

updateFileInfoDisplayList = function()
    if not editValue then return end
    local fullPath, dir, fn = resolveFilePath(CFG.world_file_name, "boren_plant_worlds.txt")
    local okF, statusMsg = checkFileStatus(fullPath)
    local dirDisplay = (dir ~= "") and dir or "(Folder Download HP)"
    local rows = {
        { "📁 Lokasi Folder", dirDisplay },
        { "📄 Nama File Simpanan", fn },
        { "🔍 Status File", okF and ("`2[ADA] `w" .. statusMsg) or ("`4[BELUM DISIMPAN] `oKlik 'Simpan ke Download'") },
        { "Lokasi Lengkap", fullPath }
    }
    pcall(editValue, "ap_file_info_list", jsonEncode(rows))
end

-- ============================================================================
-- 7. SLEEP, TIMING & CHEAT TOGGLES
-- ============================================================================
local function safeSleep(ms)
    ms = tonumber(ms) or 50
    if ms <= 0 then ms = 10 end
    local fn = sleep or CSleep
    if fn then pcall(fn, ms) end
end

local function applyCheatToggles()
    if not editToggle then return end
    if CFG.use_modfly then
        pcall(editToggle, "ModFly", true)
    end
    if CFG.anti_lava then
        pcall(editToggle, "Anti Lava", true)
        pcall(editToggle, "No Lava", true)
    end
    if CFG.auto_reconnect then
        pcall(editToggle, "Auto Reconnect", true)
        pcall(editToggle, "AutoReconnect", true)
    end
end

-- ============================================================================
-- 8. INTEGRATED HOOK: ON-SEND-PACKET-RAW (ANTI-COLLECT & IGNORE GEMS)
-- ============================================================================
local function onSendPacketRawCollectHook(pkt)
    if type(pkt) ~= "table" then return false end

    -- Packet Type 11 = PACKET_ITEM_ACTIVATE_OBJECT_REQUEST (Collect Object)
    local pktType = tonumber(pkt.type)
    if pktType == 11 then
        local objUID = tonumber(pkt.value) or 0

        -- KASUS 1: Anti-Take Proteksi saat sedang drop / non-collect
        if STATE.anti_take_active then
            return true -- Blokir! Bot tidak mengambil item
        end

        -- KASUS 2: Ignore Gems (Item ID 112 di Growtopia)
        if CFG.ignore_gems then
            local getObjsFn = getObjects or getObjectList
            if getObjsFn then
                local ok, objs = pcall(getObjsFn)
                if ok and type(objs) == "table" then
                    for _, obj in pairs(objs) do
                        if obj and tonumber(obj.id) == objUID then
                            if tonumber(obj.itemid) == 112 then
                                return true -- Blokir gems! Gems tetap di lantai
                            end
                            break
                        end
                    end
                end
            end
        end
    end

    return false
end

local function ensureHooksInstalled()
    if STATE.hooks_installed then return end
    STATE.hooks_installed = true
    if addHook then
        pcall(addHook, onSendPacketRawCollectHook, "onsendpacketraw")
    end
    if applyHook then
        pcall(applyHook)
    end
end

-- ============================================================================
-- 9. WORLD WARPING & SAFE RECONNECT
-- ============================================================================
local function getCurrentWorldSafe()
    local fn = getCurrentWorldName or getWorld
    if not fn then return "" end
    local ok, res = pcall(fn)
    if ok and res then
        if type(res) == "string" then return res:upper() end
        if type(res) == "table" and res.name then return tostring(res.name):upper() end
    end
    return ""
end

local function warpToWorld(worldName, doorID)
    worldName = tostring(worldName or ""):gsub("%s+", ""):upper()
    doorID = tostring(doorID or ""):gsub("%s+", "")
    if worldName == "" or worldName == "EXIT" then return false end

    local curW = getCurrentWorldSafe()
    if curW == worldName and doorID == "" then return true end

    local targetStr = (doorID ~= "") and (worldName .. "|" .. doorID) or worldName
    setStatus("Warping", "Menuju world " .. targetStr)

    for attempt = 1, 3 do
        if not STATE.running then return false end
        if sendPacket then
            pcall(sendPacket, 3, "action|join_request\nname|" .. targetStr .. "\ninvitedWorld|0\n")
        end
        local waited = 0
        local targetWait = CFG.warp_delay or 3500
        while waited < targetWait do
            if not STATE.running then return false end
            safeSleep(200)
            waited = waited + 200
            local nowW = getCurrentWorldSafe()
            if nowW == worldName then
                safeSleep(800)
                applyCheatToggles()
                return true
            end
        end
    end
    return (getCurrentWorldSafe() == worldName)
end

-- ============================================================================
-- 10. TILE MAP, SUPPORT CHECK & MOVEMENT
-- ============================================================================
local function getTileSafe(tx, ty)
    if tx < 0 or tx > 99 or ty < 0 or ty > 59 then
        return { fg = 0, bg = 0, collidable = false, x = tx, y = ty }
    end
    local fn = getTile
    if fn then
        local ok, t = pcall(fn, tx, ty)
        if ok and t then return t end
    end
    return { fg = 0, bg = 0, collidable = false, x = tx, y = ty }
end

local function getPlayerTilePos()
    local fn = getLocal
    if not fn then return 0, 0 end
    local ok, p = pcall(fn)
    if ok and p then
        local px = p.posX or (p.pos and p.pos.x) or 0
        local py = p.posY or (p.pos and p.pos.y) or 0
        return math.floor((px + 10) / 32), math.floor((py + 10) / 32)
    end
    return 0, 0
end

-- Tabel lookup O(1) cepat untuk support platform & tanah / solid blocks
local SUPPORT_ITEMS = {
    [2] = true,   -- Dirt
    [4] = true,   -- Lava
    [8] = true,   -- Bedrock
    [10] = true,  -- Rock
    [14] = true,  -- Cave Dirt
    [20] = true,  -- Wood Block
    [22] = true,  -- Lava Rock
    [24] = true,  -- Mars Rock
    [102] = true, -- Wooden Platform
    [456] = true, [458] = true, [460] = true, [462] = true,
    [464] = true, [466] = true, [468] = true, [470] = true, [472] = true,
    [880] = true, -- Stone Platform
    [954] = true, -- Steel Platform
    [1238] = true,-- Glass Platform
    [2304] = true,-- Cyber Platform
    [3800] = true,-- Bubble Platform
}

local function isSupportTile(t)
    if not t then return false end
    local fg = tonumber(t.fg) or 0
    if fg <= 0 then return false end

    -- 1. Cek tabel lookup O(1) tercepat
    if SUPPORT_ITEMS[fg] then return true end

    -- 2. Properti collidable engine Growlauncher
    if t.collidable == true or t.collidable == 1 then
        return true
    end

    -- 3. Semua block padat & platform Growtopia ID-nya genap (> 0)
    --    Selain pintu (6, 12, 18), lock (202, 204, 206, 242), dan jammer (226)
    if (fg % 2 == 0) then
        if fg ~= 6 and fg ~= 12 and fg ~= 18 and fg ~= 202 and fg ~= 204 and fg ~= 206 and fg ~= 242 and fg ~= 226 then
            return true
        end
    end

    return false
end

local function isPermanentObstacle(t)
    if not t then return false end
    local fg = tonumber(t.fg) or 0
    if fg == 6 or fg == 242 or fg == 202 or fg == 204 or fg == 206 or fg == 226 or fg == 828 or fg == 12 or fg == 18 then
        return true -- Main Door, WL, SL, BL, HL, Jammer, Vent, Door, Dungeon Door
    end
    return false
end

local function getTilePlantStatus(tx, ty)
    if tx < 0 or tx > 99 or ty < 0 or ty > 53 then return "INVALID" end
    local tBelow = getTileSafe(tx, ty + 1)
    if not isSupportTile(tBelow) then return "INVALID" end

    local tAt = getTileSafe(tx, ty)
    if isPermanentObstacle(tAt) then return "INVALID" end

    local fgAt = tonumber(tAt and tAt.fg) or 0
    local s1 = tonumber(CFG.seed_1_id) or 0
    local s2 = tonumber(CFG.seed_2_id) or 0

    if CFG.splice_mode and s2 > 0 and s1 > 0 and s1 ~= s2 then
        if fgAt == 0 then
            return "EMPTY"
        elseif fgAt == s1 then
            return "NEEDS_SPLICE_2"
        elseif fgAt == s2 then
            return "NEEDS_SPLICE_1"
        else
            -- Petak telah tertanam pohon hasil splice (atau block/platform lain)
            return "DONE"
        end
    else
        -- Mode single seed biasa
        if fgAt == 0 then
            return "EMPTY"
        else
            return "DONE"
        end
    end
end

local function isTilePlantable(tx, ty)
    local st = getTilePlantStatus(tx, ty)
    return (st == "EMPTY" or st == "NEEDS_SPLICE_2" or st == "NEEDS_SPLICE_1")
end

local function hasPlantableSpotsInRow(plantY)
    if plantY < 0 or plantY > 53 then return false end
    for x = 0, 99 do
        if isTilePlantable(x, plantY) then
            return true
        end
    end
    return false
end

local function moveSafeTo(tx, ty)
    if not STATE.running then return false end
    tx = math.max(0, math.min(99, math.floor(tx or 0)))
    ty = math.max(0, math.min(53, math.floor(ty or 0)))

    local curPx, curPy = getPlayerTilePos()
    if curPx == tx and curPy == ty then
        return true
    end

    -- Jika target adalah tile padat (misal seed di atas block solid), arahkan ke petak aman terdekat
    local sx, sy = tx, ty
    local t = getTileSafe(tx, ty)
    if t and t.collidable then
        if not getTileSafe(tx, ty - 1).collidable then
            sx, sy = tx, ty - 1
        elseif not getTileSafe(tx - 1, ty).collidable then
            sx, sy = tx - 1, ty
        elseif not getTileSafe(tx + 1, ty).collidable then
            sx, sy = tx + 1, ty
        elseif not getTileSafe(tx, ty + 1).collidable then
            sx, sy = tx, ty + 1
        end
    end

    local pFn = FindPath or findPath
    if pFn then
        -- Titik singgah (waypoint) wajib tile kosong; titik garis lurus sering jatuh di block padat
        local function isFree(x, y)
            if x < 0 or x > 99 or y < 0 or y > 53 then return false end
            local tt = getTileSafe(x, y)
            return not (tt and tt.collidable)
        end
        local function nearestFree(cx, cy)
            for r = 0, 3 do
                for oy = -r, r do
                    for ox = -r, r do
                        if math.max(math.abs(ox), math.abs(oy)) == r and isFree(cx + ox, cy + oy) then
                            return cx + ox, cy + oy
                        end
                    end
                end
            end
            return nil, nil
        end

        local CHUNK_LIMIT = 5 -- hop pendek (5 block) agar gerakan natural & aman saat lag
        local stuck = 0
        while STATE.running do
            local cx, cy = getPlayerTilePos()
            if not cx or not cy then safeSleep(100); stuck = stuck + 1; if stuck >= 3 then break end
            else
                if math.abs(cx - sx) <= 1 and math.abs(cy - sy) <= 1 then
                    safeSleep(CFG.step_delay or 40)
                    return true
                end
                local dx, dy = sx - cx, sy - cy
                local dist = math.max(math.abs(dx), math.abs(dy))
                local wx, wy = sx, sy
                local direct = (dist <= CHUNK_LIMIT) or stuck >= 1
                if not direct then
                    local r = CHUNK_LIMIT / dist
                    local ix = math.max(0, math.min(99, math.floor(cx + dx * r + 0.5)))
                    local iy = math.max(0, math.min(53, math.floor(cy + dy * r + 0.5)))
                    wx, wy = nearestFree(ix, iy)
                    if not wx then wx, wy, direct = sx, sy, true end
                end

                -- TELEPORT per hop dengan jeda SEBELUM teleport (jitter ±20% agar ritme tidak robotik)
                local baseDelay = tonumber(CFG.step_delay) or 110
                safeSleep(math.floor(math.max(100, baseDelay) * (0.8 + math.random() * 0.4)))
                if not STATE.running then break end
                pcall(pFn, wx, wy)
                local stepDist = math.max(math.abs(wx - cx), math.abs(wy - cy))
                local maxWait = math.max(120, math.min(1500, stepDist * 60))
                local waited = 0
                while waited < maxWait and STATE.running do
                    local npx, npy = getPlayerTilePos()
                    if npx and npy and math.abs(npx - wx) <= 1 and math.abs(npy - wy) <= 1 then break end
                    safeSleep(30)
                    waited = waited + 30
                end

                local nx, ny = getPlayerTilePos()
                if nx and ny and math.abs(nx - sx) <= 1 and math.abs(ny - sy) <= 1 then
                    safeSleep(math.max(150, baseDelay)) -- jeda setelah teleport terakhir sebelum aksi
                    return true
                end
                if nx == cx and ny == cy then
                    stuck = stuck + 1 -- tidak bergerak: coba langsung ke target, lalu menyerah
                    if direct and stuck >= 2 then break end
                else
                    stuck = 0
                end
                -- Jeda SETELAH tiap teleport mengikuti slider "Kecepatan Melangkah" (min 200ms, jitter ±20%)
                safeSleep(math.floor(math.max(200, baseDelay * 2) * (0.8 + math.random() * 0.4)))
            end
        end
    end

    -- Fallback Packet 0 jika FindPath terhambat udara / ModFly
    local okP, p = pcall(getLocal)
    if okP and p and sendPacketRaw then
        local state = (curPx and curPx > sx) and 48 or 32
        pcall(sendPacketRaw, false, {
            type  = 0,
            x     = sx * 32,
            y     = sy * 32,
            state = state,
        })
        safeSleep(CFG.step_delay or 50)
        return true
    end
    return false
end

local function waitForWorldLoaded(timeoutMs)
    timeoutMs = timeoutMs or 3000
    local elapsed = 0
    while elapsed < timeoutMs do
        local tMid = getTileSafe(50, 30)
        local tDoor = getTileSafe(0, 0)
        local tBot = getTileSafe(50, 54)
        if (tMid.fg and tMid.fg > 0) or (tDoor.fg and tDoor.fg > 0) or (tBot.fg and tBot.fg > 0)
           or (tMid.bg and tMid.bg > 0) or (tDoor.bg and tDoor.bg > 0) then
            return true
        end
        safeSleep(150)
        elapsed = elapsed + 150
    end
    return true
end

-- ============================================================================
-- 11. DETEKSI BARIS PLATFORM WORLD FARM (DARI PALING ATAS KE BAWAH)
-- ============================================================================
local function detectPlantableRows()
    local rows = {}
    for y = 0, 53 do
        if hasPlantableSpotsInRow(y) then
            table.insert(rows, y)
        end
    end
    return rows
end
_G.__detectPlantableRows = detectPlantableRows

-- ============================================================================
-- 12. PLANTING ENGINE & SPLICE EXECUTION
-- ============================================================================
local function sendPlantPacket(tx, ty, itemID)
    if not sendPacketRaw then return false end
    itemID = tonumber(itemID) or 0
    if itemID <= 0 then return false end

    local okP, p = pcall(getLocal)
    local px = (okP and p and (p.posX or (p.pos and p.pos.x))) or (tx * 32)
    local py = (okP and p and (p.posY or (p.pos and p.pos.y))) or (ty * 32)
    local state = (px > (tx * 32)) and 48 or 32

    local ok = pcall(sendPacketRaw, false, {
        type  = 3,
        value = itemID,
        px    = tx,
        py    = ty,
        x     = px,
        y     = py,
        state = state,
    })
    return ok
end

local function plantSingleSpot(tx, ty)
    if not STATE.running then return false end
    local st = getTilePlantStatus(tx, ty)
    if st == "DONE" or st == "INVALID" then return true end

    local s1 = CFG.seed_1_id
    local s2 = CFG.seed_2_id

    local curPx, curPy = getPlayerTilePos()
    if math.abs(curPx - tx) > 1 or math.abs(curPy - ty) > 1 then
        moveSafeTo(tx, ty)
    end

    local isSplice = (CFG.splice_mode and s2 and s2 > 0 and s1 > 0 and s1 ~= s2)

    if not isSplice then
        if st == "EMPTY" then
            sendPlantPacket(tx, ty, s1)
            safeSleep(math.max(40, CFG.plant_delay))
        end
        return true
    end

    if st == "NEEDS_SPLICE_2" then
        sendPlantPacket(tx, ty, s2)
        safeSleep(math.max(60, CFG.splice_delay))
    elseif st == "NEEDS_SPLICE_1" then
        sendPlantPacket(tx, ty, s1)
        safeSleep(math.max(60, CFG.splice_delay))
    elseif st == "EMPTY" then
        sendPlantPacket(tx, ty, s1)
        safeSleep(math.max(80, CFG.splice_delay))
        sendPlantPacket(tx, ty, s2)
        safeSleep(math.max(50, CFG.plant_delay))
    end

    return true
end

local function plantTileSection(spotList, plantY)
    if not STATE.running or not spotList or #spotList == 0 then return true end

    local s1 = CFG.seed_1_id
    local s2 = CFG.seed_2_id
    local isSplice = (CFG.splice_mode and s2 and s2 > 0 and s1 > 0 and s1 ~= s2)

    for attempt = 1, 3 do
        if not STATE.running then break end
        while STATE.paused do safeSleep(500) if not STATE.running then break end end

        local anyAction = false

        if not isSplice then
            for _, sx in ipairs(spotList) do
                if isTilePlantable(sx, plantY) then
                    sendPlantPacket(sx, plantY, s1)
                    safeSleep(math.max(30, CFG.plant_delay))
                    anyAction = true
                end
            end
        else
            -- Mode Splice: Tahap 1 - Selesaikan petak yang sebelumnya tertinggal/hanya ada 1 seed
            for _, sx in ipairs(spotList) do
                local st = getTilePlantStatus(sx, plantY)
                if st == "NEEDS_SPLICE_2" then
                    sendPlantPacket(sx, plantY, s2)
                    safeSleep(math.max(35, CFG.plant_delay))
                    anyAction = true
                elseif st == "NEEDS_SPLICE_1" then
                    sendPlantPacket(sx, plantY, s1)
                    safeSleep(math.max(35, CFG.plant_delay))
                    anyAction = true
                end
            end

            -- Mode Splice: Tahap 2 - Tanam Seed 1 ke semua petak yang masih EMPTY dalam seksi ini
            local newlyPlantedS1 = {}
            for _, sx in ipairs(spotList) do
                local st = getTilePlantStatus(sx, plantY)
                if st == "EMPTY" then
                    sendPlantPacket(sx, plantY, s1)
                    table.insert(newlyPlantedS1, sx)
                    safeSleep(math.max(35, CFG.plant_delay))
                    anyAction = true
                end
            end

            -- Beri jeda pemrosesan server agar Seed 1 terdaftar sebelum ditimpa Seed 2
            if #newlyPlantedS1 > 0 then
                safeSleep(math.max(80, CFG.splice_delay))
                -- Mode Splice: Tahap 3 - Timpa dengan Seed 2 ke seluruh petak tadi
                for _, sx in ipairs(newlyPlantedS1) do
                    sendPlantPacket(sx, plantY, s2)
                    safeSleep(math.max(35, CFG.plant_delay))
                end
            end
        end

        if not anyAction then break end

        safeSleep(math.max(40, isSplice and CFG.splice_delay or CFG.plant_delay))

        local stillNeed = false
        for _, sx in ipairs(spotList) do
            if isTilePlantable(sx, plantY) then
                stillNeed = true
                break
            end
        end
        if not stillNeed then break end
    end

    return true
end

-- ============================================================================
-- 13. SEED STORAGE RESTOCK & AUTO-SKIP EMPTY STORAGE
-- ============================================================================
local function collectFloatingSeedsInStorage(targetSeedID, targetAmount)
    local getObjsFn = getObjects or getObjectList
    if not getObjsFn then return 0 end

    targetSeedID = math.floor(tonumber(targetSeedID) or 0)
    if targetSeedID <= 0 then return 0 end

    local curBP = getInvCount(targetSeedID)
    local needed = math.max(0, targetAmount - curBP)
    if needed <= 0 then return 0 end

    local collected = 0
    local ok, objs = pcall(getObjsFn)
    if not ok or type(objs) ~= "table" then return 0 end

    for _, obj in pairs(objs) do
        if not STATE.running then break end
        local objItemID = tonumber(obj and (obj.itemid or obj.itemId or obj.item_id or 0)) or 0
        if obj and obj.id and objItemID == targetSeedID then
            local rawX = (obj.pos and obj.pos.x) or obj.posX or obj.x or 0
            local rawY = (obj.pos and obj.pos.y) or obj.posY or obj.y or 0
            local ox = math.floor((rawX + 10) / 32)
            local oy = math.floor((rawY + 10) / 32)

            addLog(string.format("[Storage] Menghampiri seed ID %d di tile (%d, %d)...", targetSeedID, ox, oy))
            moveSafeTo(ox, oy)
            safeSleep(100)

            -- Ambil objek via packet 11
            if sendPacketRaw then
                pcall(sendPacketRaw, false, {
                    type  = 11,
                    value = obj.id,
                    x     = rawX,
                    y     = rawY,
                })
            end
            safeSleep(150)
            collected = collected + (tonumber(obj.amount) or 1)
            syncInventoryCache()
            if getInvCount(targetSeedID) >= targetAmount then break end
        end
    end
    return collected
end

local function restockFromStorage()
    if #CFG.storage_world_list == 0 then
        setStatus("Seed di Tas Habis", "Seed di tas telah habis & tidak ada World Storage!")
        addLog("[Peringatan] Seed di tas habis dan tidak ada daftar world storage. Bot dijeda.")
        if sendNotification then pcall(sendNotification, "Seed di tas habis dan tidak ada World Storage! Bot dijeda.") end
        STATE.paused = true
        return false
    end

    local farmW = STATE.active_farm_world
    local farmD = STATE.active_farm_door
    local curPx, curPy = getPlayerTilePos()
    STATE.saved_farm_x = curPx
    STATE.saved_farm_y = curPy

    setStatus("Menuju Storage", "Mengambil stok seed ke gudang...")

    local totalStorages = #CFG.storage_world_list
    local checkedCount = 0
    local successRestock = false

    while checkedCount < totalStorages do
        if not STATE.running then return false end
        if STATE.active_storage_idx > totalStorages then
            STATE.active_storage_idx = 1
        end

        local storEntry = CFG.storage_world_list[STATE.active_storage_idx]
        local storName = storEntry.name
        local storDoor = storEntry.door or ""

        setStatus("Storage Check", string.format("Warp ke Storage: %s (%d/%d)", storName, STATE.active_storage_idx, totalStorages))
        local okWarp = warpToWorld(storName, storDoor)
        if okWarp then
            safeSleep(800)
            -- Tunggu hingga objek world termuat di memori
            for _ = 1, 8 do
                local getObjsFn = getObjects or getObjectList
                local objs = getObjsFn and getObjsFn()
                if objs and #objs > 0 then break end
                safeSleep(150)
            end
            syncInventoryCache()
            if editToggle then
                pcall(editToggle, "Auto Collect", true)
                pcall(editToggle, "Anti Collect", false)
            end

            -- Ambil Seed 1
            local c1 = collectFloatingSeedsInStorage(CFG.seed_1_id, CFG.target_seed_bp)
            -- Jika Splice, ambil juga Seed 2
            local c2 = 0
            if CFG.splice_mode then
                c2 = collectFloatingSeedsInStorage(CFG.seed_2_id, CFG.target_seed_bp)
            end

            -- Tunggu toleransi sinkronisasi paket inventori dari server
            local bp1 = getInvCount(CFG.seed_1_id)
            local bp2 = CFG.splice_mode and getInvCount(CFG.seed_2_id) or 999
            local hasSeedNow = (not CFG.splice_mode and (bp1 > 0 or c1 > 0))
                            or (CFG.splice_mode and (bp1 > 0 or c1 > 0) and (bp2 > 0 or c2 > 0))

            if not hasSeedNow then
                for _ = 1, 5 do
                    safeSleep(200)
                    syncInventoryCache()
                    bp1 = getInvCount(CFG.seed_1_id)
                    bp2 = CFG.splice_mode and getInvCount(CFG.seed_2_id) or 999
                    if (not CFG.splice_mode and bp1 > 0) or (CFG.splice_mode and bp1 > 0 and bp2 > 0) then
                        hasSeedNow = true
                        break
                    end
                end
            else
                safeSleep(300)
                syncInventoryCache()
                bp1 = getInvCount(CFG.seed_1_id)
                if CFG.splice_mode then bp2 = getInvCount(CFG.seed_2_id) end
            end

            local canPlantNow = (not CFG.splice_mode and bp1 > 0)
                             or (CFG.splice_mode and bp1 > 0 and bp2 > 0)

            if canPlantNow then
                addLog(string.format("[Storage] Sukses ambil seed di %s (Seed 1: %d | Seed 2: %d). Kembali ke farm untuk menanam...", storName, bp1, bp2))
                successRestock = true
                -- PENTING: Jangan langsung skip ke storage berikutnya jika tas berhasil diisi seed!
                -- Biarkan bot kembali ke farm menanam stok ini.
                -- Jika stok di storage ini benar-benar habis, bot baru akan konfirmasi dan skip saat balik lagi nanti dengan tas kosong!
                break
            else
                if CFG.splice_mode and bp1 > 0 and bp2 <= 0 then
                    addLog(string.format("[Storage] Seed 1 ada di %s (%d), tetapi Seed 2 kosong. Mencari Seed 2 di storage berikutnya...", storName, bp1))
                else
                    addLog(string.format("[Storage] Stok di %s habis/kosong (0 seed didapat). Cek storage berikutnya...", storName))
                    if sendNotification then
                        pcall(sendNotification, string.format("Storage %s kosong! Skip ke berikutnya...", storName))
                    end
                end
                STATE.active_storage_idx = STATE.active_storage_idx + 1
                checkedCount = checkedCount + 1
            end
        else
            addLog("[Storage] Gagal warp ke " .. storName .. ", mencoba storage berikutnya...")
            STATE.active_storage_idx = STATE.active_storage_idx + 1
            checkedCount = checkedCount + 1
        end
    end

    -- Validasi akhir: jika di tas ada seed yang bisa ditanam (misalnya dari storage sebelumnya)
    local finalBp1 = getInvCount(CFG.seed_1_id)
    local finalBp2 = CFG.splice_mode and getInvCount(CFG.seed_2_id) or 999
    if (not CFG.splice_mode and finalBp1 > 0) or (CFG.splice_mode and finalBp1 > 0 and finalBp2 > 0) then
        successRestock = true
    end

    if not successRestock then
        setStatus("Semua Storage Habis", "Semua world storage kehabisan stok seed!")
        addLog("[Peringatan] Semua world storage telah diperiksa dan stok seed benar-benar habis. Bot dijeda.")
        if sendNotification then
            pcall(sendNotification, "PERINGATAN: Semua World Storage kehabisan seed! Bot dijeda.")
        end
        STATE.paused = true
        return false
    end

    -- Kembali ke World Farm
    setStatus("Kembali ke Farm", "Menuju world " .. farmW)
    local okBack = warpToWorld(farmW, farmD)
    if okBack and STATE.saved_farm_x and STATE.saved_farm_y then
        safeSleep(800)
        moveSafeTo(STATE.saved_farm_x, STATE.saved_farm_y)
    end
    return true
end

-- ============================================================================
-- 14. ALUR UTAMA TANAM PER BARIS & WORLD
-- ============================================================================
local function countPlantableSpotsInWorld()
    local cnt = 0
    for y = 0, 53 do
        for x = 0, 99 do
            if isTilePlantable(x, y) then
                cnt = cnt + 1
            end
        end
    end
    return cnt
end

local function hasEnoughSeedInBackpack()
    local s1 = CFG.seed_1_id
    local s2 = CFG.seed_2_id

    local bp1 = getInvCount(s1)
    local bp2 = CFG.splice_mode and getInvCount(s2) or 999

    -- VALIDASI 1: Jika di tas masih ada seed (bp1 > 0 dan jika splice bp2 > 0),
    -- bot WAJIB menanam sampai habis (0 di tas). Jangan pernah ambil seed ke storage saat tas belum habis!
    if bp1 > 0 and (not CFG.splice_mode or bp2 > 0) then
        return true
    end

    -- VALIDASI 2: Jika terdeteksi 0, double-check dengan sync inventory untuk mencegah lag pembacaan paket
    syncInventoryCache()
    safeSleep(50)
    bp1 = getInvCount(s1)
    bp2 = CFG.splice_mode and getInvCount(s2) or 999
    if bp1 > 0 and (not CFG.splice_mode or bp2 > 0) then
        return true
    end

    -- Tas benar-benar 0 (habis ter-plant semua)
    return false
end

local function executePlantRow(plantY)
    if CFG.plant_mode == "3zigzag" then
        -- Mode Plant 3 Zig-Zag ala Lucifer (Kiri, Tengah, Kanan lalu melangkah 3 petak)
        -- Selalu bergerak dari Kiri ke Kanan (X = 0 s/d 99)
        local standX = 1
        while standX <= 97 do
            if not STATE.running then break end
            while STATE.paused do safeSleep(500) if not STATE.running then break end end

            local sLeft   = standX - 1
            local sCenter = standX
            local sRight  = standX + 1

            local needPlant = (sLeft >= 0 and isTilePlantable(sLeft, plantY))
                           or isTilePlantable(sCenter, plantY)
                           or (sRight <= 99 and isTilePlantable(sRight, plantY))

            if needPlant then
                -- VALIDASI 3: Cek stok tas HANYA saat petak benar-benar butuh tanam!
                if not hasEnoughSeedInBackpack() then
                    local remHoles = countPlantableSpotsInWorld()
                    if remHoles == 0 then
                        -- World sudah ter-plant semua! Tidak perlu restock lagi!
                        return true
                    end
                    local okRestock = restockFromStorage()
                    if not okRestock then return false end
                end

                moveSafeTo(standX, plantY)

                local sectionSpots = {}
                if sLeft >= 0 then table.insert(sectionSpots, sLeft) end
                table.insert(sectionSpots, sCenter)
                if sRight <= 99 then table.insert(sectionSpots, sRight) end

                plantTileSection(sectionSpots, plantY)
            end

            standX = standX + 3
        end

        -- Tangani ujung kanan platform (petak 98 dan 99 agar tidak bolong di ujung)
        if isTilePlantable(98, plantY) or isTilePlantable(99, plantY) then
            if not hasEnoughSeedInBackpack() then
                local remHoles = countPlantableSpotsInWorld()
                if remHoles == 0 then return true end
                local okRestock = restockFromStorage()
                if not okRestock then return false end
            end

            moveSafeTo(98, plantY)
            plantTileSection({ 98, 99 }, plantY)
        end

    else
        -- Mode 1 by 1 (Tanam per petak demi petak penuh dari ujung kiri ke kanan 0 s/d 99)
        for curX = 0, 99 do
            if not STATE.running then break end
            while STATE.paused do safeSleep(500) if not STATE.running then break end end

            if isTilePlantable(curX, plantY) then
                if not hasEnoughSeedInBackpack() then
                    local remHoles = countPlantableSpotsInWorld()
                    if remHoles == 0 then return true end
                    local okRestock = restockFromStorage()
                    if not okRestock then return false end
                end

                moveSafeTo(curX, plantY)
                plantTileSection({ curX }, plantY)
            end
        end
    end

    -- =========================================================================
    -- ROW SWEEPER: Deteksi & tambal otomatis setiap petak yang terlewat di baris ini
    -- =========================================================================
    if hasPlantableSpotsInRow(plantY) then
        local missedSpots = {}
        for x = 0, 99 do
            if isTilePlantable(x, plantY) then
                table.insert(missedSpots, x)
            end
        end

        if #missedSpots > 0 then
            addLog(string.format("[Tambal Baris Y=%d] Terdeteksi %d petak belum selesai/tercampur, melakukan tambal...", plantY, #missedSpots))
            for _, mx in ipairs(missedSpots) do
                if not STATE.running then break end
                while STATE.paused do safeSleep(500) if not STATE.running then break end end

                if isTilePlantable(mx, plantY) then
                    if not hasEnoughSeedInBackpack() then
                        local remHoles = countPlantableSpotsInWorld()
                        if remHoles == 0 then return true end
                        local okRestock = restockFromStorage()
                        if not okRestock then return false end
                    end

                    moveSafeTo(mx, plantY)
                    plantTileSection({ mx }, plantY)
                end
            end
        end
    end

    return true
end

local function plantEntireWorld()
    local curW = getCurrentWorldSafe()
    setStatus("Menanam", "Memulai proses tanam dari baris paling atas di world " .. curW)
    addLog(string.format("Memulai tanam world %s (Urut dari baris paling atas Y=0 s/d Y=53, kiri ke kanan)", curW))

    -- Pindai dan kumpulkan baris yang memiliki petak kosong berlantai (Y=0 s/d Y=53)
    local activeRows = {}
    for y = 0, 53 do
        if hasPlantableSpotsInRow(y) then
            table.insert(activeRows, y)
        end
    end

    if #activeRows == 0 then
        setStatus("World Penuh / Selesai", "Tidak ada petak kosong yang dapat ditanam di world " .. curW)
        addLog("[Info] World " .. curW .. " tidak memiliki petak kosong berlantai. Ditandai selesai.")
        return true
    end

    addLog(string.format("Terdeteksi %d baris tanam di %s (Mulai dari baris paling atas: Y=%d)",
        #activeRows, curW, activeRows[1]))

    for idx, plantY in ipairs(activeRows) do
        if not STATE.running then break end
        while STATE.paused do safeSleep(500) if not STATE.running then break end end

        setStatus("Menanam", string.format("Baris Y=%d (%d/%d) di %s", plantY, idx, #activeRows, curW))
        local okRow = executePlantRow(plantY)
        if not okRow then return false end
    end

    -- =========================================================================
    -- WORLD SWEEPER: Validasi ulang seluruh baris (Y=0 s/d 53) untuk memastikan 0 BOLONG
    -- =========================================================================
    local maxWorldSweeps = 2
    for sweepCycle = 1, maxWorldSweeps do
        if not STATE.running then break end
        while STATE.paused do safeSleep(500) if not STATE.running then break end end

        local remainingRows = {}
        local totalRemainingHoles = 0

        for y = 0, 53 do
            local holesInY = 0
            for x = 0, 99 do
                if isTilePlantable(x, y) then
                    holesInY = holesInY + 1
                end
            end
            if holesInY > 0 then
                table.insert(remainingRows, y)
                totalRemainingHoles = totalRemainingHoles + holesInY
            end
        end

        if totalRemainingHoles == 0 then
            break -- World 100% tuntas tanpa ada satu pun petak bolong!
        end

        addLog(string.format("[Sweeper World #%d] Masih tersisa %d petak bolong di %d baris. Menyapu dan menambal ulang...",
            sweepCycle, totalRemainingHoles, #remainingRows))
        setStatus("Menambal Sisa", string.format("Sweep #%d: %d petak di %s", sweepCycle, totalRemainingHoles, curW))

        for _, sweepY in ipairs(remainingRows) do
            if not STATE.running then break end
            while STATE.paused do safeSleep(500) if not STATE.running then break end end
            local okRow = executePlantRow(sweepY)
            if not okRow then return false end
        end
    end

    -- Verifikasi Akhir Jumlah Petak Kosong
    local finalHoles = 0
    for y = 0, 53 do
        for x = 0, 99 do
            if isTilePlantable(x, y) then
                finalHoles = finalHoles + 1
            end
        end
    end

    if finalHoles == 0 then
        addLog(string.format("World Farm %s SELESAI ditanam! (100%% Penuh, 0 Bolong)", curW))
        setStatus("World Selesai", string.format("World %s 100%% tuntas tertanam!", curW))
    else
        addLog(string.format("[Peringatan] World %s masih menyisakan %d petak kosong (kehabisan seed).", curW, finalHoles))
        setStatus("Selesai Sebagian", string.format("Tersisa %d petak kosong di %s", finalHoles, curW))
    end

    return true
end

-- ============================================================================
-- 15. MAIN BOT COROUTINE
-- ============================================================================
local function autoPlantMainLoop()
    STATE.running = true
    STATE.paused  = false
    ensureHooksInstalled()
    applyCheatToggles()

    if STATE.buf_seed_1_id and STATE.buf_seed_1_id > 0 then
        CFG.seed_1_id = ensureSeedID(STATE.buf_seed_1_id)
        CFG.seed_1_name = resolveSeedName(CFG.seed_1_id)
        STATE.buf_seed_1_id = CFG.seed_1_id
    end
    if CFG.splice_mode and STATE.buf_seed_2_id and STATE.buf_seed_2_id > 0 then
        CFG.seed_2_id = ensureSeedID(STATE.buf_seed_2_id)
        CFG.seed_2_name = resolveSeedName(CFG.seed_2_id)
        STATE.buf_seed_2_id = CFG.seed_2_id
    end
    if CFG.splice_mode and CFG.seed_1_id > 0 and CFG.seed_1_id == CFG.seed_2_id then
        addLog("[Peringatan] Seed 1 & Seed 2 bernilai sama (" .. CFG.seed_1_id .. "). Mode Splice membutuhkan 2 jenis seed berbeda!")
        if sendNotification then pcall(sendNotification, "Peringatan: Seed 1 & 2 tidak boleh sama saat Splice!") end
    end
    persistConfig()
    updateSeedStatusDisplay()
    updatePowerStatusList()

    if #CFG.world_list == 0 then
        local curW = getCurrentWorldSafe()
        if curW ~= "" and curW ~= "EXIT" then
            addLog("[Info] List world kosong, otomatis menggunakan world saat ini: " .. curW)
            table.insert(CFG.world_list, { name = curW, door = "", done = false, status = "ANTRE" })
            updateWorldDisplayList()
        else
            setStatus("List World Kosong", "Silakan tambahkan world farm terlebih dahulu di menu!")
            if sendNotification then pcall(sendNotification, "List World Farm kosong!") end
            STATE.running = false
            if editToggle then pcall(editToggle, "ap_run_power", false) end
            return
        end
    end

    if STATE.active_world_idx > #CFG.world_list then
        STATE.active_world_idx = 1
    end

    setStatus("Memulai Bot", "Auto Plant & Splice by Boren Store aktif...")

    while STATE.running and STATE.active_world_idx <= #CFG.world_list do
        local entry = CFG.world_list[STATE.active_world_idx]
        if not entry.done then
            entry.status = "PROSES"
            STATE.active_farm_world = entry.name
            STATE.active_farm_door  = entry.door or ""
            updateWorldDisplayList()

            setStatus("Masuk World Farm", "Menuju " .. entry.name)
            local arrived = warpToWorld(entry.name, entry.door)
            if arrived then
                safeSleep(800)
                waitForWorldLoaded(3000)
                syncInventoryCache()


                -- Validasi awal: Cek apakah world ini memang masih memiliki petak kosong berlantai
                local initialHoles = countPlantableSpotsInWorld()
                if initialHoles == 0 then
                    addLog(string.format("[Info] World %s sudah ter-plant penuh (0 petak kosong tersisa). Selesai!", entry.name))
                    entry.done = true
                    entry.status = "DONE"
                    persistConfig()
                    updateWorldDisplayList()
                else
                    -- Cek stok awal HANYA jika world masih membutuhkan penanaman
                    if not hasEnoughSeedInBackpack() then
                        local okR = restockFromStorage()
                        if not okR then break end
                    end

                    local okPlant = plantEntireWorld()
                    if okPlant and STATE.running then
                        entry.done = true
                        entry.status = "DONE"
                        persistConfig()
                        updateWorldDisplayList()
                        addLog(string.format("World Farm %s SELESAI ditanam!", entry.name))
                        if sendNotification then
                            pcall(sendNotification, string.format("Farm %s selesai! Menuju world berikutnya...", entry.name))
                        end
                    else
                        if STATE.paused or not STATE.running then
                            break
                        end
                    end
                end
            else
                addLog("Gagal masuk ke world " .. entry.name .. ", melewati...")
            end
        end
        STATE.active_world_idx = STATE.active_world_idx + 1
    end

    if STATE.paused then
        -- Pertahankan status pause agar user tahu kenapa bot berhenti (misal: Seed Habis)
        STATE.running = false
        if editToggle then pcall(editToggle, "ap_run_power", false) end
        updateWorldDisplayList()
        return
    end

    if STATE.running then
        setStatus("Selesai Semua World", "Seluruh antrean world farm telah selesai ditanam!")
        if sendNotification then pcall(sendNotification, "Semua world farm di list selesai ditanam!") end
    else
        setStatus("Berhenti", "Auto Plant berhenti.")
    end

    STATE.running = false
    if editToggle then pcall(editToggle, "ap_run_power", false) end
    updateWorldDisplayList()
end

local function startBot()
    if STATE.running then return end
    if runCoroutine then
        pcall(runCoroutine, autoPlantMainLoop)
    else
        local co = coroutine.create(autoPlantMainLoop)
        coroutine.resume(co)
    end
end

local function stopBot()
    STATE.running = false
    STATE.paused  = false
    setStatus("Berhenti", "Bot dimatikan pengguna.")
    if editToggle then pcall(editToggle, "ap_run_power", false) end
end

-- ============================================================================
-- 16. DIALOG MANAGEMENT (UNIFIED MANAGER: COPY, QUICK PASTE, EDIT & HAPUS)
-- ============================================================================
local function safeSendRawDialog(dText)
    if not dText or dText == "" then return false end
    if growtopia and type(growtopia.sendDialog) == "function" then
        local ok = pcall(growtopia.sendDialog, dText)
        if ok then return true end
    end
    if sendVariant then
        local ok = pcall(sendVariant, { v1 = "OnDialogRequest", v2 = dText })
        if ok then return true end
    end
    if sendDialog then
        pcall(sendDialog, dText)
        return true
    end
    return false
end

openWorldListManagerDialog = function(fmt)
    fmt = fmt or "colon"

    local copyLines = {}
    for _, e in ipairs(CFG.world_list) do
        local door = e.door or ""
        if fmt == "colon" then
            table.insert(copyLines, (door ~= "") and (e.name .. ":" .. door) or e.name)
        elseif fmt == "pipe" then
            table.insert(copyLines, (door ~= "") and (e.name .. "|" .. door) or e.name)
        else
            table.insert(copyLines, e.name)
        end
    end
    local rawCopy = table.concat(copyLines, "\n")
    local rawBoxText = table.concat(copyLines, ", ")
    if ImGui and ImGui.SetClipboardText and rawCopy ~= "" then
        pcall(ImGui.SetClipboardText, rawCopy)
    end

    local dLines = {
        "set_default_color|`o",
        "add_quick_exit|",
        string.format("add_label_with_icon|big|`wKelola, Salin & Tempel World (%d)``|left|2|", #CFG.world_list),
        "add_textbox|`oDi sini Anda bisa salin antrean, tempel banyak world baru, dan edit/hapus world.|left|",
        "add_spacer|small|",

        -- Bagian 1: Salin Semua World
        "add_textbox|`2[1. Salin Semua World Farm ke Clipboard]|left|",
        string.format("add_text_input|boren_wcopy_box|Salin Antrean|%s|9999|", rawBoxText),
        "add_button|boren_btn_wfmt_colon|Format Titik Dua (:)|noflags|0|0|",
        "add_button|boren_btn_wfmt_pipe|Format Garis (|)|noflags|0|0|",
        "add_button|boren_btn_wfmt_name|Hanya Nama World|noflags|0|0|",
        "add_spacer|small|",

        -- Bagian 2: Tempel Banyak / Tambah World
        "add_textbox|`2[2. Tempel / Tambah World ke Antrean]|left|",
        "add_textbox|`eTempel 1 atau banyak world (Format: WORLD:ID / WORLD|ID / WORLD). Bebas koma, spasi, enter.|left|",
        "add_text_input|boren_wpaste_raw|Tempel World di sini:||9999|",
        "add_checkbox|boren_wpaste_replace|Ganti semua antrean (Replace)|0|",
        "add_button|boren_submit_wpaste|`2+ Tempel / Tambah ke Antrean|noflags|0|0|",
        "add_spacer|small|",

        -- Bagian 3: Daftar World & Aksi Edit/Hapus
        string.format("add_textbox|`2[3. Daftar Antrean Saat Ini (%d World)]|left|", #CFG.world_list)
    }

    if #CFG.world_list == 0 then
        table.insert(dLines, "add_textbox|`4(Antrean World Farm masih kosong. Silakan tempel di atas!)|left|")
    else
        for i, e in ipairs(CFG.world_list) do
            local st = getWorldEntryStatusTag(e)
            local d = (e.door and e.door ~= "") and e.door or "-"
            table.insert(dLines, string.format("add_textbox|`w%d. `9%s `o[Door: %s] `2[%s]|left|", i, e.name, d, st))
            table.insert(dLines, string.format("add_button|boren_wedit_%d|Edit|noflags|0|0|", i))
            table.insert(dLines, string.format("add_button|boren_whapus_%d|Hapus|noflags|0|0|", i))
            table.insert(dLines, "add_spacer|small|")
        end
    end

    table.insert(dLines, "end_dialog|boren_plant_world_mgr|Tutup||")
    return safeSendRawDialog(table.concat(dLines, "\n"))
end

openStorageListManagerDialog = function(fmt)
    fmt = fmt or "colon"

    local copyLines = {}
    for _, e in ipairs(CFG.storage_world_list) do
        local door = e.door or ""
        if fmt == "colon" then
            table.insert(copyLines, (door ~= "") and (e.name .. ":" .. door) or e.name)
        elseif fmt == "pipe" then
            table.insert(copyLines, (door ~= "") and (e.name .. "|" .. door) or e.name)
        else
            table.insert(copyLines, e.name)
        end
    end
    local rawCopy = table.concat(copyLines, "\n")
    local rawBoxText = table.concat(copyLines, ", ")
    if ImGui and ImGui.SetClipboardText and rawCopy ~= "" then
        pcall(ImGui.SetClipboardText, rawCopy)
    end

    local dLines = {
        "set_default_color|`o",
        "add_quick_exit|",
        string.format("add_label_with_icon|big|`wKelola, Salin & Tempel Gudang (%d)``|left|242|", #CFG.storage_world_list),
        "add_textbox|`oDi sini Anda bisa salin daftar gudang, tempel banyak gudang baru, dan edit/hapus gudang.|left|",
        "add_spacer|small|",

        -- Bagian 1: Salin Semua Gudang
        "add_textbox|`2[1. Salin Semua Gudang Seed ke Clipboard]|left|",
        string.format("add_text_input|boren_stcopy_box|Salin Gudang|%s|9999|", rawBoxText),
        "add_button|boren_btn_stfmt_colon|Format Titik Dua (:)|noflags|0|0|",
        "add_button|boren_btn_stfmt_pipe|Format Garis (|)|noflags|0|0|",
        "add_button|boren_btn_stfmt_name|Hanya Nama Gudang|noflags|0|0|",
        "add_spacer|small|",

        -- Bagian 2: Tempel Banyak / Tambah Gudang
        "add_textbox|`2[2. Tempel / Tambah Gudang Seed ke Antrean]|left|",
        "add_textbox|`eTempel 1 atau banyak gudang (Format: WORLD:ID / WORLD|ID / WORLD). Bebas koma, spasi, enter.|left|",
        "add_text_input|boren_stpaste_raw|Tempel Gudang di sini:||9999|",
        "add_checkbox|boren_stpaste_replace|Ganti semua gudang (Replace)|0|",
        "add_button|boren_submit_stpaste|`2+ Tempel / Tambah ke Antrean|noflags|0|0|",
        "add_spacer|small|",

        -- Bagian 3: Daftar Gudang & Aksi Edit/Hapus
        string.format("add_textbox|`2[3. Daftar Antrean Gudang (%d Gudang)]|left|", #CFG.storage_world_list)
    }

    if #CFG.storage_world_list == 0 then
        table.insert(dLines, "add_textbox|`4(Daftar Gudang Seed masih kosong. Silakan tempel di atas!)|left|")
    else
        for i, e in ipairs(CFG.storage_world_list) do
            local d = (e.door and e.door ~= "") and e.door or "-"
            local act = (i == STATE.active_storage_idx) and " `2[AKTIF]" or ""
            table.insert(dLines, string.format("add_textbox|`w%d. `9%s `o[Door: %s]%s|left|", i, e.name, d, act))
            table.insert(dLines, string.format("add_button|boren_stedit_%d|Edit|noflags|0|0|", i))
            table.insert(dLines, string.format("add_button|boren_sthapus_%d|Hapus|noflags|0|0|", i))
            table.insert(dLines, "add_spacer|small|")
        end
    end

    table.insert(dLines, "end_dialog|boren_plant_stor_mgr|Tutup||")
    return safeSendRawDialog(table.concat(dLines, "\n"))
end

openEditWorldEntryDialog = function(idx)
    idx = tonumber(idx) or 0
    local e = CFG.world_list[idx]
    if not e then return false end
    local dLines = {
        "set_default_color|`o",
        string.format("add_label_with_icon|big|`wEdit World Farm #%d``|left|2|", idx),
        "add_textbox|`oUbah nama world atau Door ID di bawah ini:|left|",
        "add_spacer|small|",
        string.format("add_text_input|boren_ed_wname|Nama World|%s|32|", e.name or ""),
        string.format("add_text_input|boren_ed_wdoor|Door ID (Kosong = White Door)|%s|32|", e.door or ""),
        "add_spacer|small|",
        string.format("add_button|boren_save_wedit_%d|`2Simpan Perubahan|noflags|0|0|", idx),
        "end_dialog|boren_edit_w_dlg|Batal||"
    }
    return safeSendRawDialog(table.concat(dLines, "\n"))
end

openEditStorageEntryDialog = function(idx)
    idx = tonumber(idx) or 0
    local e = CFG.storage_world_list[idx]
    if not e then return false end
    local dLines = {
        "set_default_color|`o",
        string.format("add_label_with_icon|big|`wEdit Gudang Seed #%d``|left|242|", idx),
        "add_textbox|`oUbah nama gudang atau Door ID di bawah ini:|left|",
        "add_spacer|small|",
        string.format("add_text_input|boren_ed_sname|Nama Gudang|%s|32|", e.name or ""),
        string.format("add_text_input|boren_ed_sdoor|Door ID (Kosong = White Door)|%s|32|", e.door or ""),
        "add_spacer|small|",
        string.format("add_button|boren_save_stedit_%d|`2Simpan Perubahan|noflags|0|0|", idx),
        "end_dialog|boren_edit_s_dlg|Batal||"
    }
    return safeSendRawDialog(table.concat(dLines, "\n"))
end

openPasteWorldListDialog = function(isStorage)
    if isStorage then
        return openStorageListManagerDialog()
    else
        return openWorldListManagerDialog()
    end
end

openCopyAllWorldsDialog = function(isStorage, fmt)
    if isStorage then
        return openStorageListManagerDialog(fmt)
    else
        return openWorldListManagerDialog(fmt)
    end
end

-- Hook dialog return untuk memproses submit Quick Paste & Copy Format & Edit/Hapus
local function onSendPacketDialogHook(ptype, pkt)
    if type(pkt) ~= "string" or not pkt:find("action|dialog_return", 1, true) then return false end
    local fields = {}
    for line in pkt:gmatch("[^\r\n]+") do
        local k, v = line:match("^([^|]+)|(.*)$")
        if k then fields[k] = v end
    end
    local dName = fields.dialog_name or ""
    local btn = fields.buttonClicked or ""

    if dName == "boren_plant_world_mgr" or dName == "boren_paste_farm_mgr" or dName == "boren_copy_farm_mgr" then
        if btn == "boren_btn_wfmt_colon" or btn == "boren_btn_fmt_colon" then
            openWorldListManagerDialog("colon")
            return true
        elseif btn == "boren_btn_wfmt_pipe" or btn == "boren_btn_fmt_pipe" then
            openWorldListManagerDialog("pipe")
            return true
        elseif btn == "boren_btn_wfmt_name" or btn == "boren_btn_fmt_name" then
            openWorldListManagerDialog("name_only")
            return true
        elseif btn == "boren_submit_wpaste" or btn == "boren_submit_paste" then
            local raw = pkt:match("boren_wpaste_raw|(.-)\nboren_wpaste_replace|")
                or pkt:match("boren_paste_raw|(.-)\nboren_paste_replace|")
                or pkt:match("boren_wpaste_raw|(.-)\nbuttonClicked|")
                or pkt:match("boren_paste_raw|(.-)\nbuttonClicked|")
                or fields.boren_wpaste_raw or fields.boren_paste_raw or ""
            local isReplace = (fields.boren_wpaste_replace == "1" or fields.boren_paste_replace == "1")
            local added, dups, ignored, summary = parseAndValidateWorldBatch(raw, isReplace)
            addLog("[Quick Paste Farm] " .. summary)
            if sendNotification then pcall(sendNotification, summary) end
            openWorldListManagerDialog()
            return true
        end

        local editIdx = btn:match("^boren_wedit_(%d+)$")
        if editIdx then
            openEditWorldEntryDialog(tonumber(editIdx))
            return true
        end

        local hapusIdx = btn:match("^boren_whapus_(%d+)$")
        if hapusIdx then
            local idx = tonumber(hapusIdx)
            if idx and CFG.world_list[idx] then
                local removed = table.remove(CFG.world_list, idx)
                if STATE.active_world_idx > #CFG.world_list then
                    STATE.active_world_idx = 1
                end
                persistConfig()
                updateWorldDisplayList()
                addLog(string.format("[World Farm] Dihapus dari antrean: %s", removed.name))
                if sendNotification then pcall(sendNotification, "Dihapus: " .. removed.name) end
                openWorldListManagerDialog()
            end
            return true
        end
        return true

    elseif dName == "boren_plant_stor_mgr" or dName == "boren_paste_stor_mgr" or dName == "boren_copy_stor_mgr" then
        if btn == "boren_btn_stfmt_colon" or btn == "boren_btn_fmt_colon" then
            openStorageListManagerDialog("colon")
            return true
        elseif btn == "boren_btn_stfmt_pipe" or btn == "boren_btn_fmt_pipe" then
            openStorageListManagerDialog("pipe")
            return true
        elseif btn == "boren_btn_stfmt_name" or btn == "boren_btn_fmt_name" then
            openStorageListManagerDialog("name_only")
            return true
        elseif btn == "boren_submit_stpaste" or btn == "boren_submit_paste" then
            local raw = pkt:match("boren_stpaste_raw|(.-)\nboren_stpaste_replace|")
                or pkt:match("boren_paste_raw|(.-)\nboren_paste_replace|")
                or pkt:match("boren_stpaste_raw|(.-)\nbuttonClicked|")
                or pkt:match("boren_paste_raw|(.-)\nbuttonClicked|")
                or fields.boren_stpaste_raw or fields.boren_paste_raw or ""
            local isReplace = (fields.boren_stpaste_replace == "1" or fields.boren_paste_replace == "1")
            local added, dups, ignored, summary = parseAndValidateStorageBatch(raw, isReplace)
            addLog("[Quick Paste Gudang] " .. summary)
            if sendNotification then pcall(sendNotification, summary) end
            openStorageListManagerDialog()
            return true
        end

        local editIdx = btn:match("^boren_stedit_(%d+)$")
        if editIdx then
            openEditStorageEntryDialog(tonumber(editIdx))
            return true
        end

        local hapusIdx = btn:match("^boren_sthapus_(%d+)$")
        if hapusIdx then
            local idx = tonumber(hapusIdx)
            if idx and CFG.storage_world_list[idx] then
                local removed = table.remove(CFG.storage_world_list, idx)
                if STATE.active_storage_idx > #CFG.storage_world_list then
                    STATE.active_storage_idx = 1
                end
                persistConfig()
                updateStorageDisplayList()
                addLog(string.format("[Gudang Seed] Dihapus dari antrean: %s", removed.name))
                if sendNotification then pcall(sendNotification, "Dihapus: " .. removed.name) end
                openStorageListManagerDialog()
            end
            return true
        end
        return true

    elseif dName == "boren_edit_w_dlg" then
        local saveIdx = btn:match("^boren_save_wedit_(%d+)$")
        if saveIdx then
            local idx = tonumber(saveIdx)
            if idx and CFG.world_list[idx] then
                local newName = tostring(fields.boren_ed_wname or ""):gsub("%s+", ""):upper()
                local newDoor = tostring(fields.boren_ed_wdoor or ""):gsub("^%s+", ""):gsub("%s+$", "")
                if newName ~= "" then
                    CFG.world_list[idx].name = newName
                    CFG.world_list[idx].door = newDoor
                    persistConfig()
                    updateWorldDisplayList()
                    addLog(string.format("[World Farm #%d] Diperbarui: %s [Door: %s]", idx, newName, (newDoor ~= "" and newDoor or "-")))
                    if sendNotification then pcall(sendNotification, "World Farm diperbarui: " .. newName) end
                end
            end
            openWorldListManagerDialog()
            return true
        end
        return true

    elseif dName == "boren_edit_s_dlg" then
        local saveIdx = btn:match("^boren_save_stedit_(%d+)$")
        if saveIdx then
            local idx = tonumber(saveIdx)
            if idx and CFG.storage_world_list[idx] then
                local newName = tostring(fields.boren_ed_sname or ""):gsub("%s+", ""):upper()
                local newDoor = tostring(fields.boren_ed_sdoor or ""):gsub("^%s+", ""):gsub("%s+$", "")
                if newName ~= "" then
                    CFG.storage_world_list[idx].name = newName
                    CFG.storage_world_list[idx].door = newDoor
                    persistConfig()
                    updateStorageDisplayList()
                    addLog(string.format("[Gudang #%d] Diperbarui: %s [Door: %s]", idx, newName, (newDoor ~= "" and newDoor or "-")))
                    if sendNotification then pcall(sendNotification, "Gudang diperbarui: " .. newName) end
                end
            end
            openStorageListManagerDialog()
            return true
        end
        return true
    end

    return false
end

-- ============================================================================
-- 17. NATIVE GROWLAUNCHER MENU ("Boren Store - Auto Plant")
-- ============================================================================
updatePowerStatusList = function()
    if not editValue then return end
    local statusTitle = STATE.running and (STATE.paused and "STATUS: DIJEDA (PAUSE)" or "STATUS: SEDANG BERJALAN") or "STATUS: BERHENTI (OFF)"
    local s1Info = string.format("%s (ID: %d) | Di Tas: %d", CFG.seed_1_name, CFG.seed_1_id, getInvCount(CFG.seed_1_id))
    local s2Info = CFG.splice_mode and string.format("%s (ID: %d) | Di Tas: %d", CFG.seed_2_name, CFG.seed_2_id, getInvCount(CFG.seed_2_id)) or "Nonaktif (Hanya tanam 1 seed)"
    local modeTxt = (CFG.plant_mode == "3zigzag") and "Tanam 3 Petak Sekaligus" or "Tanam 1 per 1 Petak"
    local curWTxt = (STATE.active_farm_world ~= "") and STATE.active_farm_world or "(Belum masuk world)"

    pcall(editValue, "ap_power_status_list", jsonEncode({
        { statusTitle, STATE.status_text or "Siap digunakan" },
        { "Pola Tanam", modeTxt },
        { "World Farm Saat Ini", curWTxt },
        { "Seed 1 (Utama)", s1Info },
        { "Seed 2 (Splice)", s2Info },
    }))
end

updateSeedStatusDisplay = function()
    if not editValue then return end
    local s1_id = STATE.buf_seed_1_id or CFG.seed_1_id
    local s2_id = STATE.buf_seed_2_id or CFG.seed_2_id

    local s1_dirty = (s1_id ~= CFG.seed_1_id)
    local s2_dirty = (s2_id ~= CFG.seed_2_id)

    local s1_name = resolveSeedName(s1_id)
    local s2_name = resolveSeedName(s2_id)

    local s1_title = s1_dirty and "⚠️ Seed 1 (Utama) [BELUM DISIMPAN]" or "✅ Seed 1 (Utama) [TERSIMPAN]"
    local s1_desc = string.format("%s (ID: %d) | Di Tas: %d%s",
        s1_name, s1_id, getInvCount(s1_id),
        s1_dirty and " -> Klik 'Simpan Pilihan ID Seed' di bawah!" or " (Siap Ditanam)"
    )

    local s2_title = ""
    local s2_desc = ""
    if CFG.splice_mode then
        if s1_id > 0 and s1_id == s2_id then
            s2_title = "⚠️ Seed 2 (Splice) [ID SAMA DENGAN SEED 1]"
            s2_desc = string.format("%s (ID: %d) -> Seed 1 & 2 tidak boleh sama! Masukkan ID berbeda.", s2_name, s2_id)
        else
            s2_title = s2_dirty and "⚠️ Seed 2 (Splice) [BELUM DISIMPAN]" or "✅ Seed 2 (Splice) [TERSIMPAN]"
            s2_desc = string.format("%s (ID: %d) | Di Tas: %d%s",
                s2_name, s2_id, getInvCount(s2_id),
                s2_dirty and " -> Klik 'Simpan Pilihan ID Seed' di bawah!" or " (Siap Displice)"
            )
        end
    else
        s2_title = "ℹ️ Seed 2 (Splice) [NONAKTIF]"
        s2_desc = "Mode Splice Nonaktif (Hanya tanam 1 jenis seed)"
    end

    pcall(editValue, "ap_seed_status_display", jsonEncode({
        { s1_title, s1_desc },
        { s2_title, s2_desc },
    }))
end

updateBagDisplayList = function()
    if not editValue then return end
    local bList = {}
    for _, it in ipairs(STATE.cached_inv) do
        table.insert(bList, {
            string.format("%s (ID: %d)", it.name, it.id),
            string.format("Jumlah: %d", it.amount)
        })
    end
    if #bList == 0 then table.insert(bList, { "Tas kosong", "-" }) end
    pcall(editValue, "ap_bag_display_list", jsonEncode(bList))
end

updateLogDisplayList = function()
    if not editValue then return end
    local src = STATE.console_errors_only and STATE.error_logs or STATE.logs
    local lList = {}
    for _, l in ipairs(src) do
        table.insert(lList, { l, "" })
    end
    if #lList == 0 then table.insert(lList, { "Belum ada log.", "" }) end
    pcall(editValue, "ap_log_display_list", jsonEncode(lList))
end

local function createNativeUI(subName, iconName)
    if UserInterface and UserInterface.new then
        return UserInterface.new(subName, iconName)
    end
    local ui = { sub_name = subName, icon = iconName, menu = {} }
    function ui:addLabelApp(text, icon) table.insert(self.menu, { type = "labelapp", text = text, icon = icon or "" }) return self end
    function ui:addLabel(text) table.insert(self.menu, { type = "label", text = text }) return self end
    function ui:addDivider() table.insert(self.menu, { type = "divider" }) return self end
    function ui:addToggle(text, default, alias, autosave) table.insert(self.menu, { type = "toggle", text = text, default = default == true, alias = alias, autosave = autosave == true }) return self end
    function ui:addToggleButton(text, default, alias) table.insert(self.menu, { type = "toggle_button", text = text, default = default == true, alias = alias }) return self end
    function ui:addButton(text, alias) table.insert(self.menu, { type = "button", text = text, alias = alias }) return self end
    function ui:addInputString(text, default, label, placeholder, icon, alias) table.insert(self.menu, { type = "input_string", text = text, default = default or "", label = label or "Text", placeholder = placeholder or "", icon = icon or "", alias = alias }) return self end
    function ui:addInputInt(text, default, label, placeholder, icon, alias) table.insert(self.menu, { type = "input_int", text = text, default = tostring(default or "0"), label = label or "Value", placeholder = placeholder or "0", icon = icon or "", alias = alias }) return self end
    function ui:addSlider(text, minVal, maxVal, defaultVal, stepVal, useDot, alias) table.insert(self.menu, { type = "slider", text = text, min = minVal, max = maxVal, default = defaultVal, step = stepVal, use_dot = useDot == true, alias = alias }) return self end
    function ui:addTooltip(text, supportText, icon, background) table.insert(self.menu, { type = "tooltip", text = text, support_text = supportText or "", icon = icon or "Info", background = background == true }) return self end
    function ui:addItemPicker(text, item, default, alias) table.insert(self.menu, { type = "item_picker", text = text, item = item or "Blank", default = tostring(default or "0"), alias = alias }) return self end
    function ui:addDisplayList(text, displayType, alias) table.insert(self.menu, { type = "display_list", text = text, display_type = displayType or "Default", alias = alias }) return self end
    function ui:addExpandableToggle(text, default, alias, autoExpand, background) return { list_child = alias .. "_child" } end
    function ui:addChildButton(childRef, text, alias) table.insert(self.menu, { type = "child_button", child = childRef, text = text, alias = alias }) return self end
    function ui:addChildToggle(childRef, text, default, alias) table.insert(self.menu, { type = "child_toggle", child = childRef, text = text, default = default == true, alias = alias }) return self end
    return ui
end

local function registerNativePlantUI()
    if not addCategory or not addIntoModule then return end

    -- Tab 1: Start & World Farm
    local uiFarm = createNativeUI("1. Start & World Farm", "PlayArrow")
    uiFarm:addLabelApp("Boren Store - Auto Plant & Splice", "Spa")
    uiFarm:addToggleButton("▶ START BOT (Mulai Tanam)", false, "ap_run_power")
    uiFarm:addButton("■ STOP BOT (Matikan)", "ap_btn_stop")
    uiFarm:addToggle("Jeda Bot Sementara (Pause)", false, "ap_pause_toggle", false)
    uiFarm:addDisplayList("Status & Info Bot", "Default", "ap_power_status_list")
    uiFarm:addDivider()

    uiFarm:addLabel("Pengaturan Tanam & Splice:")
    uiFarm:addToggle("Tanam 3 Petak Sekaligus (Gaya Lucifer)", CFG.plant_mode == "3zigzag", "ap_toggle_mode_3zigzag", true)
    uiFarm:addToggle("Aktifkan Splice (Kawin 2 Seed)", CFG.splice_mode, "ap_toggle_splice", true)
    uiFarm:addDivider()

    uiFarm:addLabel("Pengaturan Bibit (Input ID Manual):")
    uiFarm:addInputInt("ID Seed 1 (Utama)", tostring(CFG.seed_1_id), "Seed ID 1", "Contoh: 3 (Dirt) / 4585 (Pepper)", "Tag", "ap_input_seed_1")
    uiFarm:addInputInt("ID Seed 2 (Splice)", tostring(CFG.seed_2_id), "Seed ID 2", "Contoh: 15 (Cave)", "Tag", "ap_input_seed_2")
    uiFarm:addButton("💾 Simpan Pilihan ID Seed", "ap_btn_save_seeds")
    uiFarm:addDisplayList("Keterangan & Status ID Seed", "Default", "ap_seed_status_display")
    uiFarm:addDivider()

    uiFarm:addLabel("Daftar World Farm:")
    uiFarm:addInputString("Nama World Farm", CFG.manual_world_text, "World", "Ketik nama world", "Public", "ap_manual_world_input")
    uiFarm:addInputString("Door ID (Opsional)", CFG.manual_door_text, "Door ID", "Kosongkan jika White Door", "DoorFront", "ap_manual_door_input")
    uiFarm:addButton("+ Tambah World ke Antrean", "ap_btn_add_world")
    uiFarm:addButton("+ Tambah World Saya Sekarang", "ap_btn_add_cur_world")
    uiFarm:addButton("📋 Kelola, Salin & Tempel World", "ap_btn_view_worlds")
    uiFarm:addButton("🗑️ Kosongkan Semua World Farm", "ap_btn_clear_worlds")
    uiFarm:addDivider()

    uiFarm:addLabel("Cadangan File (Folder Download HP):")
    uiFarm:addDisplayList("Status File Download", "Default", "ap_file_info_list")
    uiFarm:addButton("📥 Simpan Antrean ke Download", "ap_btn_save_worlds")
    uiFarm:addButton("📤 Muat Antrean dari Download", "ap_btn_load_worlds")
    uiFarm:addDisplayList("Daftar Antrean Farm", "Default", "ap_world_display_list")

    -- Tab 2: Gudang Seed (Storage)
    local uiStorage = createNativeUI("2. Gudang Seed (Storage)", "Inventory")
    uiStorage:addLabelApp("Gudang Seed & Ambil Otomatis", "Inventory")
    uiStorage:addTooltip("Fitur Gudang Cerdas", "Bot otomatis pergi mengambil seed saat di tas habis. Jika gudang kosong, bot otomatis lompat ke gudang berikutnya!", "Verified", false)
    uiStorage:addSlider("Sisa Seed di Tas untuk Ambil (Min BP)", 0, 20, CFG.min_seed_bp, 1, false, "ap_slider_min_bp")
    uiStorage:addSlider("Target Jumlah Ambil Seed ke Tas", 50, 200, CFG.target_seed_bp, 10, false, "ap_slider_target_bp")
    uiStorage:addSlider("Jarak Magnet Ambil Seed (Tile)", 1, 6, CFG.collect_range, 1, false, "ap_slider_collect_range")
    uiStorage:addDivider()

    uiStorage:addLabel("Daftar World Gudang Seed:")
    uiStorage:addInputString("Nama World Gudang", CFG.manual_storage_text, "Gudang", "Ketik nama world gudang", "Public", "ap_manual_stor_input")
    uiStorage:addInputString("Door ID (Opsional)", CFG.manual_stor_door, "Door ID", "Kosongkan jika White Door", "DoorFront", "ap_manual_stor_door_input")
    uiStorage:addButton("+ Tambah Gudang ke Antrean", "ap_btn_add_storage")
    uiStorage:addButton("📋 Kelola, Salin & Tempel Gudang", "ap_btn_view_storages")
    uiStorage:addButton("📥 Simpan Antrean Gudang ke File", "ap_btn_save_storages")
    uiStorage:addButton("📤 Muat Antrean Gudang dari File", "ap_btn_load_storages")
    uiStorage:addButton("🗑️ Kosongkan Semua Gudang", "ap_btn_clear_storages")
    uiStorage:addDivider()
    uiStorage:addDisplayList("Daftar World Gudang Seed", "Default", "ap_storage_display_list")

    -- Tab 3: Pengaturan & Delay
    local uiSetting = createNativeUI("3. Pengaturan & Delay", "Build")
    uiSetting:addLabelApp("Kecepatan & Delay Bot", "Build")
    uiSetting:addInputInt("Kecepatan Tanam (ms)", tostring(CFG.plant_delay), "Plant Delay (ms)", "Contoh: 70", "Timer", "ap_input_plant_delay")
    uiSetting:addSlider("Jeda Timpa Splice Seed 2 (ms)", 40, 300, CFG.splice_delay, 10, false, "ap_slider_splice_delay")
    uiSetting:addSlider("Kecepatan Melangkah (ms)", 50, 500, CFG.step_delay, 10, false, "ap_slider_step_delay")
    uiSetting:addSlider("Jeda Pindah World / Warp (ms)", 2000, 6000, CFG.warp_delay, 500, false, "ap_slider_warp_delay")
    uiSetting:addDivider()

    uiSetting:addLabel("Fitur Pembantu & Proteksi:")
    uiSetting:addToggle("Abaikan Gems (Jangan Ambil Gems di Lantai)", CFG.ignore_gems, "ap_toggle_ignore_gems", true)
    uiSetting:addToggle("ModFly (Terbang Bebas)", CFG.use_modfly, "ap_toggle_modfly", true)
    uiSetting:addToggle("Anti Lava / Rintangan Berbahaya", CFG.anti_lava, "ap_toggle_anti_lava", true)
    uiSetting:addToggle("Login Ulang Otomatis (Auto Reconnect)", CFG.auto_reconnect, "ap_toggle_reconnect", true)

    -- Tab 4: Console & Tas
    local uiConsole = createNativeUI("4. Console & Tas", "Terminal")
    uiConsole:addLabelApp("Catatan Log & Isi Tas", "Terminal")
    uiConsole:addButton("🗑️ Bersihkan Semua Catatan Log", "ap_btn_clear_logs")
    uiConsole:addToggle("Hanya Tampilkan Pesan Error", STATE.console_errors_only, "ap_toggle_err_only", false)
    uiConsole:addDisplayList("Catatan Aktivitas Bot", "Default", "ap_log_display_list")
    uiConsole:addDivider()
    uiConsole:addLabel("Isi Tas / Backpack:")
    uiConsole:addButton("🔄 Perbarui Tampilan Tas", "ap_btn_refresh_bag")
    uiConsole:addDisplayList("Daftar Barang di Tas", "Default", "ap_bag_display_list")

    addCategory("Boren Plant", "Spa")
    addIntoModule(uiFarm:generateJSON(), "Boren Plant")
    addIntoModule(uiStorage:generateJSON(), "Boren Plant")
    addIntoModule(uiSetting:generateJSON(), "Boren Plant")
    addIntoModule(uiConsole:generateJSON(), "Boren Plant")
end

-- ============================================================================
-- 17B. FILE BACKUP ENGINE (FARM WORLDS & STORAGE WORLDS)
-- ============================================================================
local function savePlantWorldsToFile()
    persistConfig()
    local exportLines = {}
    for _, e in ipairs(CFG.world_list) do
        local line = (e.door and e.door ~= "") and (e.name .. ":" .. e.door) or e.name
        table.insert(exportLines, line)
    end
    local exportTxt = table.concat(exportLines, "\n")
    local fullPath, dir, fName = resolveFilePath(CFG.world_file_name, "boren_plant_worlds.txt")

    local saved = false
    if io and io.open then
        local okF, fh = pcall(io.open, fullPath, "w")
        if okF and fh then
            pcall(function()
                fh:write(exportTxt .. (exportTxt ~= "" and "\n" or ""))
                fh:close()
            end)
            saved = true
        end
        if not saved and not isSystemWindows() then
            local okA, fhA = pcall(io.open, "/sdcard/Download/" .. fName, "w")
            if okA and fhA then
                pcall(function()
                    fhA:write(exportTxt .. (exportTxt ~= "" and "\n" or ""))
                    fhA:close()
                end)
                saved = true
            end
        end
        if not saved then
            local okLoc, fhLoc = pcall(io.open, fName, "w")
            if okLoc and fhLoc then
                pcall(function()
                    fhLoc:write(exportTxt .. (exportTxt ~= "" and "\n" or ""))
                    fhLoc:close()
                end)
                saved = true
            end
        end
    end
    if writeToLocal then
        pcall(writeToLocal, fullPath, exportTxt)
        pcall(writeToLocal, fName, exportTxt)
        saved = true
    end

    local summary = string.format("Tersimpan %d world farm ke %s & Preferences.", #CFG.world_list, saved and fullPath or fName)
    addLog("[Save World] " .. summary)
    if sendNotification then pcall(sendNotification, summary) end
    if updateFileInfoDisplayList then pcall(updateFileInfoDisplayList) end
    return true
end

local function loadPlantWorldsFromFile()
    local fullPath, dir, fName = resolveFilePath(CFG.world_file_name, "boren_plant_worlds.txt")
    local raw = ""
    local source = ""
    if io and io.open then
        local okF, fh = pcall(io.open, fullPath, "r")
        if okF and fh then
            pcall(function()
                raw = fh:read("*all") or ""
                fh:close()
            end)
            if raw ~= "" then source = fullPath end
        end
        if raw == "" and not isSystemWindows() then
            local okA, fhA = pcall(io.open, "/sdcard/Download/" .. fName, "r")
            if okA and fhA then
                pcall(function()
                    raw = fhA:read("*all") or ""
                    fhA:close()
                end)
                if raw ~= "" then source = "/sdcard/Download/" .. fName end
            end
        end
        if raw == "" then
            local okLoc, fhLoc = pcall(io.open, fName, "r")
            if okLoc and fhLoc then
                pcall(function()
                    raw = fhLoc:read("*all") or ""
                    fhLoc:close()
                end)
                if raw ~= "" then source = fName end
            end
        end
    end

    if raw ~= "" then
        local added, dups, ignored, summary = parseAndValidateWorldBatch(raw, true)
        addLog(string.format("[Load World] Berhasil memuat %d world dari %s", added, source))
        if sendNotification then pcall(sendNotification, string.format("Berhasil memuat %d world dari Download!", added)) end
    else
        addLog("[Load World] File world tidak ditemukan atau kosong!")
        if sendNotification then pcall(sendNotification, "File world belum ada atau kosong!") end
    end
    if updateFileInfoDisplayList then pcall(updateFileInfoDisplayList) end
    if updateWorldDisplayList then pcall(updateWorldDisplayList) end
end

local function savePlantStoragesToFile()
    persistConfig()
    local exportLines = {}
    for _, e in ipairs(CFG.storage_world_list) do
        local line = (e.door and e.door ~= "") and (e.name .. ":" .. e.door) or e.name
        table.insert(exportLines, line)
    end
    local exportTxt = table.concat(exportLines, "\n")
    local fullPath, dir, fName = resolveFilePath("boren_plant_storages.txt", "boren_plant_storages.txt")

    local saved = false
    if io and io.open then
        local okF, fh = pcall(io.open, fullPath, "w")
        if okF and fh then
            pcall(function()
                fh:write(exportTxt .. (exportTxt ~= "" and "\n" or ""))
                fh:close()
            end)
            saved = true
        end
        if not saved and not isSystemWindows() then
            local okA, fhA = pcall(io.open, "/sdcard/Download/" .. fName, "w")
            if okA and fhA then
                pcall(function()
                    fhA:write(exportTxt .. (exportTxt ~= "" and "\n" or ""))
                    fhA:close()
                end)
                saved = true
            end
        end
        if not saved then
            local okLoc, fhLoc = pcall(io.open, fName, "w")
            if okLoc and fhLoc then
                pcall(function()
                    fhLoc:write(exportTxt .. (exportTxt ~= "" and "\n" or ""))
                    fhLoc:close()
                end)
                saved = true
            end
        end
    end
    if writeToLocal then
        pcall(writeToLocal, fullPath, exportTxt)
        pcall(writeToLocal, fName, exportTxt)
        saved = true
    end

    local summary = string.format("Tersimpan %d gudang ke %s & Preferences.", #CFG.storage_world_list, saved and fullPath or fName)
    addLog("[Save Storage] " .. summary)
    if sendNotification then pcall(sendNotification, summary) end
    return true
end

local function loadPlantStoragesFromFile()
    local fullPath, dir, fName = resolveFilePath("boren_plant_storages.txt", "boren_plant_storages.txt")
    local raw = ""
    local source = ""
    if io and io.open then
        local okF, fh = pcall(io.open, fullPath, "r")
        if okF and fh then
            pcall(function()
                raw = fh:read("*all") or ""
                fh:close()
            end)
            if raw ~= "" then source = fullPath end
        end
        if raw == "" and not isSystemWindows() then
            local okA, fhA = pcall(io.open, "/sdcard/Download/" .. fName, "r")
            if okA and fhA then
                pcall(function()
                    raw = fhA:read("*all") or ""
                    fhA:close()
                end)
                if raw ~= "" then source = "/sdcard/Download/" .. fName end
            end
        end
        if raw == "" then
            local okLoc, fhLoc = pcall(io.open, fName, "r")
            if okLoc and fhLoc then
                pcall(function()
                    raw = fhLoc:read("*all") or ""
                    fhLoc:close()
                end)
                if raw ~= "" then source = fName end
            end
        end
    end

    if raw ~= "" then
        local added, dups, ignored, summary = parseAndValidateStorageBatch(raw, true)
        addLog(string.format("[Load Storage] Berhasil memuat %d gudang dari %s", added, source))
        if sendNotification then pcall(sendNotification, string.format("Berhasil memuat %d gudang dari Download!", added)) end
    else
        addLog("[Load Storage] File gudang tidak ditemukan atau kosong!")
        if sendNotification then pcall(sendNotification, "File gudang belum ada atau kosong!") end
    end
    if updateStorageDisplayList then pcall(updateStorageDisplayList) end
end

-- ============================================================================
-- 18. NATIVE ON-VALUE EVENT DISPATCHER
-- ============================================================================
local isSyncingSeed = false
local lastAliasEventTime = {}

local function handlePlantUIValue(typeVal, name, val)
    -- Shift argumen jika GrowLauncher memanggil onValue(alias, val) atau alias ada di typeVal
    if type(typeVal) == "string" and (name == nil or type(name) ~= "string" or (type(name) == "string" and typeVal:sub(1, 3) == "ap_")) then
        val = name
        name = typeVal
        typeVal = 0
    end
    name = tostring(name or "")
    if name == "" then return end

    -- Debounce anti spam event (terutama saat addHook & setOnValue aktif bersamaan)
    local now = os.clock()
    local isButton = (name:sub(1, 7) == "ap_btn_")
    if isButton then
        if lastAliasEventTime[name] and (now - lastAliasEventTime[name]) < 0.25 then
            return
        end
        lastAliasEventTime[name] = now
    else
        local evKey = name .. "=" .. tostring(val)
        if lastAliasEventTime[evKey] and (now - lastAliasEventTime[evKey]) < 0.08 then
            return
        end
        lastAliasEventTime[evKey] = now
    end

    if name == "ap_run_power" then
        if val == true or val == 1 then
            startBot()
        else
            stopBot()
        end
    elseif name == "ap_btn_stop" then
        stopBot()
    elseif name == "ap_pause_toggle" then
        STATE.paused = (val == true or val == 1)
        setStatus(STATE.paused and "Bot Dijeda" or "Bot Dilanjutkan")
    elseif name == "ap_toggle_mode_3zigzag" then
        CFG.plant_mode = (val == true or val == 1) and "3zigzag" or "1by1"
        persistConfig()
        updatePowerStatusList()
    elseif name == "ap_toggle_splice" then
        CFG.splice_mode = (val == true or val == 1)
        persistConfig()
        updatePowerStatusList()
        updateSeedStatusDisplay()
    elseif name == "ap_input_seed_1" then
        local num = tonumber(val)
        if num and num > 0 then
            STATE.buf_seed_1_id = math.floor(num)
            updateSeedStatusDisplay()
        end
    elseif name == "ap_input_seed_2" then
        local num = tonumber(val)
        if num and num > 0 then
            STATE.buf_seed_2_id = math.floor(num)
            updateSeedStatusDisplay()
        end
    elseif name == "ap_btn_save_seeds" then
        local s1 = STATE.buf_seed_1_id or CFG.seed_1_id
        local s2 = STATE.buf_seed_2_id or CFG.seed_2_id
        s1 = ensureSeedID(s1)
        if CFG.splice_mode and s2 and s2 > 0 then
            s2 = ensureSeedID(s2)
        end
        CFG.seed_1_id = s1
        CFG.seed_1_name = resolveSeedName(s1)
        STATE.buf_seed_1_id = s1
        if CFG.splice_mode then
            CFG.seed_2_id = s2
            CFG.seed_2_name = resolveSeedName(s2)
            STATE.buf_seed_2_id = s2
        end
        persistConfig()
        if editValue then
            pcall(editValue, "ap_input_seed_1", tostring(CFG.seed_1_id))
            if CFG.splice_mode then
                pcall(editValue, "ap_input_seed_2", tostring(CFG.seed_2_id))
            end
        end
        updateSeedStatusDisplay()
        updatePowerStatusList()
        local msg = string.format("✅ Berhasil Disimpan: Seed 1 = %s (ID: %d)", CFG.seed_1_name, CFG.seed_1_id)
        if CFG.splice_mode and CFG.seed_2_id and CFG.seed_2_id > 0 then
            msg = msg .. string.format(" | Seed 2 = %s (ID: %d)", CFG.seed_2_name, CFG.seed_2_id)
        end
        addLog(msg)
        if sendNotification then pcall(sendNotification, msg) end
    elseif name == "ap_manual_world_input" then
        CFG.manual_world_text = tostring(val or "")
        persistConfig()
    elseif name == "ap_manual_door_input" then
        CFG.manual_door_text = tostring(val or "")
        persistConfig()
    elseif name == "ap_manual_stor_input" then
        CFG.manual_storage_text = tostring(val or "")
        persistConfig()
    elseif name == "ap_manual_stor_door_input" then
        CFG.manual_stor_door = tostring(val or "")
        persistConfig()
    elseif name == "ap_btn_add_world" then
        local w = tostring(CFG.manual_world_text or ""):gsub("%s+", ""):upper()
        local d = tostring(CFG.manual_door_text or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if w ~= "" then
            table.insert(CFG.world_list, { name = w, door = d, done = false, status = "ANTRI" })
            persistConfig()
            updateWorldDisplayList()
            if sendNotification then pcall(sendNotification, "World Farm ditambahkan: " .. w) end
        end
    elseif name == "ap_btn_add_cur_world" then
        local curW = getCurrentWorldSafe()
        if curW ~= "" and curW ~= "EXIT" then
            table.insert(CFG.world_list, { name = curW, door = "", done = false, status = "ANTRI" })
            persistConfig()
            updateWorldDisplayList()
            if sendNotification then pcall(sendNotification, "World Farm ditambahkan: " .. curW) end
        end
    elseif name == "ap_btn_clear_worlds" then
        CFG.world_list = {}
        persistConfig()
        updateWorldDisplayList()
        if sendNotification then pcall(sendNotification, "Daftar World Farm dikosongkan!") end
    elseif name == "ap_btn_view_worlds" or name == "ap_btn_paste_worlds" or name == "ap_btn_copy_all_worlds" then
        openWorldListManagerDialog()
    elseif name == "ap_btn_save_worlds" then
        savePlantWorldsToFile()
    elseif name == "ap_btn_load_worlds" then
        loadPlantWorldsFromFile()
    elseif name == "ap_btn_add_storage" then
        local w = tostring(CFG.manual_storage_text or ""):gsub("%s+", ""):upper()
        local d = tostring(CFG.manual_stor_door or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if w ~= "" then
            table.insert(CFG.storage_world_list, { name = w, door = d })
            persistConfig()
            updateStorageDisplayList()
            if sendNotification then pcall(sendNotification, "World Storage ditambahkan: " .. w) end
        end
    elseif name == "ap_btn_clear_storages" then
        CFG.storage_world_list = {}
        persistConfig()
        updateStorageDisplayList()
        if sendNotification then pcall(sendNotification, "Daftar Storage dikosongkan!") end
    elseif name == "ap_btn_view_storages" or name == "ap_btn_paste_storages" or name == "ap_btn_copy_all_storages" then
        openStorageListManagerDialog()
    elseif name == "ap_btn_save_storages" then
        savePlantStoragesToFile()
    elseif name == "ap_btn_load_storages" then
        loadPlantStoragesFromFile()
    elseif name == "ap_slider_min_bp" then
        CFG.min_seed_bp = tonumber(val) or CFG.min_seed_bp
        persistConfig()
    elseif name == "ap_slider_target_bp" then
        CFG.target_seed_bp = tonumber(val) or CFG.target_seed_bp
        persistConfig()
    elseif name == "ap_slider_collect_range" then
        CFG.collect_range = tonumber(val) or CFG.collect_range
        persistConfig()
    elseif name == "ap_input_plant_delay" or name == "ap_slider_plant_delay" then
        local d = tonumber(val) or 70
        CFG.plant_delay = math.max(10, math.min(5000, math.floor(d)))
        persistConfig()
        if sendNotification then pcall(sendNotification, "Delay tanam: " .. CFG.plant_delay .. " ms") end
    elseif name == "ap_slider_splice_delay" then
        CFG.splice_delay = tonumber(val) or CFG.splice_delay
        persistConfig()
    elseif name == "ap_slider_step_delay" then
        CFG.step_delay = tonumber(val) or CFG.step_delay
        persistConfig()
    elseif name == "ap_slider_warp_delay" then
        CFG.warp_delay = tonumber(val) or CFG.warp_delay
        persistConfig()
    elseif name == "ap_toggle_ignore_gems" then
        CFG.ignore_gems = (val == true or val == 1)
        persistConfig()
    elseif name == "ap_toggle_modfly" then
        CFG.use_modfly = (val == true or val == 1)
        persistConfig()
        applyCheatToggles()
    elseif name == "ap_toggle_anti_lava" then
        CFG.anti_lava = (val == true or val == 1)
        persistConfig()
        applyCheatToggles()
    elseif name == "ap_toggle_reconnect" then
        CFG.auto_reconnect = (val == true or val == 1)
        persistConfig()
        applyCheatToggles()
    elseif name == "ap_btn_clear_logs" then
        STATE.logs = {}
        STATE.error_logs = {}
        STATE.error_count = 0
        updateLogDisplayList()
    elseif name == "ap_toggle_err_only" then
        STATE.console_errors_only = (val == true or val == 1)
        updateLogDisplayList()
    elseif name == "ap_btn_refresh_bag" then
        syncInventoryCache()
    end
end

-- Alias global OnValue & onValue agar dipanggil oleh engine Growlauncher di semua platform
function OnValue(typeVal, name, val)
    local ok, err = pcall(handlePlantUIValue, typeVal, name, val)
    if not ok then
        addLog("[Plant UI Err] " .. tostring(err))
    end
end
onValue = OnValue

local ALL_UI_ALIASES = {
    "ap_run_power", "ap_btn_stop", "ap_pause_toggle", "ap_toggle_mode_3zigzag",
    "ap_toggle_splice", "ap_input_seed_1", "ap_input_seed_2", "ap_btn_save_seeds",
    "ap_seed_status_display", "ap_manual_world_input", "ap_manual_door_input", "ap_btn_add_world",
    "ap_btn_add_cur_world", "ap_btn_view_worlds", "ap_btn_clear_worlds", "ap_btn_save_worlds",
    "ap_btn_load_worlds", "ap_slider_min_bp", "ap_slider_target_bp", "ap_slider_collect_range",
    "ap_manual_stor_input", "ap_manual_stor_door_input", "ap_btn_add_storage", "ap_btn_view_storages",
    "ap_btn_save_storages", "ap_btn_load_storages", "ap_btn_clear_storages", "ap_input_plant_delay",
    "ap_slider_plant_delay", "ap_slider_splice_delay", "ap_slider_step_delay",
    "ap_slider_warp_delay", "ap_toggle_ignore_gems", "ap_toggle_modfly", "ap_toggle_anti_lava",
    "ap_toggle_reconnect", "ap_btn_clear_logs", "ap_toggle_err_only", "ap_btn_refresh_bag"
}

if setOnValue then
    for _, aliasName in ipairs(ALL_UI_ALIASES) do
        pcall(setOnValue, aliasName, function(a1, a2, a3)
            if a2 == aliasName then
                OnValue(a1, a2, a3)
            elseif a1 == aliasName then
                OnValue(0, a1, a2)
            else
                OnValue(0, aliasName, a1)
            end
        end)
    end
end

-- ============================================================================
-- 19. INITIALIZATION & HOOK BINDINGS
-- ============================================================================
ensureHooksInstalled()
onSendPacket = onSendPacketDialogHook
OnSendPacket = onSendPacketDialogHook
if addHook then
    pcall(addHook, OnValue, "onvalue")
    pcall(addHook, onSendPacketDialogHook, "onsendpacket")
end
if applyHook then
    pcall(applyHook)
end

registerNativePlantUI()
updatePowerStatusList()
updateSeedStatusDisplay()
updateWorldDisplayList()
updateStorageDisplayList()
updateFileInfoDisplayList()
updateLogDisplayList()
syncInventoryCache()

addLog("Auto Plant & Splice by Boren Store berhasil dimuat!")
if sendNotification then
    pcall(sendNotification, "Auto Plant & Splice v2.0 siap digunakan!")
end

