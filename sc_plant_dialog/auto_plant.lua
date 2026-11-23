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
pcall(function()
    if preferences and preferences.new then
        pref = preferences:new(PREF_FILE)
    end
end)
pcall(function()
    if not pref and Preferences and Preferences.new then
        pref = Preferences:new(PREF_FILE)
    end
end)

local function isSystemWindows()
    if package and package.config and package.config:sub(1, 1) == "\\" then
        return true
    end
    if os and type(os.getenv) == "function" then
        local ok, osEnv = pcall(os.getenv, "OS")
        if ok and osEnv and tostring(osEnv):lower():find("windows", 1, true) then
            return true
        end
    end
    return false
end

local function getUserProfilePath()
    if not isSystemWindows() then return "" end
    local up = ""
    if os and type(os.getenv) == "function" then
        local ok, res = pcall(os.getenv, "USERPROFILE")
        if ok and res then up = tostring(res) end
    end
    return up
end

local function getTimeSafe()
    if os and type(os.time) == "function" then
        local ok, t = pcall(os.time)
        if ok and type(t) == "number" then return t end
    end
    if os and type(os.clock) == "function" then
        local ok, c = pcall(os.clock)
        if ok and type(c) == "number" then return math.floor(c) end
    end
    return 0
end

local function getClockSafe()
    if os and type(os.clock) == "function" then
        local ok, c = pcall(os.clock)
        if ok and type(c) == "number" then return c end
    end
    return 0
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
        local userProfile = getUserProfilePath()
        if userProfile ~= "" then
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

local function readTextFileIfExists(fileName)
    if not fileName or fileName == "" then return nil end
    local fullPath, _, fName = resolveFilePath(fileName, fileName)
    local candidates = {
        fullPath,
        fName,
        "/sdcard/Download/" .. fName,
        "/storage/emulated/0/Download/" .. fName
    }
    -- 1. Metode native Growlauncher
    if readFile then
        for _, path in ipairs(candidates) do
            local ok, content = pcall(readFile, path)
            if ok and content and type(content) == "string" and content ~= "" then
                return content
            end
        end
    end
    -- 2. Fallback io.open
    if io and io.open then
        for _, path in ipairs(candidates) do
            local ok, fh = pcall(io.open, path, "r")
            if ok and fh then
                local content = nil
                pcall(function()
                    content = fh:read("*a")
                    fh:close()
                end)
                if content and content ~= "" then
                    return content
                end
            end
        end
    end
    return nil
end

local function writeTextFileIfExists(fileName, content)
    if not fileName or fileName == "" then return false end
    content = tostring(content or "")
    local fullPath, _, fName = resolveFilePath(fileName, fileName)
    local targets = {
        fullPath,
        fName,
        "/sdcard/Download/" .. fName,
        "/storage/emulated/0/Download/" .. fName
    }
    local wroteAny = false
    -- 1. Metode native Growlauncher
    if writeFile then
        local ok1 = pcall(writeFile, fullPath, content)
        local ok2 = pcall(writeFile, fName, content)
        if ok1 or ok2 then wroteAny = true end
    end
    -- 2. Fallback io.open
    if io and io.open then
        for _, path in ipairs(targets) do
            local ok, fh = pcall(io.open, path, "w")
            if ok and fh then
                pcall(function()
                    fh:write(content .. (content ~= "" and "\n" or ""))
                    fh:close()
                end)
                wroteAny = true
            end
        end
    end
    if writeToLocal then
        pcall(writeToLocal, fullPath, content)
        pcall(writeToLocal, fName, content)
        wroteAny = true
    end
    return wroteAny
end

local function loadPref(key, default)
    pcall(function()
        if saved and type(saved) ~= "boolean" and saved.get then
            local val = saved:get(key, default)
            if val ~= nil then default = val end
        end
    end)
    pcall(function()
        if pref and type(pref) ~= "boolean" and pref.get then
            local val = pref:get(key, default)
            if val ~= nil then default = val end
        end
    end)
    return default
end

local function savePrefs(cfg_table)
    local function doSave(storageObj)
        if not storageObj then return end
        pcall(function()
            for k, v in pairs(cfg_table) do
                local vt = type(v)
                if vt == "string" or vt == "number" or vt == "boolean" then
                    pcall(function() storageObj:set(k, v) end)
                end
            end
            -- Simpan daftar world farm sebagai string sederhana flat (NAME|DOOR|STATUS)
            local wParts = {}
            if type(cfg_table.world_list) == "table" then
                for _, entry in ipairs(cfg_table.world_list) do
                    if type(entry) == "table" and entry.name and entry.name ~= "" then
                        local flag = entry.done and "1" or "0"
                        table.insert(wParts, tostring(entry.name) .. "|" .. tostring(entry.door or "") .. "|" .. flag)
                    end
                end
            end
            pcall(function() storageObj:set("world_list_str", table.concat(wParts, ";")) end)

            -- Simpan daftar world storage sebagai string sederhana flat (NAME|DOOR)
            local sParts = {}
            if type(cfg_table.storage_world_list) == "table" then
                for _, entry in ipairs(cfg_table.storage_world_list) do
                    if type(entry) == "table" and entry.name and entry.name ~= "" then
                        table.insert(sParts, tostring(entry.name) .. "|" .. tostring(entry.door or ""))
                    end
                end
            end
            pcall(function() storageObj:set("storage_world_list_str", table.concat(sParts, ";")) end)

            pcall(function() storageObj:save() end)
        end)
    end

    if saved then pcall(doSave, saved) end
    if pref then pcall(doSave, pref) end
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

local function parseWorldEntryToken(rawToken, defaultDoor)
    local clean = tostring(rawToken or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if clean == "" or clean:sub(1, 1) == "#" then return nil end

    -- Dukung format: WORLD:ID, WORLD|ID, plus opsional status |1 / |0 / |DONE / |ANTRI / :DONE
    local body = clean
    local isDone = false
    local statusTag = nil

    local b1, tag1 = clean:match("^(.-)[|:](DONE)$")
    if not b1 then b1, tag1 = clean:match("^(.-)[|:](done)$") end
    if not b1 then b1, tag1 = clean:match("^(.-)[|:](PROSES)$") end
    if not b1 then b1, tag1 = clean:match("^(.-)[|:](ANTRI)$") end
    if not b1 then b1, tag1 = clean:match("^(.-)|([01])$") end
    if b1 and tag1 then
        body = b1
        statusTag = tag1:upper()
        isDone = (statusTag == "DONE" or statusTag == "1")
    end

    local wName, dId = body:match("^([^|:]+)[|:](.*)$")
    if not wName then
        wName = body
        dId = defaultDoor or ""
    end
    wName = wName:upper():gsub("%s+", "")
    dId = (dId or ""):gsub("%s+", "")
    if wName == "" or wName == "EXIT" or wName == "0" then return nil end

    local validName = wName:match("^([%w_]+)$")
    if not validName or #validName < 1 or #validName > 24 then return nil end

    return {
        name = validName:upper(),
        door = dId,
        done = isDone,
        status = isDone and "DONE" or (statusTag or "ANTRI")
    }
end

local function parseSavedWorldList()
    local list = {}
    local seen = {}
    -- 1. Baca dari file fisik boren_plant_worlds.txt di Download HP / PC (awet dan tidak pernah hilang saat GL ditutup)
    local rawFile = readTextFileIfExists("boren_plant_worlds.txt")
    if rawFile and rawFile ~= "" then
        local cleaned = rawFile:gsub("[\"\'%[%]%(%)]", " "):gsub("\t", " ")
        for token in cleaned:gmatch("[^\r\n;,]+") do
            local entry = parseWorldEntryToken(token, "")
            if entry and not seen[entry.name] then
                seen[entry.name] = true
                table.insert(list, entry)
            end
        end
    end
    -- 2. Sinkronkan dengan Preferences GL (world_list_str)
    local rawStr = loadPref("world_list_str", "")
    if type(rawStr) == "string" and rawStr ~= "" then
        for token in rawStr:gmatch("[^;\r\n]+") do
            local entry = parseWorldEntryToken(token, "")
            if entry and not seen[entry.name] then
                seen[entry.name] = true
                table.insert(list, entry)
            end
        end
    end
    return list
end

local function parseSavedStorageList()
    local list = {}
    local seen = {}
    -- 1. Baca dari file fisik boren_plant_storage.txt di Download HP / PC
    local rawFile = readTextFileIfExists("boren_plant_storage.txt")
    if not rawFile or rawFile == "" then
        rawFile = readTextFileIfExists("boren_plant_storages.txt")
    end
    if rawFile and rawFile ~= "" then
        local cleaned = rawFile:gsub("[\"\'%[%]%(%)]", " "):gsub("\t", " ")
        for token in cleaned:gmatch("[^\r\n;,]+") do
            local entry = parseWorldEntryToken(token, "")
            if entry and not seen[entry.name] then
                seen[entry.name] = true
                table.insert(list, { name = entry.name, door = entry.door })
            end
        end
    end
    -- 2. Sinkronkan dengan Preferences GL (storage_world_list_str)
    local rawStr = loadPref("storage_world_list_str", "")
    if type(rawStr) == "string" and rawStr ~= "" then
        for token in rawStr:gmatch("[^;\r\n]+") do
            local entry = parseWorldEntryToken(token, "")
            if entry and not seen[entry.name] then
                seen[entry.name] = true
                table.insert(list, { name = entry.name, door = entry.door })
            end
        end
    end
    return list
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
    plant_delay         = tonumber(loadPref("plant_delay", 180)) or 180,
    splice_delay        = tonumber(loadPref("splice_delay", 180)) or 180,
    step_delay          = tonumber(loadPref("step_delay", 110)) or 110,
    warp_delay          = tonumber(loadPref("warp_delay", 3500)) or 3500,

    -- Restock & Storage Settings
    min_seed_bp         = tonumber(loadPref("min_seed_bp", 3)) or 3,      -- Sisa seed di BP untuk memicu ambil ke storage
    target_seed_bp      = tonumber(loadPref("target_seed_bp", 150)) or 150,-- Target ambil seed di storage
    active_storage_idx  = tonumber(loadPref("active_storage_idx", 1)) or 1,
    collect_range       = tonumber(loadPref("collect_range", 3)) or 3,

    -- Toggles & Keamanan
    ignore_gems              = loadPref("ignore_gems", true),        -- Abaikan gems (ID 112)
    use_modfly               = loadPref("use_modfly", true),
    auto_reconnect           = loadPref("auto_reconnect", true),
    anti_lava                = loadPref("anti_lava", true),
    auto_clear_failed_splice = loadPref("auto_clear_failed_splice", true), -- Auto punch & replant pohon bertunas yg gagal splice

    -- World Lists (Safe Persistence Anti-Crash)
    world_list          = parseSavedWorldList(),
    storage_world_list  = parseSavedStorageList(),

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
    pending_drop_id     = 0,
    pending_drop_amt    = 0,
    drop_confirmed      = false,
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
    foreign_locked_tiles= {},
    blocked_tiles       = {},
    plant_fail_count    = {},
    fresh_seeds         = {},
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
local showPlantMainDialog
local showPlantAddCurrentWorldDialog
local showPlantQueueDialog
local showPlantStorageDialog
local showPlantPacingDialog
local showPlantLogsDialog
local showPlantItemSearchDialog
local openWorldListManagerDialog
local openEditWorldEntryDialog
local openStorageListManagerDialog
local openEditStorageEntryDialog
local openPasteWorldListDialog
local openCopyAllWorldsDialog
local parseAndValidateWorldBatch
local parseAndValidateStorageBatch
local resolvePickedItemID
local savePlantWorldsToFile
local savePlantStoragesToFile
local getCurrentWorldSafe

getCurrentWorldSafe = function()
    local fn = getCurrentWorldName or getWorld or getCurrentWorld
    if not fn then return "" end
    local ok, res = pcall(fn)
    if ok and res then
        if type(res) == "string" then return res:upper() end
        if type(res) == "table" and res.name then return tostring(res.name):upper() end
    end
    return ""
end

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
    local timestamp = "00:00:00"
    if os and type(os.date) == "function" then
        local okD, dRes = pcall(os.date, "%H:%M:%S")
        if okD and dRes then timestamp = tostring(dRes) end
    end
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

local function persistConfig(silentFileSave)
    savePrefs(CFG)
    if silentFileSave ~= false then
        if savePlantWorldsToFile then pcall(savePlantWorldsToFile, true) end
        if savePlantStoragesToFile then pcall(savePlantStoragesToFile, true) end
    end
end

-- ============================================================================
-- 3. ITEM & INVENTORY HELPERS
-- ============================================================================
-- ============================================================================
-- 5B. BOREN ITEM DATABASE & SEED RESOLVER ENGINE (16.480 ITEM DARI ITEM_DATABASE.TXT)
-- ============================================================================
local BOREN_ITEM_DB = {
    loaded = false,
    by_name = {},
    by_id = {},
    items_array = {},
    total_items = 0
}
_G.BOREN_ITEM_DB = BOREN_ITEM_DB

local COMMON_SEED_ALIASES = {
    ["PEPPER"]            = 4585,
    ["PEPPER TREE"]       = 4585,
    ["PEPPER SEED"]       = 4585,
    ["PEPPER TREE SEED"]  = 4585,
    ["LGRID"]             = 5667,
    ["L-GRID"]            = 5667,
    ["LASER GRID"]        = 5667,
    ["LASER GRID SEED"]   = 5667,
    ["CHAND"]             = 341,
    ["CHANDELIER"]        = 341,
    ["CHANDELIER SEED"]   = 341,
    ["GRASS"]             = 881,
    ["GRASS SEED"]        = 881,
    ["DIRT"]              = 3,
    ["DIRT SEED"]         = 3,
    ["ROCK"]              = 15,
    ["ROCK SEED"]         = 15,
    ["CAVE"]              = 17,
    ["CAVE SEED"]         = 17,
    ["CAVE BG"]           = 17,
    ["LAVA"]              = 11,
    ["LAVA SEED"]         = 11,
    ["WOOD"]              = 27,
    ["WOOD BLOCK"]        = 27,
    ["WOOD SEED"]         = 27,
    ["PLATFORM"]          = 103,
    ["WOODEN PLATFORM"]   = 103,
    ["FISHTANK"]          = 1043,
    ["FISH TANK"]         = 1043,
    ["FISH TANK SEED"]    = 1043,
    ["SHELF"]             = 1523,
    ["DISPLAY SHELF"]     = 1523,
    ["BELL"]              = 2595,
    ["MAGIC BELL"]        = 2595,
    ["SOIL"]              = 8773,
    ["FERTILE SOIL"]      = 8773,
    ["SOIL SEED"]         = 8773,
}

local SEARCH_PATHS_ITEM_DB = {
    "item_database.txt",
    "script/item_database.txt",
    "script/component/item_database.txt",
    "sc_plant_dialog/item_database.txt",
    "/storage/emulated/0/Android/media/launcher.powerkuy.growlauncher/ScriptLua/item_database.txt",
    "/storage/emulated/0/Android/data/launcher.powerkuy.growlauncher/files/ScriptLua/item_database.txt",
    "/storage/emulated/0/Download/item_database.txt"
}

function BOREN_ITEM_DB:findFile()
    for _, path in ipairs(SEARCH_PATHS_ITEM_DB) do
        local okF, fh = pcall(io.open, path, "r")
        if okF and fh then
            fh:close()
            return path
        end
    end
    return nil
end

function BOREN_ITEM_DB:load()
    if self.loaded then return true, self.total_items end
    local filePath = self:findFile()
    local rawText = nil

    if filePath then
        local okF, fh = pcall(io.open, filePath, "r")
        if okF and fh then
            rawText = fh:read("*a")
            fh:close()
        end
    end

    -- Cloud Fallback jika file lokal belum ada di perangkat
    if (not rawText or #rawText < 100) and fetch then
        local okFetch, res = pcall(fetch, "https://raw.githubusercontent.com/rendhi69/data-_id_item/main/item_database.txt")
        if okFetch and res and type(res) == "string" and #res > 1000 then
            rawText = res
            local okW, fhW = pcall(io.open, "item_database.txt", "w")
            if okW and fhW then
                fhW:write(res)
                fhW:close()
            end
        end
    end

    if rawText and #rawText > 100 then
        self.by_name = {}
        self.by_id = {}
        self.items_array = {}
        local count = 0
        for line in rawText:gmatch("[^\r\n]+") do
            local clean = line:gsub("^%s+", ""):gsub("%s+$", "")
            if clean ~= "" and clean:sub(1, 2) ~= "--" and clean:sub(1, 1) ~= "#" then
                local name, idStr = clean:match("^([^=]+)%s*=%s*(%d+)$")
                if name and idStr then
                    local id = tonumber(idStr)
                    local nm = name:gsub("^%s+", ""):gsub("%s+$", "")
                    if id and nm ~= "" then
                        self.by_name[nm:upper()] = id
                        self.by_id[id] = nm
                        self.items_array[#self.items_array + 1] = { name = nm, id = id }
                        count = count + 1
                    end
                end
            end
        end
        self.total_items = count
        self.loaded = (count > 0)
        addLog(string.format("[Item Database] Berhasil memuat %d item dari %s!", count, filePath or "Cloud"))
        return true, count
    end

    self.loaded = true
    return false, 0
end

function BOREN_ITEM_DB:resolveName(idOrName)
    if not self.loaded then self:load() end
    local num = tonumber(idOrName)
    if num and num > 0 then
        num = math.floor(num)
        if self.by_id[num] then return self.by_id[num] end
        return "Item #" .. num
    end
    local s = tostring(idOrName or ""):gsub("^%s+", ""):gsub("%s+$", ""):upper()
    local alias = COMMON_SEED_ALIASES[s]
    if alias and self.by_id[alias] then return self.by_id[alias] end
    if self.by_name[s] then return self.by_id[self.by_name[s]] end
    return tostring(idOrName or "")
end

function BOREN_ITEM_DB:resolveSeedID(input)
    if not self.loaded then self:load() end
    if not input then return 0, "" end

    local num = tonumber(input)
    if num ~= nil then
        if num <= 0 then return 0, "NONAKTIF" end
        num = math.floor(num)
        -- Standar Growtopia: Jika user input block/tree (genap), jadikan seed (ID + 1)
        local seedID = (num % 2 == 0) and (num + 1) or num
        local name = self:resolveName(seedID)
        return seedID, name
    end

    local s = tostring(input):gsub("^%s+", ""):gsub("%s+$", ""):upper()
    if s == "" or s == "0" or s == "NONE" or s == "NONAKTIF" or s == "OFF" then
        return 0, "NONAKTIF"
    end

    if COMMON_SEED_ALIASES[s] then
        local id = COMMON_SEED_ALIASES[s]
        return id, self:resolveName(id)
    end

    if self.by_name[s] then
        local id = self.by_name[s]
        local seedID = (id % 2 == 0) and (id + 1) or id
        return seedID, self:resolveName(seedID)
    end

    local seedKey = s .. " SEED"
    if self.by_name[seedKey] then
        local id = self.by_name[seedKey]
        return id, self:resolveName(id)
    end

    for _, it in ipairs(self.items_array) do
        local u = it.name:upper()
        if u == s or u == seedKey or (u:find(s, 1, true) and u:find("SEED", 1, true)) then
            local id = it.id
            local seedID = (id % 2 == 0) and (id + 1) or id
            return seedID, it.name
        end
    end

    return 0, ""
end

function BOREN_ITEM_DB:search(query, maxResults)
    if not self.loaded then self:load() end
    maxResults = maxResults or 8
    local results = {}
    local q = tostring(query or ""):gsub("^%s+", ""):gsub("%s+$", ""):upper()
    if q == "" then return results end

    local qNum = tonumber(q)
    if qNum and qNum > 0 and self.by_id[qNum] then
        results[#results + 1] = { id = qNum, name = self.by_id[qNum] }
    end

    for _, it in ipairs(self.items_array) do
        if it.name:upper():find(q, 1, true) then
            if not qNum or it.id ~= qNum then
                results[#results + 1] = it
                if #results >= maxResults then break end
            end
        end
    end
    return results
end

local function getItemNameSafe(itemID)
    itemID = tonumber(itemID) or 0
    if itemID <= 0 then return "" end
    return BOREN_ITEM_DB:resolveName(itemID)
end
_G.getItemNameSafe = getItemNameSafe

local function ensureSeedID(itemID)
    local sID, _ = BOREN_ITEM_DB:resolveSeedID(itemID)
    return (sID and sID > 0) and sID or (tonumber(itemID) or 0)
end
_G.ensureSeedID = ensureSeedID

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

    -- Guard: Jangan pernah akses inventory C++ bila di Title Screen (mencegah SIGSEGV NULL pointer)
    local curW = getCurrentWorldSafe()
    if curW == "" or curW:upper() == "EXIT" then
        return 0
    end

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
        if type(it) == "table" or type(it) == "userdata" then
            local okId, idVal = pcall(function() return it.id or it.itemid or it.itemID end)
            local id = (okId and tonumber(idVal)) or 0
            if id == itemID then
                local okAmt, amtVal = pcall(function() return it.amount or it.count end)
                total = total + ((okAmt and tonumber(amtVal)) or 0)
            end
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
    local curW = getCurrentWorldSafe()
    if curW == "" or curW:upper() == "EXIT" then
        STATE.cached_inv = {}
        return
    end
    local inv = getInventorySafe()
    local map = {}
    for _, it in pairs(inv) do
        if type(it) == "table" or type(it) == "userdata" then
            local okId, idVal = pcall(function() return it.id or it.itemid or it.itemID end)
            local id = (okId and tonumber(idVal)) or 0
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
    end
    local c = {}
    for _, it in pairs(map) do
        table.insert(c, it)
    end
    table.sort(c, function(a, b) return (a.amount or 0) > (b.amount or 0) end)
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

-- ============================================================================
-- 5. QUICK PASTE BATCH VALIDATOR (FARM & STORAGE)
-- ============================================================================

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
        -- Touch Shield: Mencegah sentuhan saat form terbuka memukul pohon/blok di game
        if _G.__BOREN_APEX_UI and _G.__BOREN_APEX_UI.open and not _G.__BOREN_APEX_UI.minimized and _G.__BOREN_APEX_UI_STATE and _G.__BOREN_APEX_UI_STATE.touch_shield then
            if pktType == 3 or pktType == 7 then
                return true -- Blokir punch & wrench saat form UI aktif
            end
        end

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
    local fn = getCurrentWorldName or getWorld or getCurrentWorld
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

local function isTileTree(t)
    if not t then return false end
    local fg = tonumber(t.fg) or 0
    if fg <= 0 then return false end

    -- 1. Siap panen (pasti pohon matang)
    if t.readyharvest == true then return true end
    if t.canHarvest and type(t.canHarvest) == "function" then
        local okH, resH = pcall(t.canHarvest, t)
        if okH and resH == true then return true end
    end

    -- 2. Memiliki buah di pohon
    if t.extra and type(t.extra) == "table" then
        local fruits = tonumber(t.extra.fruitcount) or 0
        if fruits > 0 then return true end
    end

    return false
end

local function isFreshlyPlantedSeed(tx, ty)
    if not STATE.fresh_seeds then return false end
    local key = tx .. "_" .. ty
    local plantTime = STATE.fresh_seeds[key]
    if plantTime and (getTimeSafe() - plantTime) <= 60 then
        return true
    end
    return false
end

local function getLocalSafe()
    local fn = getLocal
    if not fn then return nil end
    local ok, p = pcall(fn)
    if ok and p then return p end
    return nil
end

local function isLockOwnedByLocal(tLock)
    if not tLock then return false end
    local me = getLocalSafe()
    local myUserId = tonumber(me and (me.userID or me.userId)) or 0

    local okExtra, extra = pcall(function() return tLock.extra end)
    if okExtra and extra then
        local ownerId = 0
        pcall(function()
            ownerId = tonumber(extra.owner or extra.owner_signed) or 0
        end)
        if myUserId > 0 and ownerId > 0 and ownerId == myUserId then
            return true
        end
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
    STATE.foreign_locked_tiles = {}
    STATE.blocked_tiles = STATE.blocked_tiles or {}

    local mainDoorX, mainDoorY = nil, nil
    for y = 0, 53 do
        for x = 0, 99 do
            local t = getTileSafe(x, y)
            if t and tonumber(t.fg) == 6 then -- Main Door
                mainDoorX, mainDoorY = x, y
                break
            end
        end
        if mainDoorX then break end
    end

    local me = getLocalSafe()
    local myUserId = tonumber(me and (me.userID or me.userId)) or 0

    local foreignLockCount = 0
    local lockedTileCount = 0

    for y = 0, 53 do
        for x = 0, 99 do
            local t = getTileSafe(x, y)
            local fg = tonumber(t and t.fg) or 0
            -- Hanya periksa Small Lock (202), Big Lock (204), Huge Lock (206), dan Builder's Lock (4994)
            -- JANGAN PERNAH me-lock seluruh world berdasarkan World Lock (242) agar world farm milik sendiri tidak terkunci!
            if fg == 202 or fg == 204 or fg == 206 or fg == 4994 then
                -- JANGAN PERNAH tandai lock di dekat Main Door sebagai foreign lock (itu lock proteksi pintu farm sendiri!)
                local isNearDoor = false
                if mainDoorX and mainDoorY then
                    if math.abs(x - mainDoorX) <= 3 and math.abs(y - mainDoorY) <= 3 then
                        isNearDoor = true
                    end
                end

                if not isNearDoor then
                    -- Hanya anggap lock asing jika data owner definitif berbeda dan myUserId diketahui (> 0)
                    local isForeign = false
                    local okExtra, extra = pcall(function() return t.extra end)
                    if okExtra and extra and myUserId > 0 then
                        local ownerId = tonumber(extra.owner or extra.owner_signed) or 0
                        if ownerId > 0 and ownerId ~= myUserId then
                            local isAdmin = false
                            if extra.admin then
                                for _, admId in ipairs(extra.admin) do
                                    if tonumber(admId) == myUserId then isAdmin = true; break end
                                end
                            end
                            if not isAdmin then isForeign = true end
                        end
                    end

                    if isForeign then
                        foreignLockCount = foreignLockCount + 1
                        local radius = 4 -- Small Lock (fg == 202)
                        if fg == 204 then
                            radius = 7 -- Big Lock
                        elseif fg == 206 or fg == 4994 then
                            radius = 15 -- Huge / Builder's Lock
                        end

                        local minX = math.max(0, x - radius)
                        local maxX = math.min(99, x + radius)
                        local minY = math.max(0, y - radius)
                        local maxY = math.min(53, y + radius)
                        for cy = minY, maxY do
                            for cx = minX, maxX do
                                local dist = math.abs(cx - x) + math.abs(cy - y)
                                if dist <= (radius + 1) then
                                    local k = cx .. "_" .. cy
                                    if not STATE.foreign_locked_tiles[k] then
                                        STATE.foreign_locked_tiles[k] = true
                                        lockedTileCount = lockedTileCount + 1
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if foreignLockCount > 0 then
        addLog(string.format("`e[Lock Orang Lain] `wTerdeteksi %d lock milik orang lain (%d petak diamankan). Bot tidak akan memaksa plant di sana!", foreignLockCount, lockedTileCount))
    end
    return foreignLockCount, lockedTileCount
end

local function getTilePlantStatus(tx, ty)
    if tx < 0 or tx > 99 or ty < 0 or ty > 53 then return "INVALID" end
    local k = tx .. "_" .. ty
    if STATE.blocked_tiles and STATE.blocked_tiles[k] then return "INVALID" end
    if STATE.foreign_locked_tiles and STATE.foreign_locked_tiles[k] then return "INVALID" end

    local tBelow = getTileSafe(tx, ty + 1)
    if not isSupportTile(tBelow) then return "INVALID" end

    local tAt = getTileSafe(tx, ty)
    if isPermanentObstacle(tAt) then return "INVALID" end

    local fgAt = tonumber(tAt and tAt.fg) or 0
    local s1 = tonumber(CFG.seed_1_id) or 0
    local s2 = tonumber(CFG.seed_2_id) or 0

    if not CFG.splice_mode or s2 <= 0 or s1 <= 0 or s1 == s2 then
        -- Mode single seed biasa
        if fgAt == 0 then
            return "EMPTY"
        else
            return "DONE"
        end
    end

    -- Mode Splice (2 Seed):
    if fgAt == 0 then
        -- Petak kosong: siap ditanam Seed 1 & Seed 2
        return "EMPTY"
    end

    -- Jika petak memiliki fg == s1 (Seed 1)
    if fgAt == s1 then
        -- Jika pohon sudah berbuah / siap panen, jangan ditimpa
        if isTileTree(tAt) then
            return "DONE"
        end
        -- Bibit Seed 1 belum jadi pohon berbuah (baik baru ditanam maupun sudah ada di world):
        -- Validasi: WAJIB DICOBA SPLICE (timpa Seed 2)!
        return "NEEDS_SPLICE_2"
    end

    -- Jika petak memiliki fg == s2 (Seed 2)
    if fgAt == s2 then
        if isTileTree(tAt) then
            return "DONE"
        end
        -- Bibit Seed 2 belum jadi pohon berbuah: WAJIB DICOBA SPLICE (timpa Seed 1)!
        return "NEEDS_SPLICE_1"
    end

    -- fgAt sudah bukan 0, bukan s1, dan bukan s2.
    -- Berarti pohon hasil splice sudah terbentuk (atau platform/block lain)!
    return "DONE"
end

local function isTilePlantable(tx, ty)
    local k = tx .. "_" .. ty
    if STATE.blocked_tiles and STATE.blocked_tiles[k] then return false end
    if STATE.foreign_locked_tiles and STATE.foreign_locked_tiles[k] then return false end
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

local function isTilePlanted(tx, ty)
    if tx < 0 or tx > 99 or ty < 0 or ty > 53 then return false end
    local tBelow = getTileSafe(tx, ty + 1)
    if not isSupportTile(tBelow) then return false end

    local tAt = getTileSafe(tx, ty)
    if not tAt or isPermanentObstacle(tAt) then return false end
    local fgAt = tonumber(tAt.fg) or 0
    if fgAt <= 0 then return false end

    local s1 = tonumber(CFG.seed_1_id) or 0
    local s2 = tonumber(CFG.seed_2_id) or 0

    if CFG.splice_mode and s2 > 0 and s1 > 0 and s1 ~= s2 then
        local st = getTilePlantStatus(tx, ty)
        if st == "DONE" then return true end
        if fgAt == s1 or fgAt == s2 then return true end
        if isTileTree(tAt) or (fgAt % 2 == 1) then return true end
        return false
    end

    if s1 > 0 and fgAt == s1 then return true end
    if isTileTree(tAt) then return true end
    if fgAt % 2 == 1 then return true end
    return false
end

-- ============================================================================
-- PENDETEKSI CERDAS: CARI SEED TERAKHIR & TENTUKAN ARAH TANAM SECARA OTOMATIS
-- Menghilangkan keharusan bot pergi ke ujung 0 atau 98 dahulu sebelum menanam!
-- ============================================================================
local function findRowPlantPlan(plantY, curPx)
    if plantY < 0 or plantY > 53 then return nil, nil, nil, 0 end

    local planted = {}
    local plantable = {}
    local plantableSet = {}

    for x = 0, 99 do
        if isTilePlantable(x, plantY) then
            table.insert(plantable, x)
            plantableSet[x] = true
        elseif isTilePlanted(x, plantY) then
            table.insert(planted, x)
        end
    end

    if #plantable == 0 then
        return nil, nil, nil, 0
    end

    curPx = tonumber(curPx) or 0

    -- 1. Jika baris benar-benar fresh (0 seed tertanam di baris ini)
    if #planted == 0 then
        if curPx >= 50 then
            return false, plantable[#plantable], nil, #plantable
        else
            return true, plantable[1], nil, #plantable
        end
    end

    local minPlanted = planted[1]
    local maxPlanted = planted[#planted]

    -- Kumpulkan petak kosong di sisi kanan seed terakhir (x > maxPlanted)
    local rightPlantable = {}
    for _, px in ipairs(plantable) do
        if px > maxPlanted then
            table.insert(rightPlantable, px)
        end
    end

    -- Kumpulkan petak kosong di sisi kiri seed pertama (x < minPlanted)
    local leftPlantable = {}
    for _, px in ipairs(plantable) do
        if px < minPlanted then
            table.insert(leftPlantable, px)
        end
    end

    -- 2. KASUS A: Mayoritas sisa petak kosong ada di sisi kanan seed terakhir
    -- (Pola penanaman alami Kiri -> Kanan)
    if #rightPlantable > 0 and #rightPlantable >= #leftPlantable then
        return true, rightPlantable[1], maxPlanted, #plantable
    end

    -- 3. KASUS B: Mayoritas sisa petak kosong ada di sisi kiri seed pertama
    -- (Pola penanaman alami Kanan -> Kiri)
    if #leftPlantable > 0 and #leftPlantable > #rightPlantable then
        return false, leftPlantable[#leftPlantable], minPlanted, #plantable
    end

    -- 4. KASUS C: Titik batas transisi (boundary) terdekat dengan posisi bot
    local bestDist = 9999
    local bestDir = true
    local bestStartX = plantable[1]
    local bestLastSeed = planted[1]

    for _, p in ipairs(planted) do
        -- Transisi: p (seed) -> p + 1 (kosong) => arah KANAN
        if plantableSet[p + 1] then
            local dist = math.abs((p + 1) - curPx)
            if dist < bestDist then
                bestDist = dist
                bestDir = true
                bestStartX = p + 1
                bestLastSeed = p
            end
        end
        -- Transisi: p - 1 (kosong) <- p (seed) => arah KIRI
        if plantableSet[p - 1] then
            local dist = math.abs((p - 1) - curPx)
            if dist < bestDist then
                bestDist = dist
                bestDir = false
                bestStartX = p - 1
                bestLastSeed = p
            end
        end
    end

    if bestDist < 9999 then
        return bestDir, bestStartX, bestLastSeed, #plantable
    end

    -- Fallback: pilih sisi yang lebih dekat dengan posisi bot saat ini
    if curPx >= 50 then
        return false, plantable[#plantable], maxPlanted, #plantable
    else
        return true, plantable[1], minPlanted, #plantable
    end
end

local function moveSafeTo(tx, ty)
    if not STATE.running then return false end
    tx = math.max(0, math.min(99, math.floor(tx or 0)))
    ty = math.max(0, math.min(53, math.floor(ty or 0)))

    local curPx, curPy = getPlayerTilePos()
    if curPx and curPy and math.abs(curPx - tx) <= 1 and math.abs(curPy - ty) <= 1 then
        return true
    end

    -- Jika target adalah tile padat (misal seed di atas block solid), arahkan ke petak aman terdekat
    local sx, sy = tx, ty
    local t = getTileSafe(tx, ty)
    if t and t.collidable then
        local tUp = getTileSafe(tx, ty - 1)
        local tLeft = getTileSafe(tx - 1, ty)
        local tRight = getTileSafe(tx + 1, ty)
        local tDown = getTileSafe(tx, ty + 1)
        if tUp and not tUp.collidable then
            sx, sy = tx, ty - 1
        elseif tLeft and not tLeft.collidable then
            sx, sy = tx - 1, ty
        elseif tRight and not tRight.collidable then
            sx, sy = tx + 1, ty
        elseif tDown and not tDown.collidable then
            sx, sy = tx, ty + 1
        end
    end

    local pFn = FindPath or findPath
    if not pFn then return false end

    -- Pastikan cheat ModFly aktif jika di-enable agar bot bisa bergerak bebas antar lantai
    if CFG.use_modfly and editToggle then
        pcall(editToggle, "ModFly", true)
    end

    local startPx, startPy = getPlayerTilePos()
    local totalDist = math.max(math.abs((startPx or 0) - sx), math.abs((startPy or 0) - sy))

    -- JALUR 1: Jika jarak DEKAT (<= 3 blok, khas langkah tanam 3-zigzag)
    if totalDist <= 3 then
        pcall(pFn, sx, sy)
        local maxWait = math.max(160, (tonumber(CFG.step_delay) or 110) * 3)
        local waited = 0
        while waited < maxWait and STATE.running do
            while STATE.paused do safeSleep(200) if not STATE.running then return false end end
            local px, py = getPlayerTilePos()
            if px and py and math.abs(px - sx) <= 1 and math.abs(py - sy) <= 1 then
                safeSleep(CFG.step_delay or 40)
                return true
            end
            safeSleep(25)
            waited = waited + 25
        end
        local fPx, fPy = getPlayerTilePos()
        return (fPx and fPy and math.abs(fPx - sx) <= 1 and math.abs(fPy - sy) <= 1)
    end

    -- JALUR 2: Jika jarak JAUH (berpindah dari pintu ke baris tanaman, atau antar baris)
    -- Growlauncher FindPath menangani kalkulasi rute platform & tangga secara otomatis.
    pcall(pFn, sx, sy)

    -- Batas waktu wajar berdasarkan jarak (misal 70 blok butuh waktu ~12-18 detik)
    local maxWaitFar = math.max(3000, math.min(25000, totalDist * 250))
    local waitedFar = 0
    local lastPx, lastPy = startPx, startPy
    local stuckTicks = 0

    while waitedFar < maxWaitFar and STATE.running do
        while STATE.paused do safeSleep(300) if not STATE.running then return false end end
        safeSleep(70)
        waitedFar = waitedFar + 70

        local nx, ny = getPlayerTilePos()
        if nx and ny then
            -- Apakah bot sudah tiba di tujuan atau bersebelahan (toleransi 1 blok)?
            if math.abs(nx - sx) <= 1 and math.abs(ny - sy) <= 1 then
                safeSleep(CFG.step_delay or 60)
                return true
            end

            -- Evaluasi apakah bot sedang berjalan maju atau benar-benar diam/macet
            if nx == lastPx and ny == lastPy then
                stuckTicks = stuckTicks + 1
                -- Jika diam selama 1.4 detik (20 ticks), panggil ulang FindPath sekali
                if stuckTicks == 20 then
                    pcall(pFn, sx, sy)
                elseif stuckTicks >= 40 then
                    -- Bot terhenti total selama hampir 3 detik tanpa pergerakan
                    break
                end
            else
                stuckTicks = 0
                lastPx, lastPy = nx, ny
            end
        end
    end

    local finalX, finalY = getPlayerTilePos()
    if finalX and finalY and math.abs(finalX - sx) <= 1 and math.abs(finalY - sy) <= 1 then
        return true
    end

    return false
end

local function isWorldProperlyLoaded(expectedWorld)
    local curW = getCurrentWorldSafe()
    if curW == "" or curW == "EXIT" then return false end
    if expectedWorld and expectedWorld ~= "" and curW ~= expectedWorld:upper() then return false end

    -- Cek ketersediaan tile map (bukan nil atau kosong total)
    local hasAnyTile = false
    for checkY = 0, 59, 10 do
        local t = getTileSafe(50, checkY)
        if t and ((t.fg and t.fg > 0) or (t.bg and t.bg > 0)) then
            hasAnyTile = true
            break
        end
    end
    if not hasAnyTile then
        -- Cek dasar world (bedrock Y=54..59)
        for checkY = 54, 59 do
            local t = getTileSafe(1, checkY)
            if t and (t.fg and t.fg > 0) then
                hasAnyTile = true
                break
            end
        end
    end
    return hasAnyTile
end

local function waitForWorldLoaded(timeoutMs, expectedWorld)
    timeoutMs = timeoutMs or 3500
    local elapsed = 0
    while elapsed < timeoutMs do
        if not STATE.running then return false end
        if isWorldProperlyLoaded(expectedWorld) then
            return true
        end
        safeSleep(200)
        elapsed = elapsed + 200
    end
    return isWorldProperlyLoaded(expectedWorld)
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

local function sendRawAction(tx, ty, value)
    if not sendPacketRaw then return false end
    value = tonumber(value) or 18

    local okP, p = pcall(getLocal)
    local px = (okP and p and (p.posX or (p.pos and p.pos.x))) or (tx * 32)
    local py = (okP and p and (p.posY or (p.pos and p.pos.y))) or (ty * 32)
    local state = (px > (tx * 32)) and 48 or 32

    local ok = pcall(sendPacketRaw, false, {
        type  = 3,
        value = value,
        px    = tx,
        py    = ty,
        x     = px,
        y     = py,
        state = state,
    })
    return ok
end

local function punchTile(tx, ty)
    return sendRawAction(tx, ty, 18)
end

local function clearFailedSpliceTile(tx, ty)
    if not STATE.running then return false end
    local k = tx .. "_" .. ty
    if STATE.blocked_tiles and STATE.blocked_tiles[k] then return false end
    if STATE.foreign_locked_tiles and STATE.foreign_locked_tiles[k] then return false end
    local s1 = CFG.seed_1_id
    local s2 = CFG.seed_2_id

    for punchCount = 1, 4 do
        if not STATE.running then return false end
        punchTile(tx, ty)
        safeSleep(150)
        local t = getTileSafe(tx, ty)
        local fgNow = tonumber(t and t.fg) or 0
        if fgNow == 0 then
            return true -- Berhasil dihancurkan dan petak kosong!
        end
        if fgNow ~= s1 and fgNow ~= s2 then
            return true -- Berubah jadi item lain / pohon
        end
    end
    return false
end

local function plantAndSpliceTile(tx, ty)
    if not STATE.running then return false end
    local k = tx .. "_" .. ty
    if STATE.blocked_tiles and STATE.blocked_tiles[k] then return true end
    if STATE.foreign_locked_tiles and STATE.foreign_locked_tiles[k] then return true end
    local st = getTilePlantStatus(tx, ty)
    if st == "DONE" or st == "INVALID" then return true end

    local s1 = CFG.seed_1_id
    local s2 = CFG.seed_2_id

    local isSplice = (CFG.splice_mode and s2 and s2 > 0 and s1 > 0 and s1 ~= s2)

    local delayPlant = tonumber(CFG.plant_delay) or 180
    local delaySplice = tonumber(CFG.splice_delay) or 180

    if not isSplice then
        if st == "EMPTY" then
            sendPlantPacket(tx, ty, s1)
            safeSleep(delayPlant)
        end
        return true
    end

    -- =========================================================================
    -- MODE SPLICE 1 PETAK (DENGAN MULTI-RETRY & AUTO-RECOVERY PUNCH)
    -- =========================================================================
    local maxSpliceAttempts = 3
    for attempt = 1, maxSpliceAttempts do
        if not STATE.running then return false end
        while STATE.paused do safeSleep(500) if not STATE.running then return false end end

        local curSt = getTilePlantStatus(tx, ty)
        if curSt == "DONE" then
            return true
        end

        if curSt == "EMPTY" then
            sendPlantPacket(tx, ty, s1)
            safeSleep(delaySplice)
            sendPlantPacket(tx, ty, s2)
            safeSleep(delayPlant)
        elseif curSt == "NEEDS_SPLICE_2" then
            sendPlantPacket(tx, ty, s2)
            safeSleep(delayPlant)
        elseif curSt == "NEEDS_SPLICE_1" then
            sendPlantPacket(tx, ty, s1)
            safeSleep(delayPlant)
        end

        -- Verifikasi hasil: apakah splice berhasil (fg bukan 0, bukan s1, dan bukan s2)
        local confirmed = false
        for _ = 1, 3 do
            safeSleep(50)
            local tCheck = getTileSafe(tx, ty)
            local fgNow = tonumber(tCheck and tCheck.fg) or 0
            if fgNow ~= 0 and fgNow ~= s1 and fgNow ~= s2 then
                confirmed = true
                break
            end
        end

        if confirmed then
            return true
        end

        safeSleep(80)
    end

    -- Jika setelah 3 percobaan masih gagal (karena sudah bertunas/sprouted un-spliced)
    if CFG.auto_clear_failed_splice ~= false then
        local lastSt = getTilePlantStatus(tx, ty)
        if lastSt == "NEEDS_SPLICE_2" or lastSt == "NEEDS_SPLICE_1" then
            addLog(string.format("[Splice Recovery] Mereset semak bertunas gagal splice di (%d, %d)...", tx, ty))
            local cleared = clearFailedSpliceTile(tx, ty)
            if cleared then
                safeSleep(100)
                sendPlantPacket(tx, ty, s1)
                safeSleep(delaySplice)
                sendPlantPacket(tx, ty, s2)
                safeSleep(delayPlant)
                return true
            end
        end
    end

    return true
end

local function plantSingleSpot(tx, ty)
    if not STATE.running then return false end
    local curPx, curPy = getPlayerTilePos()
    if math.abs(curPx - tx) > 1 or math.abs(curPy - ty) > 1 then
        moveSafeTo(tx, ty)
    end
    return plantAndSpliceTile(tx, ty)
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

local function plantTileSection(spotList, plantY)
    if not STATE.running or not spotList or #spotList == 0 then return true end

    local s1 = CFG.seed_1_id
    local s2 = CFG.seed_2_id
    local isSplice = (CFG.splice_mode and s2 and s2 > 0 and s1 > 0 and s1 ~= s2)
    local delayPlant = tonumber(CFG.plant_delay) or 180
    local delaySplice = tonumber(CFG.splice_delay) or 180

    local failCounts = STATE.plant_fail_count or {}
    STATE.plant_fail_count = failCounts
    local blocked = STATE.blocked_tiles or {}
    STATE.blocked_tiles = blocked

    -- -------------------------------------------------------------------------
    -- A. SINGLE SEED MODE
    -- -------------------------------------------------------------------------
    if not isSplice then
        for _, sx in ipairs(spotList) do
            if not STATE.running then break end
            while STATE.paused do safeSleep(500) if not STATE.running then break end end
            local k = sx .. "_" .. plantY
            if not blocked[k] and getTilePlantStatus(sx, plantY) == "EMPTY" then
                sendPlantPacket(sx, plantY, s1)
                safeSleep(delayPlant)
            end
        end

        -- Verifikasi konfirmasi: Beri toleransi latency server sebelum menganggap SL terkunci
        safeSleep(60)
        for retry = 1, 3 do
            local needRetry = false
            for _, sx in ipairs(spotList) do
                local k = sx .. "_" .. plantY
                if not blocked[k] and getTilePlantStatus(sx, plantY) == "EMPTY" then
                    needRetry = true
                    sendPlantPacket(sx, plantY, s1)
                    safeSleep(delayPlant)
                    local tNow = getTileSafe(sx, plantY)
                    local curPx, curPy = getPlayerTilePos()
                    local isNear = curPx and curPy and math.abs(curPx - sx) <= 2 and math.abs(curPy - plantY) <= 2
                    if isNear and tNow and tonumber(tNow.fg) == 0 and hasEnoughSeedInBackpack() then
                        failCounts[k] = (failCounts[k] or 0) + 1
                        -- Wajib gagal berturut-turut minimal 4 kali (konfirmasi network nyata) sebelum mem-blacklist tile
                        if failCounts[k] >= 4 then
                            blocked[k] = true
                            addLog(string.format("`4[Area Lock Terdeteksi] `wPetak (%d, %d) tidak bisa ditanam (SL orang lain/terkunci). Dilewati!", sx, plantY))
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

    -- -------------------------------------------------------------------------
    -- B. BATCH SECTION SPLICING (3-Petak Sekaligus Bebas Cooldown Server)
    -- -------------------------------------------------------------------------
    -- TAHAP 1: Pasang Seed 1 pada semua petak EMPTY dalam seksi
    local plantedS1 = {}
    for _, sx in ipairs(spotList) do
        if not STATE.running then break end
        while STATE.paused do safeSleep(500) if not STATE.running then break end end
        local k = sx .. "_" .. plantY
        if not blocked[k] then
            local st = getTilePlantStatus(sx, plantY)
            if st == "EMPTY" then
                sendPlantPacket(sx, plantY, s1)
                plantedS1[sx] = true
                safeSleep(delayPlant)
            end
        end
    end

    -- TAHAP 2: Jeda Cooldown Server Growtopia (> 200ms per-tile)
    safeSleep(delaySplice)

    -- TAHAP 3: Pasang Seed 2 untuk menimpa Seed 1 (Splice Execution)
    for _, sx in ipairs(spotList) do
        if not STATE.running then break end
        while STATE.paused do safeSleep(500) if not STATE.running then break end end
        local k = sx .. "_" .. plantY
        if not blocked[k] then
            local st = getTilePlantStatus(sx, plantY)
            if plantedS1[sx] or st == "NEEDS_SPLICE_2" or st == "EMPTY" then
                sendPlantPacket(sx, plantY, s2)
                safeSleep(delayPlant)
            elseif st == "NEEDS_SPLICE_1" then
                sendPlantPacket(sx, plantY, s1)
                safeSleep(delayPlant)
            end
        end
    end

    -- TAHAP 4: Verifikasi Langsung di Tempat Sebelum Bot Melangkah
    safeSleep(140)
    for retry = 1, 3 do
        if not STATE.running then break end
        local allDone = true
        for _, sx in ipairs(spotList) do
            local k = sx .. "_" .. plantY
            if not blocked[k] then
                local st = getTilePlantStatus(sx, plantY)
                if st == "NEEDS_SPLICE_2" then
                    allDone = false
                    sendPlantPacket(sx, plantY, s2)
                    safeSleep(delayPlant)
                elseif st == "NEEDS_SPLICE_1" then
                    allDone = false
                    sendPlantPacket(sx, plantY, s1)
                    safeSleep(delayPlant)
                elseif st == "EMPTY" then
                    allDone = false
                    sendPlantPacket(sx, plantY, s1)
                    safeSleep(delaySplice)
                    sendPlantPacket(sx, plantY, s2)
                    safeSleep(delayPlant)
                    local tNow = getTileSafe(sx, plantY)
                    local curPx, curPy = getPlayerTilePos()
                    local isNear = curPx and curPy and math.abs(curPx - sx) <= 2 and math.abs(curPy - plantY) <= 2
                    if isNear and tNow and tonumber(tNow.fg) == 0 and hasEnoughSeedInBackpack() then
                        failCounts[k] = (failCounts[k] or 0) + 1
                        if failCounts[k] >= 4 then
                            blocked[k] = true
                            addLog(string.format("`4[Area Lock Terdeteksi] `wPetak (%d, %d) tidak bisa ditanam (SL orang lain/terkunci). Dilewati!", sx, plantY))
                        end
                    else
                        failCounts[k] = 0
                    end
                end
            end
        end
        if allDone then break end
        safeSleep(120)
    end

    -- TAHAP 5: Auto-Recovery untuk Bibit yang Terlewat & Sudah Bertunas (Punch & Replant)
    if CFG.auto_clear_failed_splice ~= false then
        for _, sx in ipairs(spotList) do
            if not STATE.running then break end
            local k = sx .. "_" .. plantY
            if not blocked[k] then
                local st = getTilePlantStatus(sx, plantY)
                if st == "NEEDS_SPLICE_2" or st == "NEEDS_SPLICE_1" then
                    addLog(string.format("[Splice Recovery] Mendeteksi semak bertunas gagal splice di (%d, %d). Mereset...", sx, plantY))
                    local cleared = clearFailedSpliceTile(sx, plantY)
                    if cleared then
                        safeSleep(100)
                        sendPlantPacket(sx, plantY, s1)
                        safeSleep(delaySplice)
                        sendPlantPacket(sx, plantY, s2)
                        safeSleep(delayPlant)
                    end
                end
            end
        end
    end

    return true
end

-- ============================================================================
-- 13. SEED STORAGE RESTOCK & AUTO-SKIP EMPTY STORAGE
-- ============================================================================
local function getUnifiedWorldObjects()
    local getFn = getObjectList or getObjects or getWorldObjects
    if not getFn then return {} end
    local ok, objs = pcall(getFn)
    if not ok or not objs then return {} end

    local container = objs
    pcall(function()
        if type(objs) == "table" and objs.objects then
            container = objs.objects
        end
    end)

    local results = {}
    local function parseObj(o)
        if not o then return end
        local t = type(o)
        if t ~= "table" and t ~= "userdata" then return end

        local itemID, uid, amt, rx, ry = nil, nil, nil, nil, nil
        pcall(function() itemID = tonumber(o.itemid or o.itemId or o.item_id or o.itemID) end)
        pcall(function() uid = tonumber(o.id or o.oid or o.uid or o.objID or o.netid) end)
        pcall(function() amt = tonumber(o.amount or o.count or o.cnt or 1) or 1 end)
        pcall(function()
            if o.pos then
                rx = tonumber(o.pos.x or o.pos[1])
                ry = tonumber(o.pos.y or o.pos[2])
            end
        end)
        if not rx then pcall(function() rx = tonumber(o.x or o.posX) end) end
        if not ry then pcall(function() ry = tonumber(o.y or o.posY) end) end

        if itemID and uid and rx and ry then
            results[#results + 1] = {
                id      = uid,
                itemid  = itemID,
                amount  = amt,
                x       = rx,
                y       = ry,
                tileX   = math.floor((rx + 10) / 32),
                tileY   = math.floor((ry + 10) / 32),
                raw     = o,
            }
        end
    end

    -- 1. Coba iterasi standar pairs
    pcall(function()
        for _, o in pairs(container) do
            parseObj(o)
        end
    end)

    -- 2. Jika pairs kosong / userdata array tanpa metamethod __pairs
    if #results == 0 then
        local len = 0
        pcall(function() len = #container end)
        if not len or len <= 0 then
            pcall(function() len = container:size() end)
        end
        if not len or len <= 0 then
            pcall(function() len = container.count or container.length end)
        end
        local maxN = (len and tonumber(len) and tonumber(len) > 0) and tonumber(len) or 1000
        local consecutiveNil = 0
        for i = 0, maxN do
            local itemOk, o = pcall(function() return container[i] end)
            if itemOk and o then
                parseObj(o)
                consecutiveNil = 0
            else
                consecutiveNil = consecutiveNil + 1
                if consecutiveNil >= 30 and i > 5 then break end
            end
        end
    end

    return results
end
_G.getUnifiedWorldObjects = getUnifiedWorldObjects

local function isMatchingSeedID(floatingItemID, targetSeedID)
    floatingItemID = tonumber(floatingItemID) or 0
    targetSeedID = tonumber(targetSeedID) or 0
    if floatingItemID <= 0 or targetSeedID <= 0 then return false end

    -- 1. Cocok persis
    if floatingItemID == targetSeedID then return true end

    -- 2. Normalisasi via ensureSeedID
    local normFloat = ensureSeedID(floatingItemID)
    local normTarget = ensureSeedID(targetSeedID)
    if normFloat > 0 and normTarget > 0 and normFloat == normTarget then
        return true
    end

    -- 3. Selisih 1 (Block <-> Seed di Growtopia)
    if math.abs(floatingItemID - targetSeedID) == 1 then
        return true
    end

    -- 4. BOREN_ITEM_DB resolusi ganda
    if BOREN_ITEM_DB and BOREN_ITEM_DB.loaded then
        local sFloat, _ = BOREN_ITEM_DB:resolveSeedID(floatingItemID)
        local sTarget, _ = BOREN_ITEM_DB:resolveSeedID(targetSeedID)
        if sFloat > 0 and sTarget > 0 and sFloat == sTarget then
            return true
        end
    end

    return false
end
_G.isMatchingSeedID = isMatchingSeedID

local function collectFloatingSeedsInStorage(targetSeedID, targetAmount)
    targetSeedID = math.floor(tonumber(targetSeedID) or 0)
    if targetSeedID <= 0 then return 0 end

    local normTarget = ensureSeedID(targetSeedID)
    local curBP = math.max(getInvCount(targetSeedID), getInvCount(normTarget))
    local needed = math.max(0, targetAmount - curBP)
    if needed <= 0 then return 0 end

    local allObjs = getUnifiedWorldObjects()
    if #allObjs == 0 then
        addLog(string.format("[Storage] Tidak ada objek floating di world saat ini (#objs = 0)."))
        return 0
    end

    local collected = 0
    local matchedCount = 0

    for _, obj in ipairs(allObjs) do
        if not STATE.running then break end
        if isMatchingSeedID(obj.itemid, targetSeedID) then
            matchedCount = matchedCount + 1
            local ox = obj.tileX
            local oy = obj.tileY

            addLog(string.format("[Storage] Menemukan floating seed (ID: %d, UID: %d, Jml: %d) di tile (%d, %d). Menghampiri...",
                obj.itemid, obj.id, obj.amount, ox, oy))
            moveSafeTo(ox, oy)
            safeSleep(100)

            -- Ambil objek via packet 11 (Collect Object)
            if sendPacketRaw then
                pcall(sendPacketRaw, false, {
                    type  = 11,
                    value = obj.id,
                    x     = obj.x,
                    y     = obj.y,
                })
            end
            safeSleep(180)
            collected = collected + obj.amount
            syncInventoryCache()

            local nowBP = math.max(getInvCount(targetSeedID), getInvCount(normTarget))
            if nowBP >= targetAmount then
                addLog(string.format("[Storage] Target seed tercapai di tas: %d/%d", nowBP, targetAmount))
                break
            end
        end
    end

    if matchedCount == 0 then
        addLog(string.format("[Storage] Tidak menemukan seed ID %d (atau norm ID %d) di antara %d objek floating.",
            targetSeedID, normTarget, #allObjs))
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
                local objs = getUnifiedWorldObjects()
                if #objs > 0 then break end
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
            local normS1 = ensureSeedID(CFG.seed_1_id)
            local normS2 = ensureSeedID(CFG.seed_2_id)
            local bp1 = math.max(getInvCount(CFG.seed_1_id), getInvCount(normS1))
            local bp2 = CFG.splice_mode and math.max(getInvCount(CFG.seed_2_id), getInvCount(normS2)) or 999
            local hasSeedNow = (not CFG.splice_mode and (bp1 > 0 or c1 > 0))
                            or (CFG.splice_mode and (bp1 > 0 or c1 > 0) and (bp2 > 0 or c2 > 0))

            if not hasSeedNow then
                for _ = 1, 5 do
                    safeSleep(200)
                    syncInventoryCache()
                    bp1 = math.max(getInvCount(CFG.seed_1_id), getInvCount(normS1))
                    bp2 = CFG.splice_mode and math.max(getInvCount(CFG.seed_2_id), getInvCount(normS2)) or 999
                    if (not CFG.splice_mode and bp1 > 0) or (CFG.splice_mode and bp1 > 0 and bp2 > 0) then
                        hasSeedNow = true
                        break
                    end
                end
            else
                safeSleep(300)
                syncInventoryCache()
                bp1 = math.max(getInvCount(CFG.seed_1_id), getInvCount(normS1))
                if CFG.splice_mode then bp2 = math.max(getInvCount(CFG.seed_2_id), getInvCount(normS2)) end
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
-- 13.5. RETURN DIALOG & DROP SISA SEED KE WORLD STORAGE
-- ============================================================================
local function trimStr(s)
    if type(s) ~= "string" then return "" end
    return s:match("^%s*(.-)%s*$") or ""
end

local function buildDropDialogReturn(dlgText, fallbackItemID, dropAmt)
    local dName = "drop_item"
    local embedLines = {}
    local hasItemEmbed = false
    local countField = "count"
    local foundInput = false

    if type(dlgText) == "string" and dlgText ~= "" then
        for line in dlgText:gmatch("[^\r\n]+") do
            local parts = {}
            for part in (line .. "|"):gmatch("([^|]*)|") do
                parts[#parts + 1] = part
            end
            local cmd = parts[1]
            if cmd == "end_dialog" and parts[2] and parts[2] ~= "" then
                dName = trimStr(parts[2])
            elseif cmd == "embed_data" and parts[2] and parts[2] ~= "" then
                local ek = trimStr(parts[2])
                local ev = trimStr(parts[3] or "")
                if ek:lower() == "itemid" or ek:lower() == "item_id" then hasItemEmbed = true end
                embedLines[#embedLines + 1] = ek .. "|" .. ev .. "|"
            elseif cmd == "add_text_input" and parts[2] and parts[2] ~= "" and (not foundInput) then
                countField = trimStr(parts[2])
                foundInput = true
            end
        end
    end

    local lines = {
        "action|dialog_return",
        "dialog_name|" .. dName,
    }
    for _, el in ipairs(embedLines) do
        lines[#lines + 1] = el
    end
    if not hasItemEmbed then
        lines[#lines + 1] = "itemID|" .. tostring(fallbackItemID) .. "|"
    end
    lines[#lines + 1] = countField .. "|" .. tostring(dropAmt)
    return table.concat(lines, "\n") .. "\n"
end

local function waitInvDropTo(itemID, targetMax, maxWaitMs)
    local waited = 0
    local lim = maxWaitMs or 900
    while waited < lim and STATE.running do
        safeSleep(80)
        waited = waited + 80
        syncInventoryCache()
        if getInvCount(itemID) <= targetMax then
            return true
        end
    end
    return (getInvCount(itemID) <= targetMax)
end

local function dropSingleSeedToStorage(itemID, dropAmt, label)
    itemID = math.floor(tonumber(itemID) or 0)
    dropAmt = math.floor(tonumber(dropAmt) or 0)
    if itemID <= 0 or dropAmt <= 0 then return true end

    local initialCur = getInvCount(itemID)
    if initialCur <= 0 then return true end
    local targetAfter = math.max(0, initialCur - dropAmt)

    for round = 1, 10 do
        if not STATE.running then return false end
        syncInventoryCache()
        local cur = getInvCount(itemID)
        if cur <= targetAfter then return true end

        local excess = cur - targetAfter
        local batchAmt = math.min(200, excess)

        local okDropped = false
        for attempt = 1, 3 do
            if not STATE.running then return false end
            syncInventoryCache()
            cur = getInvCount(itemID)
            if cur <= targetAfter then return true end
            excess = cur - targetAfter
            batchAmt = math.min(200, excess)

            if attempt > 1 or round > 1 then
                local px, py = getPlayerTilePos()
                if px and py then
                    local shift = ((attempt + round) % 2 == 0) and 2 or -2
                    local nx = math.max(2, math.min(97, px + shift))
                    moveSafeTo(nx, py)
                    safeSleep(200)
                end
            end

            STATE.pending_drop_id  = itemID
            STATE.pending_drop_amt = batchAmt
            STATE.drop_confirmed   = false
            setStatus("Drop Seed", string.format("Drop %s (%d)...", tostring(label or itemID), batchAmt))
            addLog(string.format("[Drop Seed R%d-#%d] %s (ID %d): drop %d (tas %d -> target sisa %d)",
                round, attempt, tostring(label or itemID), itemID, batchAmt, cur, targetAfter))

            -- Metode 1: API Native confirmDropItem
            if growtopia and growtopia.confirmDropItem then
                pcall(growtopia.confirmDropItem, itemID, batchAmt)
                okDropped = waitInvDropTo(itemID, cur - 1, 850)
            end

            -- Metode 2: Packet standar action|drop -> ditangkap OnDialogRequest oleh hook onvariant
            if (not okDropped) and STATE.running and sendPacket then
                STATE.drop_confirmed = false
                pcall(sendPacket, 2, "action|drop\n|itemID|" .. tostring(itemID))
                okDropped = waitInvDropTo(itemID, cur - 1, 950)
            end

            -- Metode 3: API Native growtopia.dropItem
            if (not okDropped) and STATE.running and growtopia and growtopia.dropItem then
                STATE.drop_confirmed = false
                pcall(growtopia.dropItem, itemID)
                okDropped = waitInvDropTo(itemID, cur - 1, 850)
            end

            -- Metode 4: Direct dialog_return untuk 'drop' & 'drop_item'
            if (not okDropped) and STATE.running and sendPacket then
                for _, dlgName in ipairs({ "drop", "drop_item" }) do
                    if not STATE.running then break end
                    local remNow = math.min(200, getInvCount(itemID) - targetAfter)
                    if remNow <= 0 then okDropped = true; break end
                    pcall(sendPacket, 2, string.format(
                        "action|dialog_return\ndialog_name|%s\nitemID|%d|\ncount|%d\n",
                        dlgName, itemID, remNow
                    ))
                    if waitInvDropTo(itemID, cur - 1, 750) then
                        okDropped = true
                        break
                    end
                end
            end

            STATE.pending_drop_id  = 0
            STATE.pending_drop_amt = 0

            if okDropped or getInvCount(itemID) < cur then
                break
            end
            safeSleep(200)
        end

        safeSleep(300)
    end

    return (getInvCount(itemID) <= targetAfter)
end

local function dropLeftoverSeedsToStorage(specificSeed1, specificSeed2)
    if #CFG.storage_world_list == 0 then
        addLog("[Drop Sisa Seed] Daftar World Storage kosong, sisa seed dibiarkan di tas.")
        return true
    end

    syncInventoryCache()
    local s1 = tonumber(specificSeed1 or CFG.seed_1_id) or 0
    local s2 = tonumber(specificSeed2 or CFG.seed_2_id) or 0

    local seedsToDrop = {}
    if s1 > 0 and getInvCount(s1) > 0 then
        table.insert(seedsToDrop, { id = s1, count = getInvCount(s1) })
    end
    if s2 > 0 and s2 ~= s1 and getInvCount(s2) > 0 then
        table.insert(seedsToDrop, { id = s2, count = getInvCount(s2) })
    end

    if #seedsToDrop == 0 then return true end

    local storEntry = CFG.storage_world_list[1]
    local storName = storEntry.name
    local storDoor = storEntry.door or ""

    setStatus("Drop Sisa Seed", string.format("Warp ke Storage: %s...", storName))
    addLog(string.format("[Plant Selesai] Menyimpan sisa seed ke Storage %s...", storName))

    local okWarp = warpToWorld(storName, storDoor)
    if not okWarp then
        addLog(string.format("[Gagal] Tidak bisa masuk ke Storage %s untuk drop sisa seed.", storName))
        return false
    end
    safeSleep(700)

    -- Aktifkan anti-take agar bot tidak menyedot kembali seed yang di-drop
    STATE.anti_take_active = true
    if editToggle then
        pcall(editToggle, "Auto Collect", false)
        pcall(editToggle, "AutoCollect", false)
        pcall(editToggle, "Anti Collect", true)
        pcall(editToggle, "Anti-Collect", true)
        if CFG.modfly_enabled then pcall(editToggle, "ModFly", true) end
    end
    safeSleep(200)

    local px, py = getPlayerTilePos()
    if px and py then
        local targetX = (px <= 95) and (px + 2) or (px - 2)
        moveSafeTo(targetX, py)
        safeSleep(250)
    end

    for _, it in ipairs(seedsToDrop) do
        if not STATE.running then break end
        dropSingleSeedToStorage(it.id, it.count, getItemNameSafe(it.id))
        safeSleep(300)
    end

    safeSleep(200)
    STATE.anti_take_active = false
    if editToggle then
        pcall(editToggle, "Anti Collect", false)
        pcall(editToggle, "Anti-Collect", false)
        pcall(editToggle, "Auto Collect", true)
        pcall(editToggle, "AutoCollect", true)
    end
    addLog("[Drop Selesai] Sisa seed berhasil disimpan kembali ke Storage " .. storName .. "!")
    return true
end

-- ============================================================================
-- 14. ALUR UTAMA TANAM PER BARIS & WORLD
-- ============================================================================
local function countPlantableSpotsInWorld()
    if not isWorldProperlyLoaded() then
        return -1
    end
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


local function executePlantRow(plantY, goingRight, startX)
    local curPx = getPlayerTilePos()
    if goingRight == nil or startX == nil then
        local detectedDir, detectedStartX = findRowPlantPlan(plantY, curPx)
        if detectedDir == nil then return true end
        if goingRight == nil then goingRight = detectedDir end
        if startX == nil then startX = detectedStartX end
    end
    STATE.current_plant_dir = goingRight

    if CFG.plant_mode == "3zigzag" then
        if goingRight then
            -- =================================================================
            -- POLA 3-ZIGZAG: KIRI KE KANAN
            -- =================================================================
            -- 1. Tangani petak paling kiri (x = 0) HANYA jika mulai dari sisi kiri (startX <= 0)
            if (not startX or startX <= 0) and isTilePlantable(0, plantY) then
                if not hasEnoughSeedInBackpack() then
                    local remHoles = countPlantableSpotsInWorld()
                    if remHoles == 0 then return true end
                    local okRestock = restockFromStorage()
                    if not okRestock then return false end
                end
                moveSafeTo(0, plantY)
                plantTileSection({ 0 }, plantY)
            end

            -- 2. Tanam 3-zigzag maju mulai dari standX terdekat dari startX
            local firstStandX = 1
            if startX and startX > 0 then
                local k = math.floor(startX / 3)
                firstStandX = math.max(1, math.min(97, k * 3 + 1))
            end

            -- Langsung menuju posisi berdiri awal tanpa harus kembali ke ujung kiri x = 0
            local arrivedStart = moveSafeTo(firstStandX, plantY)
            if not arrivedStart and STATE.running then
                safeSleep(150)
                moveSafeTo(firstStandX, plantY)
            end

            local standX = firstStandX
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
                    if not hasEnoughSeedInBackpack() then
                        local remHoles = countPlantableSpotsInWorld()
                        if remHoles == 0 then return true end
                        local okRestock = restockFromStorage()
                        if not okRestock then return false end
                    end

                    local moved = moveSafeTo(standX, plantY)
                    local curPx, curPy = getPlayerTilePos()
                    local inRange = curPx and curPy and math.abs(curPx - standX) <= 2 and math.abs(curPy - plantY) <= 2

                    if inRange or moved then
                        local sectionSpots = {}
                        if sLeft >= 0 and isTilePlantable(sLeft, plantY) then table.insert(sectionSpots, sLeft) end
                        if isTilePlantable(sCenter, plantY) then table.insert(sectionSpots, sCenter) end
                        if sRight <= 99 and isTilePlantable(sRight, plantY) then table.insert(sectionSpots, sRight) end

                        if #sectionSpots > 0 then
                            plantTileSection(sectionSpots, plantY)
                        end
                    end
                end

                standX = standX + 3
            end

            if not STATE.running then return false end

            -- 3. Tangani ujung kanan platform (petak 98 dan 99 agar tidak bolong di ujung)
            if isTilePlantable(98, plantY) or isTilePlantable(99, plantY) then
                if not hasEnoughSeedInBackpack() then
                    local remHoles = countPlantableSpotsInWorld()
                    if remHoles == 0 then return true end
                    local okRestock = restockFromStorage()
                    if not okRestock then return false end
                end

                moveSafeTo(98, plantY)
                local endSpots = {}
                if isTilePlantable(98, plantY) then table.insert(endSpots, 98) end
                if isTilePlantable(99, plantY) then table.insert(endSpots, 99) end
                if #endSpots > 0 then
                    plantTileSection(endSpots, plantY)
                end
            else
                -- Mendarat di ujung kanan (x=98) agar siap langsung turun ke baris bawahnya
                moveSafeTo(98, plantY)
            end

        else
            -- =================================================================
            -- POLA 3-ZIGZAG: KANAN KE KIRI
            -- =================================================================
            -- 1. Tangani ujung kanan (99, 98) HANYA jika mulai dari sisi kanan (startX >= 98)
            if (not startX or startX >= 98) and (isTilePlantable(99, plantY) or isTilePlantable(98, plantY)) then
                if not hasEnoughSeedInBackpack() then
                    local remHoles = countPlantableSpotsInWorld()
                    if remHoles == 0 then return true end
                    local okRestock = restockFromStorage()
                    if not okRestock then return false end
                end

                moveSafeTo(98, plantY)
                local endSpots = {}
                if isTilePlantable(99, plantY) then table.insert(endSpots, 99) end
                if isTilePlantable(98, plantY) then table.insert(endSpots, 98) end
                if #endSpots > 0 then
                    plantTileSection(endSpots, plantY)
                end
            end

            -- 2. Tanam 3-zigzag mundur mulai dari standX terdekat dari startX
            local firstStandX = 97
            if startX and startX < 98 then
                local k = math.floor(startX / 3)
                firstStandX = math.max(1, math.min(97, k * 3 + 1))
            end

            -- Langsung menuju posisi berdiri awal tanpa harus ke ujung kanan x = 98 dahulu
            local arrivedStart = moveSafeTo(firstStandX, plantY)
            if not arrivedStart and STATE.running then
                safeSleep(150)
                moveSafeTo(firstStandX, plantY)
            end

            local standX = firstStandX
            while standX >= 1 do
                if not STATE.running then break end
                while STATE.paused do safeSleep(500) if not STATE.running then break end end

                local sRight  = standX + 1
                local sCenter = standX
                local sLeft   = standX - 1

                local needPlant = (sRight <= 99 and isTilePlantable(sRight, plantY))
                               or isTilePlantable(sCenter, plantY)
                               or (sLeft >= 0 and isTilePlantable(sLeft, plantY))

                if needPlant then
                    if not hasEnoughSeedInBackpack() then
                        local remHoles = countPlantableSpotsInWorld()
                        if remHoles == 0 then return true end
                        local okRestock = restockFromStorage()
                        if not okRestock then return false end
                    end

                    local moved = moveSafeTo(standX, plantY)
                    local curPx, curPy = getPlayerTilePos()
                    local inRange = curPx and curPy and math.abs(curPx - standX) <= 2 and math.abs(curPy - plantY) <= 2

                    if inRange or moved then
                        local sectionSpots = {}
                        if sRight <= 99 and isTilePlantable(sRight, plantY) then table.insert(sectionSpots, sRight) end
                        if isTilePlantable(sCenter, plantY) then table.insert(sectionSpots, sCenter) end
                        if sLeft >= 0 and isTilePlantable(sLeft, plantY) then table.insert(sectionSpots, sLeft) end

                        if #sectionSpots > 0 then
                            plantTileSection(sectionSpots, plantY)
                        end
                    end
                end

                standX = standX - 3
            end

            if not STATE.running then return false end

            -- 3. Tangani petak paling kiri (x = 0) jika masih butuh
            if isTilePlantable(0, plantY) then
                if not hasEnoughSeedInBackpack() then
                    local remHoles = countPlantableSpotsInWorld()
                    if remHoles == 0 then return true end
                    local okRestock = restockFromStorage()
                    if not okRestock then return false end
                end
                moveSafeTo(0, plantY)
                plantTileSection({ 0 }, plantY)
            else
                -- Mendarat di ujung kiri (x=0) agar siap langsung turun ke baris bawahnya
                moveSafeTo(0, plantY)
            end
        end

    else
        -- =====================================================================
        -- MODE 1 BY 1
        -- =====================================================================
        if goingRight then
            local beginX = (startX and startX > 0) and startX or 0
            moveSafeTo(beginX, plantY)
            for curX = beginX, 99 do
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
            moveSafeTo(98, plantY)
        else
            local beginX = (startX and startX < 98) and startX or 99
            moveSafeTo(beginX, plantY)
            for curX = beginX, 0, -1 do
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
            moveSafeTo(0, plantY)
        end
    end

    -- =========================================================================
    -- ROW SWEEPER: Tambal otomatis setiap petak yang terlewat di baris ini
    -- Urutkan dari yang terdekat dengan posisi bot agar tidak bolak-balik
    -- =========================================================================
    if hasPlantableSpotsInRow(plantY) then
        local missedSpots = {}
        for x = 0, 99 do
            if isTilePlantable(x, plantY) then table.insert(missedSpots, x) end
        end

        if #missedSpots > 0 then
            local curPx = getPlayerTilePos()
            table.sort(missedSpots, function(a, b)
                return math.abs(a - curPx) < math.abs(b - curPx)
            end)

            addLog(string.format("[Tambal Baris Y=%d] Menyelesaikan %d petak terlewat/tersplice...", plantY, #missedSpots))
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

    -- Posisikan bot di ujung baris untuk persiapan baris berikutnya
    if goingRight then
        moveSafeTo(98, plantY)
    else
        moveSafeTo(0, plantY)
    end

    return true
end

local function plantEntireWorld()
    STATE.fresh_seeds = {}
    STATE.blocked_tiles = {}
    STATE.plant_fail_count = {}
    scanForeignLocksInWorld()
    local curW = getCurrentWorldSafe()
    if not isWorldProperlyLoaded(curW) then
        addLog("[Peringatan] World belum termuat atau bot terputus (disconnect). Tanam ditunda.")
        return false, "DISCONNECTED"
    end

    setStatus("Menanam", "Memulai proses tanam dari baris paling atas di world " .. curW)
    addLog(string.format("Memulai tanam serpentine world %s (Urut baris Y=0 s/d 53, zigzag kiri-kanan & kanan-kiri)", curW))

    -- Pindai dan kumpulkan baris yang memiliki petak kosong berlantai (Y=0 s/d Y=53)
    local activeRows = {}
    for y = 0, 53 do
        if hasPlantableSpotsInRow(y) then
            table.insert(activeRows, y)
        end
    end

    if #activeRows == 0 then
        if not isWorldProperlyLoaded(curW) then
            return false, "DISCONNECTED"
        end
        local chkHoles = countPlantableSpotsInWorld()
        if chkHoles == 0 then
            setStatus("World Penuh / Selesai", "Tidak ada petak kosong yang dapat ditanam di world " .. curW)
            addLog("[Info] World " .. curW .. " tidak memiliki petak kosong berlantai. Ditandai selesai.")
            return true
        else
            return false, "DISCONNECTED"
        end
    end

    addLog(string.format("Terdeteksi %d baris tanam di %s (Mulai baris Y=%d secara serpentine)",
        #activeRows, curW, activeRows[1]))

    for idx, plantY in ipairs(activeRows) do
        if not STATE.running then break end
        while STATE.paused do safeSleep(500) if not STATE.running then break end end

        if not isWorldProperlyLoaded(curW) then
            addLog("[Disconnect] Terputus saat menanam baris Y=" .. plantY .. ". World TIDAK ditandai selesai.")
            return false, "DISCONNECTED"
        end

        -- Tentukan arah dan titik awal tanam secara cerdas berdasarkan seed terakhir / petak yang sudah ditanam:
        local curPx = getPlayerTilePos()
        local goingRight, startX, lastSeedX, holesCount = findRowPlantPlan(plantY, curPx)
        if goingRight ~= nil then
            local dirStr = goingRight and "Kiri->Kanan" or "Kanan->Kiri"
            local seedInfo = lastSeedX and string.format("X=%d", lastSeedX) or "Fresh"
            local infoMsg = string.format("Baris Y=%d (%d/%d) [%s] Mulai X=%d (Seed Terakhir: %s | Sisa: %d petak) di %s",
                plantY, idx, #activeRows, dirStr, startX or 0, seedInfo, holesCount or 0, curW)
            setStatus("Menanam", infoMsg)
            addLog("[Auto Plant] " .. infoMsg)

            local okRow = executePlantRow(plantY, goingRight, startX)
            if not okRow then return false end
        end
    end

    -- =========================================================================
    -- WORLD SWEEPER: Validasi ulang seluruh baris (Y=0 s/d 53) untuk memastikan 0 BOLONG
    -- =========================================================================
    local maxWorldSweeps = 2
    for sweepCycle = 1, maxWorldSweeps do
        if not STATE.running then break end
        while STATE.paused do safeSleep(500) if not STATE.running then break end end

        if not isWorldProperlyLoaded(curW) then
            return false, "DISCONNECTED"
        end

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
            if not isWorldProperlyLoaded(curW) then
                return false, "DISCONNECTED"
            end
            local curPx = getPlayerTilePos()
            local sweepDir, sweepStartX, sweepLastSeed, sweepHoles = findRowPlantPlan(sweepY, curPx)
            if sweepDir ~= nil then
                local okRow = executePlantRow(sweepY, sweepDir, sweepStartX)
                if not okRow then return false end
            end
        end
    end

    -- Verifikasi Akhir Jumlah Petak Kosong
    if not isWorldProperlyLoaded(curW) then
        return false, "DISCONNECTED"
    end
    local finalHoles = countPlantableSpotsInWorld()
    if finalHoles == 0 then
        addLog(string.format("World Farm %s SELESAI ditanam! (100%% Penuh, 0 Bolong)", curW))
        setStatus("World Selesai", string.format("World %s 100%% tuntas tertanam!", curW))
        return true
    else
        addLog(string.format("[Peringatan] World %s masih menyisakan %d petak kosong. Status belum selesai.", curW, finalHoles))
        setStatus("Selesai Sebagian", string.format("Tersisa %d petak kosong di %s", finalHoles, curW))
        return false, "INCOMPLETE"
    end
end

-- ============================================================================
-- 15. MAIN BOT COROUTINE
-- ============================================================================
local function autoPlantMainLoop()
    STATE.running = true
    STATE.paused  = false
    STATE.fresh_seeds = {}
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
            local isLoaded = arrived and waitForWorldLoaded(4000, entry.name)

            if isLoaded and isWorldProperlyLoaded(entry.name) then
                safeSleep(500)
                syncInventoryCache()

                -- Validasi awal: Cek apakah world ini memang masih memiliki petak kosong berlantai
                local initialHoles = countPlantableSpotsInWorld()
                if initialHoles == 0 then
                    addLog(string.format("[Info] World %s sudah ter-plant penuh (0 petak kosong tersisa). Selesai!", entry.name))
                    entry.done = true
                    entry.status = "DONE"
                    STATE.active_world_idx = STATE.active_world_idx + 1
                    persistConfig()
                    updateWorldDisplayList()

                    -- Cek apakah masih ada world berikutnya yang membutuhkan seed
                    local nextNeedsSameSeed = false
                    for i = STATE.active_world_idx, #CFG.world_list do
                        local nw = CFG.world_list[i]
                        if nw and not nw.done then
                            nextNeedsSameSeed = true
                            break
                        end
                    end

                    local s1 = CFG.seed_1_id
                    local s2 = CFG.seed_2_id
                    local curS1 = (s1 > 0) and getInvCount(s1) or 0
                    local curS2 = (CFG.splice_mode and s2 > 0) and getInvCount(s2) or 0
                    if (curS1 > 0 or curS2 > 0) and not nextNeedsSameSeed then
                        addLog(string.format("[Sisa Seed] World Farm %s sudah penuh dan ada sisa seed di tas (S1:%d, S2:%d). Mengembalikan ke storage...",
                            entry.name, curS1, curS2))
                        dropLeftoverSeedsToStorage(s1, s2)
                    end
                elseif initialHoles > 0 then
                    -- Cek stok awal HANYA jika world masih membutuhkan penanaman
                    if not hasEnoughSeedInBackpack() then
                        local okR = restockFromStorage()
                        if not okR then
                            entry.status = "ANTRI"
                            persistConfig()
                            updateWorldDisplayList()
                            break
                        end
                    end

                    local okPlant, plantReason = plantEntireWorld()
                    if okPlant and STATE.running and isWorldProperlyLoaded(entry.name) then
                        entry.done = true
                        entry.status = "DONE"
                        STATE.active_world_idx = STATE.active_world_idx + 1
                        persistConfig()
                        updateWorldDisplayList()
                        addLog(string.format("World Farm %s SELESAI ditanam!", entry.name))
                        if sendNotification then
                            pcall(sendNotification, string.format("Farm %s selesai! Menuju world berikutnya...", entry.name))
                        end

                        -- Cek apakah masih ada world berikutnya yang membutuhkan seed
                        local nextNeedsSameSeed = false
                        for i = STATE.active_world_idx, #CFG.world_list do
                            local nw = CFG.world_list[i]
                            if nw and not nw.done then
                                nextNeedsSameSeed = true
                                break
                            end
                        end

                        local s1 = CFG.seed_1_id
                        local s2 = CFG.seed_2_id
                        local curS1 = (s1 > 0) and getInvCount(s1) or 0
                        local curS2 = (CFG.splice_mode and s2 > 0) and getInvCount(s2) or 0
                        if (curS1 > 0 or curS2 > 0) and not nextNeedsSameSeed then
                            addLog(string.format("[Sisa Seed] World Farm %s selesai dan terdapat sisa seed di tas (S1:%d, S2:%d). Mengembalikan ke storage...",
                                entry.name, curS1, curS2))
                            dropLeftoverSeedsToStorage(s1, s2)
                        end
                    else
                        -- Terputus / Disconnect / Pause / Belum tuntas
                        entry.done = false
                        entry.status = "ANTRI"
                        persistConfig()
                        updateWorldDisplayList()

                        if plantReason == "DISCONNECTED" or not isWorldProperlyLoaded(entry.name) then
                            addLog(string.format("[Disconnect] Bot terputus di %s. World TETAP 'ANTRI' & TIDAK ditandai selesai.", entry.name))
                            if CFG.auto_reconnect then
                                addLog("[Reconnect] Menunggu 4 detik untuk mencoba kembali ke world " .. entry.name .. "...")
                                safeSleep(4000)
                                -- Loop akan mencoba ulang world yang sama karena STATE.active_world_idx TIDAK bertambah!
                            else
                                addLog("[Info] Auto reconnect non-aktif. Bot dihentikan aman.")
                                STATE.running = false
                                if editToggle then pcall(editToggle, "ap_run_power", false) end
                                break
                            end
                        else
                            if STATE.paused or not STATE.running then
                                break
                            end
                            -- Jika hanya 1 world dan masih ada seed, jangan berhenti: ulangi baris tersisa
                            if #CFG.world_list <= 1 and hasEnoughSeedInBackpack() then
                                addLog(string.format("[Info] Melanjutkan penyisiran petak tersisa di %s...", entry.name))
                                safeSleep(1000)
                            else
                                STATE.active_world_idx = STATE.active_world_idx + 1
                            end
                        end
                    end
                else
                    -- initialHoles == -1 (terputus / tile map belum ready)
                    entry.done = false
                    entry.status = "ANTRI"
                    persistConfig()
                    updateWorldDisplayList()
                    addLog(string.format("[Disconnect] World %s gagal memuat tile map. Status tetap 'ANTRI'.", entry.name))
                    if CFG.auto_reconnect then
                        safeSleep(3000)
                    else
                        break
                    end
                end
            else
                -- Gagal warp atau terputus
                entry.done = false
                entry.status = "ANTRI"
                persistConfig()
                updateWorldDisplayList()
                addLog(string.format("[Gagal Masuk/Disconnect] Tidak dapat mengakses world %s. World tetap 'ANTRI'.", entry.name))
                if CFG.auto_reconnect then
                    addLog("[Reconnect] Mencoba menghubungkan ulang ke " .. entry.name .. "...")
                    safeSleep(3500)
                else
                    -- Jika auto reconnect non-aktif, lewati ke world berikutnya
                    STATE.active_world_idx = STATE.active_world_idx + 1
                end
            end
        else
            -- World memang sudah berstatus DONE, lewati ke indeks berikutnya
            STATE.active_world_idx = STATE.active_world_idx + 1
        end

        -- Cek apakah seluruh antrean selesai atau masih ada world tertunda
        if STATE.active_world_idx > #CFG.world_list and STATE.running and not STATE.paused then
            local hasPendingWorld = false
            for _, w in ipairs(CFG.world_list) do
                if not w.done then
                    hasPendingWorld = true
                    break
                end
            end
            if hasPendingWorld and hasEnoughSeedInBackpack() then
                STATE.active_world_idx = 1
                safeSleep(1000)
            end
        end
    end

    if STATE.paused then
        -- Pertahankan status pause agar user tahu kenapa bot berhenti (misal: Seed Habis)
        STATE.running = false
        if editToggle then pcall(editToggle, "ap_run_power", false) end
        updateWorldDisplayList()
        return
    end

    if STATE.running then
        local s1 = CFG.seed_1_id
        local s2 = CFG.seed_2_id
        local curS1 = (s1 > 0) and getInvCount(s1) or 0
        local curS2 = (CFG.splice_mode and s2 > 0) and getInvCount(s2) or 0
        if curS1 > 0 or curS2 > 0 then
            addLog(string.format("[Sisa Seed] Seluruh world farm selesai dan terdapat sisa seed di tas (S1:%d, S2:%d). Mengembalikan ke storage...",
                curS1, curS2))
            dropLeftoverSeedsToStorage(s1, s2)
        end
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
    STATE.blocked_tiles = {}
    STATE.plant_fail_count = {}
    pcall(scanForeignLocksInWorld)

    local function safeMainLoop()
        local ok, err = xpcall(autoPlantMainLoop, function(e)
            return tostring(e) .. "\n" .. debug.traceback()
        end)
        if not ok then
            addLog("`4[Runtime Crash] `w" .. tostring(err))
            STATE.running = false
            if editToggle then pcall(editToggle, "ap_run_power", false) end
        end
    end

    if runCoroutine then
        pcall(runCoroutine, safeMainLoop)
    else
        local co = coroutine.create(safeMainLoop)
        coroutine.resume(co)
    end
end

local function stopBot()
    STATE.running = false
    STATE.paused  = false
    STATE.anti_take_active = false
    STATE.pending_drop_id = 0
    STATE.pending_drop_amt = 0
    STATE.drop_confirmed = false
    setStatus("Berhenti", "Bot dimatikan pengguna.")
    if editToggle then
        pcall(editToggle, "ap_run_power", false)
        pcall(editToggle, "Anti Collect", false)
        pcall(editToggle, "Anti-Collect", false)
        pcall(editToggle, "Auto Collect", true)
        pcall(editToggle, "AutoCollect", true)
    end
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

    local dLines = {
        "set_default_color|`o",
        "add_quick_exit|",
        string.format("add_label_with_icon|big|`wKelola & Tempel World (%d)``|left|2|", #CFG.world_list),
        "add_textbox|`oKelola daftar antrean world farm, tempel antrean baru, dan atur door/seed.|left|",
        "add_spacer|small|",

        -- Bagian 1: Tempel Banyak / Tambah World
        "add_textbox|`2[1. Tempel / Tambah World ke Antrean]|left|",
        "add_textbox|`eTempel 1 atau banyak world (Format: WORLD:ID / WORLD|ID / WORLD). Bebas koma, spasi, enter.|left|",
        "add_text_input|boren_wpaste_raw|Tempel World di sini:||9999|",
        "add_checkbox|boren_wpaste_replace|Ganti semua antrean (Replace)|0|",
        "add_button|boren_submit_wpaste|`2+ Tempel / Tambah ke Antrean|noflags|0|0|",
        "add_spacer|small|",

        -- Bagian 2: Daftar World & Aksi Edit/Hapus
        string.format("add_textbox|`2[2. Daftar Antrean Saat Ini (%d World)]|left|", #CFG.world_list),
        "add_button|boren_btn_wreset_all|`2🔄 Reset Semua Status World (Tanam Ulang)|noflags|0|0|",
        "add_spacer|small|"
    }

    if #CFG.world_list == 0 then
        table.insert(dLines, "add_textbox|`4(Antrean World Farm masih kosong. Silakan tempel di atas!)|left|")
    else
        for i, e in ipairs(CFG.world_list) do
            local st = getWorldEntryStatusTag(e)
            local d = (e.door and e.door ~= "") and e.door or "-"
            table.insert(dLines, string.format("add_textbox|`w%d. `9%s `o[Door: %s] `2[%s]|left|", i, e.name, d, st))
            table.insert(dLines, string.format("add_button|boren_wreset_%d|Reset Status|noflags|0|0|", i))
            table.insert(dLines, string.format("add_button|boren_wedit_%d|Edit|noflags|0|0|", i))
            table.insert(dLines, string.format("add_button|boren_whapus_%d|Hapus|noflags|0|0|", i))
            table.insert(dLines, "add_spacer|small|")
        end
    end

    table.insert(dLines, "add_button|boren_btn_wsave|💾 Simpan Antrean ke File (boren_plant_worlds.txt)|noflags|0|0|")
    table.insert(dLines, "add_button|boren_btn_wload|📂 Muat Antrean dari File|noflags|0|0|")
    table.insert(dLines, "add_button|boren_btn_wclear|🗑️ Kosongkan Seluruh Antrean World|noflags|0|0|")
    table.insert(dLines, "add_spacer|small|")
    table.insert(dLines, "add_button|boren_btn_back_main|`c<< Kembali ke Menu Utama /plant|noflags|0|0|")
    table.insert(dLines, "end_dialog|boren_plant_world_mgr|Tutup||")
    return safeSendRawDialog(table.concat(dLines, "\n"))
end

openStorageListManagerDialog = function()
    local dLines = {
        "set_default_color|`o",
        "add_quick_exit|",
        string.format("add_label_with_icon|big|`wKelola & Tempel Gudang (%d)``|left|242|", #CFG.storage_world_list),
        "add_textbox|`oKelola daftar antrean gudang seed, tempel gudang baru, dan atur door/seed.|left|",
        "add_spacer|small|",

        -- Bagian 1: Tempel Banyak / Tambah Gudang
        "add_textbox|`2[1. Tempel / Tambah Gudang Seed ke Antrean]|left|",
        "add_textbox|`eTempel 1 atau banyak gudang (Format: WORLD:ID / WORLD|ID / WORLD). Bebas koma, spasi, enter.|left|",
        "add_text_input|boren_stpaste_raw|Tempel Gudang di sini:||9999|",
        "add_checkbox|boren_stpaste_replace|Ganti semua gudang (Replace)|0|",
        "add_button|boren_submit_stpaste|`2+ Tempel / Tambah ke Antrean|noflags|0|0|",
        "add_spacer|small|",

        -- Bagian 2: Daftar Gudang & Aksi Edit/Hapus
        string.format("add_textbox|`2[2. Daftar Antrean Gudang (%d Gudang)]|left|", #CFG.storage_world_list)
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

    table.insert(dLines, "add_button|boren_btn_stsave|💾 Simpan Gudang ke File (boren_plant_storages.txt)|noflags|0|0|")
    table.insert(dLines, "add_button|boren_btn_stload|📂 Muat Gudang dari File|noflags|0|0|")
    table.insert(dLines, "add_button|boren_btn_stclear|🗑️ Kosongkan Seluruh Gudang Seed|noflags|0|0|")
    table.insert(dLines, "add_spacer|small|")
    table.insert(dLines, "add_button|boren_btn_back_main|`c<< Kembali ke Menu Utama /plant|noflags|0|0|")
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
        if btn == "boren_btn_back_main" then
            showPlantMainDialog()
            return true
        elseif btn == "boren_btn_wsave" then
            savePlantWorldsToFile(false)
            openWorldListManagerDialog()
            return true
        elseif btn == "boren_btn_wload" then
            loadPlantWorldsFromFile()
            openWorldListManagerDialog()
            return true
        elseif btn == "boren_btn_wclear" then
            CFG.world_list = {}
            STATE.active_world_idx = 1
            persistConfig()
            addLog("[World Farm] Seluruh antrean world berhasil dikosongkan.")
            if sendNotification then pcall(sendNotification, "Antrean world dikosongkan!") end
            openWorldListManagerDialog()
            return true
        end

        if btn == "boren_btn_wreset_all" then
            for _, w in ipairs(CFG.world_list) do
                w.done = false
                w.status = "ANTRI"
            end
            STATE.active_world_idx = 1
            persistConfig()
            updateWorldDisplayList()
            addLog("[World Farm] Semua status world berhasil di-reset ke ANTRE!")
            if sendNotification then pcall(sendNotification, "Semua status world di-reset ke ANTRE!") end
            openWorldListManagerDialog()
            return true
        end

        local resetIdx = btn:match("^boren_wreset_(%d+)$")
        if resetIdx then
            local idx = tonumber(resetIdx)
            if idx and CFG.world_list[idx] then
                CFG.world_list[idx].done = false
                CFG.world_list[idx].status = "ANTRI"
                persistConfig()
                updateWorldDisplayList()
                addLog(string.format("[World Farm] Status %s di-reset ke ANTRE.", CFG.world_list[idx].name))
                if sendNotification then pcall(sendNotification, "Status " .. CFG.world_list[idx].name .. " di-reset!") end
                openWorldListManagerDialog()
            end
            return true
        end

        if btn == "boren_submit_wpaste" or btn == "boren_submit_paste" then
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
        if btn == "boren_btn_back_main" then
            showPlantMainDialog()
            return true
        elseif btn == "boren_btn_stsave" then
            savePlantStoragesToFile(false)
            openStorageListManagerDialog()
            return true
        elseif btn == "boren_btn_stload" then
            loadPlantStoragesFromFile()
            openStorageListManagerDialog()
            return true
        elseif btn == "boren_btn_stclear" then
            CFG.storage_world_list = {}
            persistConfig()
            addLog("[Gudang Seed] Seluruh daftar gudang berhasil dikosongkan.")
            if sendNotification then pcall(sendNotification, "Daftar gudang dikosongkan!") end
            openStorageListManagerDialog()
            return true
        end

        if btn == "boren_submit_stpaste" or btn == "boren_submit_paste" then
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

local function onVariantDialogHook(var)
    if type(var) ~= "table" and type(var) ~= "userdata" then return false end
    local v1, v2 = nil, nil
    pcall(function() v1 = var.v1 or var[0] end)
    pcall(function() v2 = var.v2 or var[1] end)
    local fn = tostring(v1 or "")
    local payload = tostring(v2 or "")

    if fn == "OnDialogRequest" and payload ~= "" then
        local endDlg = (payload:match("end_dialog|([^|\r\n]+)") or ""):lower()
        local low = payload:lower()
        if (STATE.pending_drop_id or 0) > 0 and (endDlg == "drop" or endDlg == "drop_item" or endDlg:find("drop", 1, true)
            or low:find("how many to drop", 1, true) or low:find("drop_item", 1, true))
        then
            if not STATE.drop_confirmed then
                STATE.drop_confirmed = true
                if sendPacket then
                    local pktStr = buildDropDialogReturn(payload, STATE.pending_drop_id, STATE.pending_drop_amt)
                    pcall(sendPacket, 2, pktStr)
                end
            end
            return true
        end
    end
    return false
end

-- ============================================================================
-- 17. STANDALONE UI ARCHITECTURE (TIDAK IKUT GL DRAWER)
-- ============================================================================
local function registerNativePlantUI()
    -- 100% Standalone Dear ImGui Apex Suite v3.0 ("Tidak ikut GL")
end

updatePowerStatusList = function() end
updateSeedStatusDisplay = function() end
updateBagDisplayList = function() end
updateLogDisplayList = function() end


-- 17B. FILE BACKUP ENGINE (FARM WORLDS & STORAGE WORLDS)
-- ============================================================================
savePlantWorldsToFile = function(silent)
    local exportLines = {}
    for _, e in ipairs(CFG.world_list) do
        local line = (e.door and e.door ~= "") and (e.name .. ":" .. e.door) or e.name
        table.insert(exportLines, line)
    end
    local exportTxt = table.concat(exportLines, "\n")
    local fn = CFG.world_file_name or "boren_plant_worlds.txt"
    local wrote = writeTextFileIfExists(fn, exportTxt)

    if not silent then
        local summary = string.format("Tersimpan %d world farm ke %s & Preferences.", #CFG.world_list, fn)
        addLog("[Save World] " .. summary)
        if sendNotification then pcall(sendNotification, summary) end
        if updateFileInfoDisplayList then pcall(updateFileInfoDisplayList) end
    end
    return wrote
end

local function loadPlantWorldsFromFile()
    local fn = CFG.world_file_name or "boren_plant_worlds.txt"
    local raw = readTextFileIfExists(fn)
    if raw and raw ~= "" then
        local added, dups, ignored, summary = parseAndValidateWorldBatch(raw, true)
        addLog(string.format("[Load World] Berhasil memuat %d world dari %s", added, fn))
        if sendNotification then pcall(sendNotification, string.format("Berhasil memuat %d world dari Download!", added)) end
    else
        addLog("[Load World] File world tidak ditemukan atau kosong!")
        if sendNotification then pcall(sendNotification, "File world belum ada atau kosong!") end
    end
    if updateFileInfoDisplayList then pcall(updateFileInfoDisplayList) end
    if updateWorldDisplayList then pcall(updateWorldDisplayList) end
end

savePlantStoragesToFile = function(silent)
    local exportLines = {}
    for _, e in ipairs(CFG.storage_world_list) do
        local line = (e.door and e.door ~= "") and (e.name .. ":" .. e.door) or e.name
        table.insert(exportLines, line)
    end
    local exportTxt = table.concat(exportLines, "\n")
    local fn = CFG.storage_file_name or "boren_plant_storage.txt"
    local wrote = writeTextFileIfExists(fn, exportTxt)
    writeTextFileIfExists("boren_plant_storages.txt", exportTxt)

    if not silent then
        local summary = string.format("Tersimpan %d gudang ke %s & Preferences.", #CFG.storage_world_list, fn)
        addLog("[Save Storage] " .. summary)
        if sendNotification then pcall(sendNotification, summary) end
    end
    return wrote
end

local function loadPlantStoragesFromFile()
    local fn = CFG.storage_file_name or "boren_plant_storage.txt"
    local raw = readTextFileIfExists(fn)
    if not raw or raw == "" then
        raw = readTextFileIfExists("boren_plant_storages.txt")
        if raw and raw ~= "" then fn = "boren_plant_storages.txt" end
    end
    if raw and raw ~= "" then
        local added, dups, ignored, summary = parseAndValidateStorageBatch(raw, true)
        addLog(string.format("[Load Storage] Berhasil memuat %d gudang dari %s", added, fn))
        if sendNotification then pcall(sendNotification, string.format("Berhasil memuat %d gudang dari file!", added)) end
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
local isSyncingDelay = false
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

    -- Debounce anti spam event (terutama saat addHook & legacySetOnValue aktif bersamaan)
    local now = getClockSafe()
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
        savePrefs(CFG)
    elseif name == "ap_manual_door_input" then
        CFG.manual_door_text = tostring(val or "")
        savePrefs(CFG)
    elseif name == "ap_manual_stor_input" then
        CFG.manual_storage_text = tostring(val or "")
        savePrefs(CFG)
    elseif name == "ap_manual_stor_door_input" then
        CFG.manual_stor_door = tostring(val or "")
        savePrefs(CFG)
    elseif name == "ap_btn_add_world" then
        local rawW = tostring(CFG.manual_world_text or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local rawD = tostring(CFG.manual_door_text or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if rawW ~= "" then
            local tokenToAdd = rawW
            if rawD ~= "" and not rawW:find("[:|]") then
                tokenToAdd = rawW .. ":" .. rawD
            end
            local added, dups, ignored, summary = parseAndValidateWorldBatch(tokenToAdd, false)
            if added == 0 and not rawW:find("[:|,;%s]") then
                local parsed = parseWorldEntryToken(rawW, rawD)
                if parsed and parsed.name ~= "" then
                    if not isWorldInList(CFG.world_list, parsed.name) then
                        table.insert(CFG.world_list, parsed)
                        added = 1
                    end
                end
            end
            if added > 0 then
                CFG.manual_world_text = ""
                CFG.manual_door_text = ""
                if editValue then
                    pcall(editValue, "ap_manual_world_input", "")
                    pcall(editValue, "ap_manual_door_input", "")
                end
                persistConfig()
                updateWorldDisplayList()
                if sendNotification then pcall(sendNotification, "World Farm ditambahkan!") end
            else
                if sendNotification then pcall(sendNotification, "World sudah ada atau tidak valid!") end
            end
        end
    elseif name == "ap_btn_add_cur_world" then
        local curW = getCurrentWorldSafe()
        if curW ~= "" and curW ~= "EXIT" then
            local rawD = tostring(CFG.manual_door_text or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if not isWorldInList(CFG.world_list, curW) then
                table.insert(CFG.world_list, { name = curW, door = rawD, done = false, status = "ANTRI" })
                CFG.manual_door_text = ""
                if editValue then pcall(editValue, "ap_manual_door_input", "") end
                persistConfig()
                updateWorldDisplayList()
                local dTag = (rawD ~= "") and (":" .. rawD) or ""
                if sendNotification then pcall(sendNotification, "World Farm ditambahkan: " .. curW .. dTag) end
            else
                if sendNotification then pcall(sendNotification, "World saat ini sudah ada di antrean!") end
            end
        end
    elseif name == "ap_btn_clear_worlds" then
        CFG.world_list = {}
        persistConfig()
        updateWorldDisplayList()
        if sendNotification then pcall(sendNotification, "Daftar World Farm dikosongkan!") end
    elseif name == "ap_btn_reset_status" then
        local cnt = 0
        for _, w in ipairs(CFG.world_list) do
            w.done = false
            w.status = "ANTRI"
            cnt = cnt + 1
        end
        STATE.active_world_idx = 1
        persistConfig()
        updateWorldDisplayList()
        local msg = string.format("Status %d World Farm di-reset ke ANTRE! Siap ditanam ulang.", cnt)
        addLog(msg)
        if sendNotification then pcall(sendNotification, msg) end
    elseif name == "ap_btn_view_worlds" or name == "ap_btn_paste_worlds" or name == "ap_btn_copy_all_worlds" then
        openWorldListManagerDialog()
    elseif name == "ap_btn_save_worlds" then
        savePlantWorldsToFile(false)
    elseif name == "ap_btn_load_worlds" then
        loadPlantWorldsFromFile()
    elseif name == "ap_btn_add_storage" then
        local rawW = tostring(CFG.manual_storage_text or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local rawD = tostring(CFG.manual_stor_door or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if rawW ~= "" then
            local tokenToAdd = rawW
            if rawD ~= "" and not rawW:find("[:|]") then
                tokenToAdd = rawW .. ":" .. rawD
            end
            local added, dups, ignored, summary = parseAndValidateStorageBatch(tokenToAdd, false)
            if added == 0 and not rawW:find("[:|,;%s]") then
                local parsed = parseWorldEntryToken(rawW, rawD)
                if parsed and parsed.name ~= "" then
                    if not isWorldInList(CFG.storage_world_list, parsed.name) then
                        table.insert(CFG.storage_world_list, { name = parsed.name, door = parsed.door })
                        added = 1
                    end
                end
            end
            if added > 0 then
                CFG.manual_storage_text = ""
                CFG.manual_stor_door = ""
                if editValue then
                    pcall(editValue, "ap_manual_stor_input", "")
                    pcall(editValue, "ap_manual_stor_door_input", "")
                end
                persistConfig()
                updateStorageDisplayList()
                if sendNotification then pcall(sendNotification, "World Storage ditambahkan!") end
            else
                if sendNotification then pcall(sendNotification, "Storage sudah ada atau tidak valid!") end
            end
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
        savePrefs(CFG)
    elseif name == "ap_slider_target_bp" then
        CFG.target_seed_bp = tonumber(val) or CFG.target_seed_bp
        savePrefs(CFG)
    elseif name == "ap_slider_collect_range" then
        CFG.collect_range = tonumber(val) or CFG.collect_range
        savePrefs(CFG)
    elseif name == "ap_slider_plant_delay" then
        if not isSyncingDelay then
            local d = math.max(10, math.min(5000, math.floor(tonumber(val) or 180)))
            if d ~= CFG.plant_delay then
                CFG.plant_delay = d
                savePrefs(CFG)
                if editValue then
                    isSyncingDelay = true
                    pcall(editValue, "ap_input_plant_delay", tostring(CFG.plant_delay))
                    isSyncingDelay = false
                end
            end
        end
    elseif name == "ap_input_plant_delay" then
        if not isSyncingDelay then
            local d = math.max(10, math.min(5000, math.floor(tonumber(val) or 180)))
            if d ~= CFG.plant_delay then
                CFG.plant_delay = d
                savePrefs(CFG)
                if editValue then
                    isSyncingDelay = true
                    pcall(editValue, "ap_slider_plant_delay", CFG.plant_delay)
                    isSyncingDelay = false
                end
                if sendNotification then pcall(sendNotification, "Delay tanam: " .. CFG.plant_delay .. " ms") end
            end
        end
    elseif name == "ap_slider_splice_delay" then
        if not isSyncingDelay then
            local d = math.max(10, math.min(5000, math.floor(tonumber(val) or 180)))
            if d ~= CFG.splice_delay then
                CFG.splice_delay = d
                savePrefs(CFG)
                if editValue then
                    isSyncingDelay = true
                    pcall(editValue, "ap_input_splice_delay", tostring(CFG.splice_delay))
                    isSyncingDelay = false
                end
            end
        end
    elseif name == "ap_input_splice_delay" then
        if not isSyncingDelay then
            local d = math.max(10, math.min(5000, math.floor(tonumber(val) or 180)))
            if d ~= CFG.splice_delay then
                CFG.splice_delay = d
                savePrefs(CFG)
                if editValue then
                    isSyncingDelay = true
                    pcall(editValue, "ap_slider_splice_delay", CFG.splice_delay)
                    isSyncingDelay = false
                end
                if sendNotification then pcall(sendNotification, "Jeda splice: " .. CFG.splice_delay .. " ms") end
            end
        end
    elseif name == "ap_slider_step_delay" then
        CFG.step_delay = tonumber(val) or CFG.step_delay
        savePrefs(CFG)
    elseif name == "ap_slider_warp_delay" then
        CFG.warp_delay = tonumber(val) or CFG.warp_delay
        savePrefs(CFG)
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
    elseif name == "ap_toggle_fix_splice" then
        CFG.auto_clear_failed_splice = (val == true or val == 1)
        persistConfig()
        if sendNotification then
            pcall(sendNotification, "Auto Fix Gagal Splice: " .. (CFG.auto_clear_failed_splice and "AKTIF" or "NONAKTIF"))
        end
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
    "ap_manual_world_input", "ap_manual_door_input", "ap_btn_add_world",
    "ap_btn_add_cur_world", "ap_btn_view_worlds", "ap_btn_reset_status", "ap_btn_clear_worlds", "ap_btn_save_worlds",
    "ap_btn_load_worlds", "ap_slider_min_bp", "ap_slider_target_bp", "ap_slider_collect_range",
    "ap_manual_stor_input", "ap_manual_stor_door_input", "ap_btn_add_storage", "ap_btn_view_storages",
    "ap_btn_save_storages", "ap_btn_load_storages", "ap_btn_clear_storages", "ap_input_plant_delay",
    "ap_slider_plant_delay", "ap_input_splice_delay", "ap_slider_splice_delay", "ap_slider_step_delay",
    "ap_slider_warp_delay", "ap_toggle_ignore_gems", "ap_toggle_modfly", "ap_toggle_anti_lava",
    "ap_toggle_reconnect", "ap_toggle_fix_splice", "ap_btn_clear_logs", "ap_toggle_err_only", "ap_btn_refresh_bag"
}



-- ============================================================================
-- 19. INITIALIZATION & HOOK BINDINGS (STANDALONE APEX ARCHITECTURE)
-- ============================================================================
ensureHooksInstalled()
onVariant    = onVariantDialogHook
OnVariant    = onVariantDialogHook

_G.CFG = CFG
_G.STATE = STATE
_G.persistConfig = persistConfig
_G.getPlayerTilePos = getPlayerTilePos
_G.getTilePlantStatus = getTilePlantStatus
_G.plantAndSpliceTile = plantAndSpliceTile
_G.isTilePlantable = isTilePlantable
_G.scanForeignLocksInWorld = scanForeignLocksInWorld
_G.isTilePlanted = isTilePlanted
_G.findRowPlantPlan = findRowPlantPlan
_G.executePlantRow = executePlantRow
_G.plantEntireWorld = plantEntireWorld
_G.parseSavedWorldList = parseSavedWorldList
_G.parseSavedStorageList = parseSavedStorageList
_G.parseAndValidateWorldBatch = parseAndValidateWorldBatch
_G.parseAndValidateStorageBatch = parseAndValidateStorageBatch
_G.savePlantWorldsToFile = savePlantWorldsToFile
_G.loadPlantWorldsFromFile = loadPlantWorldsFromFile
_G.savePlantStoragesToFile = savePlantStoragesToFile
_G.loadPlantStoragesFromFile = loadPlantStoragesFromFile
_G.dropLeftoverSeedsToStorage = dropLeftoverSeedsToStorage
_G.startBot = startBot
_G.stopBot = stopBot

-- ============================================================================
-- 20. BOREN APEX SUITE v3.0 - THEME ENGINE & STATE
-- ============================================================================
local UI = {
    open            = true,
    minimized       = false,
    active_tab      = 1,
    touch_shield    = true,

    world_input     = "",
    door_input      = "",
    seed1_input     = tostring(CFG.seed_1_id or "880"),
    seed2_input     = tostring(CFG.seed_2_id or "0"),

    storage_input   = "",
    stor_door_input = "",
}
_G.__BOREN_APEX_UI = UI

local pushColMode = nil
local vec4Ok = nil
local borenPal = nil

local function packU32(r, g, b, a)
    return math.floor(r) + math.floor(g) * 256 + math.floor(b) * 65536 + math.floor(a or 255) * 16777216
end

local function canUseImVec4()
    if vec4Ok ~= nil then return vec4Ok end
    if ImVec4 then
        local ok, v = pcall(ImVec4, 1.0, 1.0, 1.0, 1.0)
        vec4Ok = (ok and v ~= nil)
    else
        vec4Ok = false
    end
    return vec4Ok
end

local function v4(r, g, b, a)
    if canUseImVec4() then
        local ok, c = pcall(ImVec4, r, g, b, a or 1.0)
        if ok and c then return c end
    end
    return nil
end

local function mkCol(r, g, b, a)
    a = a or 255
    return {
        r = r / 255.0, g = g / 255.0, b = b / 255.0, a = a / 255.0,
        u32 = packU32(r, g, b, a),
        v4  = v4(r / 255.0, g / 255.0, b / 255.0, a / 255.0),
    }
end


-- ============================================================================
-- 18. GROWTOPIA IN-GAME DIALOG ENGINE (100% ON-DIALOG-REQUEST)
-- ============================================================================

local UI_STATE = {
    touch_shield = false
}
_G.__BOREN_APEX_UI_STATE = UI_STATE

local function showClientDialog(dText)
    if not dText or dText == "" then return false end
    if growtopia and type(growtopia.sendDialog) == "function" then
        local ok = pcall(growtopia.sendDialog, dText)
        if ok then return true end
    end
    if sendVariant then
        -- Standar resmi Growlauncher: v1 = "OnDialogRequest", v2 = dText (Jangan kirim v0 karena merusak urutan C++ sol2)
        local ok1 = pcall(sendVariant, { v1 = "OnDialogRequest", v2 = dText })
        if ok1 then return true end
        local okNum = pcall(sendVariant, { [1] = "OnDialogRequest", [2] = dText })
        if okNum then return true end
    end
    if sendVariantList then
        local okList = pcall(sendVariantList, { [1] = "OnDialogRequest", [2] = dText })
        if okList then return true end
    end
    if sendDialog then
        pcall(sendDialog, dText)
        return true
    end
    return false
end

-- ============================================================================
-- 19. DIALOG BUILDERS (MAIN, QUEUE, STORAGE, PACING, LOGS)
-- ============================================================================

-- 19A. MAIN DIALOG (/plant)

showPlantItemSearchDialog = function(query, results)
    query = query or ""
    results = results or {}
    local lines = {
        "set_default_color|`o",
        "add_quick_exit|",
        "add_label_with_icon|big|`cBOREN ITEM DATABASE SEARCH (16.480 ITEM)|left|4585|",
        "add_textbox|`oDatabase memuat 16.480 item lengkap Growtopia. Ketik nama item atau ID di bawah:|left|",
        "add_spacer|small|",
        string.format("add_text_input|in_search_q|Cari Nama atau ID Item:|%s|24|", query),
        "add_button|btn_do_search|`2🔍 Cari di Item Database|",
        "add_spacer|small|"
    }

    if #results > 0 then
        lines[#lines + 1] = string.format("add_smalltext|`2Ditemukan %d Item yang cocok:|", #results)
        for i, it in ipairs(results) do
            local seedID, seedName = BOREN_ITEM_DB:resolveSeedID(it.id)
            if seedID <= 0 then seedID = (it.id % 2 == 0) and (it.id + 1) or it.id end
            local sName = (seedName ~= "") and seedName or BOREN_ITEM_DB:resolveName(seedID)
            lines[#lines + 1] = string.format("add_smalltext|`w%d. `9%s `7(ID: %d) -> `eSeed: #%d (%s)|", i, it.name, it.id, seedID, sName)
            lines[#lines + 1] = string.format("add_button|use_s1_%d|`2[ Pakai sbg Seed 1 Utama (#%d) ]|", seedID, seedID)
            lines[#lines + 1] = string.format("add_button|use_s2_%d|`e[ Pakai sbg Seed 2 Splice (#%d) ]|", seedID, seedID)
            lines[#lines + 1] = "add_spacer|small|"
        end
    elseif query ~= "" then
        lines[#lines + 1] = string.format("add_smalltext|`4Tidak ditemukan item dengan kata kunci '%s'. Coba nama lain!|", query)
        lines[#lines + 1] = "add_spacer|small|"
    end

    lines[#lines + 1] = "add_button|btn_back_main|`c<< Kembali ke Menu Utama /plant|"
    lines[#lines + 1] = "end_dialog|plant_search_db|Tutup||"
    showClientDialog(table.concat(lines, "\n"))
end

showPlantAddCurrentWorldDialog = function(currentWorld)
    currentWorld = tostring(currentWorld or getCurrentWorldSafe() or ""):upper()
    if currentWorld == "" or currentWorld == "EXIT" then
        currentWorld = "MYWORLD"
    end
    local s1Display = (CFG.seed_1_id and CFG.seed_1_id > 0) and tostring(CFG.seed_1_id) or "881"
    local s2Display = (CFG.seed_2_id and CFG.seed_2_id > 0) and tostring(CFG.seed_2_id) or ""
    local isSplice = CFG.splice_mode and 1 or 0

    local lines = {
        "set_default_color|`o",
        "add_quick_exit|",
        "add_label_with_icon|big|`wAtur & Tambah World Saat Ini``|left|2|",
        string.format("add_textbox|`oWorld yang terdeteksi: `2`w%s`o|left|", currentWorld),
        "add_textbox|`7Silakan atur Door ID dan ID Seed yang akan ditanam di world ini:|left|",
        "add_spacer|small|",
        string.format("add_text_input|in_cur_world|Nama World:|%s|24|", currentWorld),
        "add_text_input|in_cur_door|Door ID (Kosongkan jika White Door):||16|",
        string.format("add_text_input|in_cur_s1|Seed 1 (ID atau Nama Item):|%s|24|", s1Display),
        string.format("add_text_input|in_cur_s2|Seed 2 (ID atau Nama Item - Splice):|%s|24|", s2Display),
        string.format("add_checkbox|chk_cur_splice|Mode Splice (Gunakan Seed 1 + Seed 2)|%d|", isSplice),
        "add_spacer|small|",
        "add_button|btn_submit_cur_world|`2✔ Tambahkan World & Terapkan Seed|noflags|0|0|",
        "add_button|btn_back_main|`4<< Batal / Kembali ke Menu Utama|noflags|0|0|",
        "end_dialog|plant_add_curr|Batal||"
    }
    return showClientDialog(table.concat(lines, "\n"))
end

showPlantMainDialog = function()
    local isRun = STATE.running
    local curW = getCurrentWorldSafe()
    if curW == "" then curW = "EXIT" end

    -- Load Database item jika belum
    if not BOREN_ITEM_DB.loaded then
        pcall(function() BOREN_ITEM_DB:load() end)
    end

    local s1ID = tonumber(CFG.seed_1_id) or 0
    local s2ID = tonumber(CFG.seed_2_id) or 0
    local s1Name = getItemNameSafe(s1ID)
    local s2Name = (s2ID > 0) and getItemNameSafe(s2ID) or "NONAKTIF"
    local s1Count = getInvCount(s1ID)
    local s2Count = getInvCount(s2ID)

    local lines = {
        "set_default_color|`o",
        "add_quick_exit|",
        "add_label_with_icon|big|`cBOREN AUTO PLANT & SPLICE PRO|left|4585|",
        "add_spacer|small|",
        string.format("add_textbox|`7Status: %s `7| World: `2%s `7| Pohon: `2%d `7| Splice: `e%d|",
            isRun and "`2[RUNNING]" or "`4[IDLE READY]", curW, STATE.trees_planted or 0, STATE.trees_spliced or 0),
        "add_spacer|small|",
    }

    -- Tombol Utama Kontrol Bot
    if not isRun then
        lines[#lines + 1] = "add_button|btn_start_bot|`2▶ START AUTO PLANT (Mulai Bot)|"
    else
        lines[#lines + 1] = "add_button|btn_stop_bot|`4■ STOP AUTO PLANT (Hentikan Bot)|"
    end
    lines[#lines + 1] = "add_button|btn_sync_curr|`b📍 Pakai / Tambah World Saat Ini ke Antrean|"
    lines[#lines + 1] = "add_spacer|small|"

    -- Form Tambah World Antrean (Support Single & Batch)
    lines[#lines + 1] = "add_smalltext|`c=== ENTRY ANTREAN FARM WORLD ===|"
    lines[#lines + 1] = "add_textbox|`7Ketik nama world (atau WORLD:DOOR). Bisa tempel banyak world sekaligus!|left|"
    lines[#lines + 1] = "add_text_input|in_world|Nama World / Batch:||24|"
    lines[#lines + 1] = "add_text_input|in_door|Door ID (Opsional):||16|"
    lines[#lines + 1] = "add_button|btn_add_queue|`2+ Tambahkan ke Antrean World|"
    lines[#lines + 1] = "add_spacer|small|"

    -- Pengaturan Bibit (Dari Item Database)
    lines[#lines + 1] = "add_smalltext|`c=== PENGATURAN BENIH (ITEM DATABASE) ===|"
    lines[#lines + 1] = string.format("add_textbox|`7Seed 1 Utama: `2#%d (%s) `7| Di Tas: `2%d `7bibit|left|", s1ID, s1Name ~= "" and s1Name or "Unknown", s1Count)
    lines[#lines + 1] = string.format("add_text_input|in_seed1|ID atau Nama Seed 1:|%s|24|", tostring(s1ID))
    lines[#lines + 1] = string.format("add_textbox|`7Seed 2 Splice: `e#%d (%s) `7| Di Tas: `e%d `7bibit|left|", s2ID, s2Name, s2Count)
    lines[#lines + 1] = string.format("add_text_input|in_seed2|ID atau Nama Seed 2:|%s|24|", (s2ID > 0) and tostring(s2ID) or "0")
    lines[#lines + 1] = "add_button|btn_open_search_item|`9🔍 Cari ID / Nama di Item Database (16.480 Item)|"
    lines[#lines + 1] = "add_spacer|small|"


    -- Mode & Proteksi Checkboxes
    lines[#lines + 1] = "add_smalltext|`c=== MODE & PROTEKSI BOT ===|"
    lines[#lines + 1] = string.format("add_checkbox|chk_mode3|Mode 3-Petak Sekaligus (3zigzag)|%d|", (CFG.plant_mode == "3zigzag") and 1 or 0)
    lines[#lines + 1] = string.format("add_checkbox|chk_splice|Aktifkan Splice (Kawin 2 Benih)|%d|", CFG.splice_mode and 1 or 0)
    lines[#lines + 1] = string.format("add_checkbox|chk_shield|Touch Shield (Anti-Click Layar Game)|%d|", (UI_STATE.touch_shield ~= false) and 1 or 0)
    lines[#lines + 1] = string.format("add_checkbox|chk_modfly|ModFly Tembus Rintangan|%d|", CFG.use_modfly and 1 or 0)
    lines[#lines + 1] = string.format("add_checkbox|chk_antilava|Anti-Lava / Hazard Shield|%d|", CFG.anti_lava and 1 or 0)
    lines[#lines + 1] = string.format("add_checkbox|chk_reconnect|Auto Reconnect saat Terputus|%d|", CFG.auto_reconnect and 1 or 0)
    lines[#lines + 1] = string.format("add_checkbox|chk_ignoregems|Abaikan Gems di Lantai|%d|", CFG.ignore_gems and 1 or 0)
    lines[#lines + 1] = "add_spacer|small|"

    -- Menu Lanjutan (World Manager & Storage Manager Resmi)
    lines[#lines + 1] = "add_smalltext|`c=== MENU LANJUTAN ===|"
    lines[#lines + 1] = string.format("add_button|btn_menu_queue|`9[ 📋 Kelola & Tempel Antrean World (%d World) ]|", #CFG.world_list)
    lines[#lines + 1] = string.format("add_button|btn_menu_storage|`e[ 📦 Kelola & Tempel Gudang Seed (%d Gudang) ]|", #CFG.storage_world_list)
    lines[#lines + 1] = "add_button|btn_menu_pacing|`a[ Tuning Kecepatan & Delay Pacing ]|"
    lines[#lines + 1] = "add_button|btn_menu_logs|`7[ Lihat Catatan Aktivitas / Logs ]|"
    lines[#lines + 1] = "add_spacer|small|"

    lines[#lines + 1] = "end_dialog|plant_main|Tutup|Simpan Pengaturan|"

    showClientDialog(table.concat(lines, "\n"))
end

-- 19B. QUEUE DIALOG
showPlantQueueDialog = function()
    local lines = {
        "set_default_color|`o",
        "add_quick_exit|",
        "add_label_with_icon|big|`cDAFTAR ANTREAN WORLD FARM|left|242|",
        "add_spacer|small|",
        string.format("add_textbox|`7Total Antrean: `2%d World `7(Otomatis berpindah saat selesai)|", #CFG.world_list),
        "add_spacer|small|",
    }
    if #CFG.world_list == 0 then
        lines[#lines + 1] = "add_smalltext|`4Belum ada world di antrean. Ketik nama world di Menu Utama.|"
    else
        for idx, w in ipairs(CFG.world_list) do
            local dStr = (w.door and w.door ~= "") and ("Door: " .. w.door) or "Door: -"
            local stColor = (w.status == "Done") and "`7[DONE]" or "`2[READY]"
            lines[#lines + 1] = string.format("add_smalltext|#%02d  `w%-14s `7%-12s %s|", idx, w.name, dStr, stColor)
        end
    end
    lines[#lines + 1] = "add_spacer|small|"
    lines[#lines + 1] = "add_button|btn_queue_reset|`2[ Reset Seluruh Status ke Ready ]|"
    lines[#lines + 1] = "add_button|btn_queue_clear|`4[ Kosongkan Seluruh Antrean ]|"
    lines[#lines + 1] = "add_button|btn_queue_save|`o[ Simpan Antrean ke File (boren_plant_worlds.txt) ]|"
    lines[#lines + 1] = "add_button|btn_queue_load|`o[ Muat Antrean dari File ]|"
    lines[#lines + 1] = "add_spacer|small|"
    lines[#lines + 1] = "add_button|btn_back_main|`c<< Kembali ke Menu Utama /plant|"
    lines[#lines + 1] = "end_dialog|plant_queue|Tutup||"

    showClientDialog(table.concat(lines, "\n"))
end

-- 19C. STORAGE VAULT DIALOG
showPlantStorageDialog = function()
    local lines = {
        "set_default_color|`o",
        "add_quick_exit|",
        "add_label_with_icon|big|`eSTORAGE VAULT GUDANG|left|3802|",
        "add_spacer|small|",
        "add_textbox|`7Bot otomatis pergi ke gudang saat seed di tas menipis.|",
        "add_spacer|small|",
        "add_text_input|in_stor_world|Nama World Gudang:|GUDANG_SEED|24|",
        "add_text_input|in_stor_door|Door ID Gudang:|WHITE|16|",
        "add_button|btn_add_storage|`e+ Tambahkan World Gudang|",
        "add_spacer|small|",
        "add_smalltext|`cThreshold Restock Tas:|",
        string.format("add_text_input|in_min_bp|Ambil saat seed di tas kurang dari:|%d|4|", tonumber(CFG.min_seed_bp) or 20),
        string.format("add_text_input|in_tar_bp|Target jumlah ambil ke tas:|%d|4|", tonumber(CFG.target_seed_bp) or 190),
        "add_spacer|small|",
        string.format("add_textbox|`7Daftar Gudang Terdaftar: `e%d Gudang|", #CFG.storage_world_list),
    }
    for idx, s in ipairs(CFG.storage_world_list) do
        local dStr = (s.door and s.door ~= "") and ("Door: " .. s.door) or "Door: -"
        lines[#lines + 1] = string.format("add_smalltext|#%02d  `w%-14s `7%-12s `e[VAULT]|", idx, s.name, dStr)
    end
    lines[#lines + 1] = "add_spacer|small|"
    lines[#lines + 1] = "add_button|btn_stor_clear|`4[ Kosongkan Daftar Gudang ]|"
    lines[#lines + 1] = "add_button|btn_stor_save|`o[ Simpan Gudang ke File ]|"
    lines[#lines + 1] = "add_button|btn_stor_load|`o[ Muat Gudang dari File ]|"
    lines[#lines + 1] = "add_spacer|small|"
    lines[#lines + 1] = "add_button|btn_back_main|`c<< Kembali ke Menu Utama /plant|"
    lines[#lines + 1] = "end_dialog|plant_storage|Tutup|Simpan Pengaturan|"

    showClientDialog(table.concat(lines, "\n"))
end

-- 19D. SPEED PACING DIALOG
showPlantPacingDialog = function()
    local lines = {
        "set_default_color|`o",
        "add_quick_exit|",
        "add_label_with_icon|big|`aTUNING DELAY & KECEPATAN BOT|left|1422|",
        "add_spacer|small|",
        "add_textbox|`7Atur jeda tanam & pergerakan bot (dalam satuan milidetik):|",
        "add_spacer|small|",
        string.format("add_text_input|in_plant_delay|Plant Strike Interval (ms):|%d|5|", CFG.plant_delay or 180),
        string.format("add_text_input|in_splice_delay|Splice Place Interval (ms):|%d|5|", CFG.splice_delay or 160),
        string.format("add_text_input|in_step_delay|Step Teleport Delay (ms):|%d|5|", CFG.step_delay or 110),
        string.format("add_text_input|in_warp_delay|Warp Safe World Delay (ms):|%d|5|", CFG.warp_delay or 5500),
        "add_spacer|small|",
        "add_smalltext|`7Preset Kecepatan Rekomendasi (Klik langsung):|",
        "add_button|preset_speed_fast|`e[ Agresif: 120ms Plant, 85ms Step ]|",
        "add_button|preset_speed_norm|`2[ Standar: 180ms Plant, 110ms Step ]|",
        "add_button|preset_speed_safe|`b[ Aman: 250ms Plant, 140ms Step ]|",
        "add_spacer|small|",
        "add_button|btn_back_main|`c<< Kembali ke Menu Utama /plant|",
        "end_dialog|plant_pacing|Tutup|Simpan Pacing|",
    }
    showClientDialog(table.concat(lines, "\n"))
end

-- 19E. LOGS DIALOG
showPlantLogsDialog = function()
    local lines = {
        "set_default_color|`o",
        "add_quick_exit|",
        "add_label_with_icon|big|`7CATATAN AKTIVITAS BOT (LOGS)|left|658|",
        "add_spacer|small|",
        string.format("add_textbox|`715 Catatan Log Terakhir Realtime (Total: %d):|", #(STATE.logs or {})),
        "add_spacer|small|",
    }
    local curLogs = STATE.logs or {}
    local startIdx = math.max(1, #curLogs - 14)
    if #curLogs == 0 then
        lines[#lines + 1] = "add_smalltext|`7Belum ada aktivitas tercatat.|"
    else
        for i = #curLogs, startIdx, -1 do
            local l = tostring(curLogs[i])
            local col = "`o"
            if l:find("Err") or l:find("Gagal") then col = "`4"
            elseif l:find("Berhasil") or l:find("Siap") or l:find("Dispatch") then col = "`2"
            end
            lines[#lines + 1] = string.format("add_smalltext|%s%s|", col, l:gsub("|", "/"))
        end
    end
    lines[#lines + 1] = "add_spacer|small|"
    lines[#lines + 1] = "add_button|btn_logs_clear|`4[ Bersihkan Semua Log ]|"
    lines[#lines + 1] = "add_button|btn_logs_refresh|`2[ Refresh Log Terbaru ]|"
    lines[#lines + 1] = "add_spacer|small|"
    lines[#lines + 1] = "add_button|btn_back_main|`c<< Kembali ke Menu Utama /plant|"
    lines[#lines + 1] = "end_dialog|plant_logs|Tutup||"
    showClientDialog(table.concat(lines, "\n"))
end

-- ============================================================================
-- 20. DIALOG PACKET RETURN & INTERACTION HANDLER
-- ============================================================================

local function handleDialogReturn(pkt)
    if not pkt or type(pkt) ~= "string" then return false end

    -- MAIN DIALOG
    if pkt:find("dialog_name|plant_main") then
        if pkt:find("buttonClicked|btn_start_bot") then
            startBot()
            showPlantMainDialog()
            return true
        elseif pkt:find("buttonClicked|btn_stop_bot") then
            stopBot()
            showPlantMainDialog()
            return true
        elseif pkt:find("buttonClicked|btn_sync_curr") then
            local cw = getCurrentWorldSafe()
            showPlantAddCurrentWorldDialog(cw)
            return true
        elseif pkt:find("buttonClicked|btn_add_queue") then
            local wInput = pkt:match("in_world|([^|\r\n]+)") or ""
            local dInput = pkt:match("in_door|([^|\r\n]+)") or ""
            wInput = wInput:gsub("^%s+", ""):gsub("%s+$", "")
            dInput = dInput:gsub("^%s+", ""):gsub("%s+$", "")
            if wInput ~= "" then
                local tokenToAdd = wInput
                if dInput ~= "" and not wInput:find("[:|]") then
                    tokenToAdd = wInput .. ":" .. dInput
                end
                local added, dups, ignored, summary = parseAndValidateWorldBatch(tokenToAdd, false)
                if added > 0 then
                    addLog("[Antrean World] " .. summary)
                    if sendNotification then pcall(sendNotification, summary) end
                end
            end
            showPlantMainDialog()
            return true
        elseif pkt:find("buttonClicked|btn_open_search_item") then
            showPlantItemSearchDialog("", {})
            return true
        elseif pkt:find("buttonClicked|btn_menu_queue") then
            openWorldListManagerDialog()
            return true
        elseif pkt:find("buttonClicked|btn_menu_storage") then
            openStorageListManagerDialog()
            return true
        elseif pkt:find("buttonClicked|btn_menu_pacing") then
            showPlantPacingDialog()
            return true
        elseif pkt:find("buttonClicked|btn_menu_logs") then
            showPlantLogsDialog()
            return true
        end

        local s1 = pkt:match("in_seed1|([^|\r\n]+)")
        local s2 = pkt:match("in_seed2|([^|\r\n]+)")
        if s1 and s1 ~= "" then
            local seedID, sName = BOREN_ITEM_DB:resolveSeedID(s1)
            if seedID and seedID > 0 then
                CFG.seed_1_id = seedID
                addLog(string.format("[Seed 1] Dipilih: #%d (%s)", seedID, sName))
            end
        end
        if s2 and s2 ~= "" then
            local seedID, sName = BOREN_ITEM_DB:resolveSeedID(s2)
            if seedID and seedID > 0 then
                CFG.seed_2_id = seedID
                addLog(string.format("[Seed 2] Dipilih: #%d (%s)", seedID, sName))
            else
                CFG.seed_2_id = 0
            end
        end

        CFG.plant_mode = (pkt:match("chk_mode3|1") ~= nil) and "3zigzag" or "1tile"
        CFG.splice_mode = (pkt:match("chk_splice|1") ~= nil)
        UI_STATE.touch_shield = (pkt:match("chk_shield|1") ~= nil)
        CFG.use_modfly = (pkt:match("chk_modfly|1") ~= nil)
        CFG.anti_lava = (pkt:match("chk_antilava|1") ~= nil)
        CFG.auto_reconnect = (pkt:match("chk_reconnect|1") ~= nil)
        CFG.ignore_gems = (pkt:match("chk_ignoregems|1") ~= nil)
        persistConfig()
        applyCheatToggles()
        addLog("[Config] Pengaturan Auto Plant disimpan.")
        return true

    -- ITEM DATABASE SEARCH SUB-DIALOG
    elseif pkt:find("dialog_name|plant_search_db") then
        local q = pkt:match("in_search_q|([^|\r\n]+)") or ""
        q = q:gsub("^%s+", ""):gsub("%s+$", "")

        local pickS1 = pkt:match("buttonClicked|use_s1_(%d+)")
        if pickS1 then
            local id = tonumber(pickS1)
            if id and id > 0 then
                CFG.seed_1_id = id
                persistConfig()
                addLog(string.format("[Item Database] Seed 1 disetel ke #%d (%s)", id, BOREN_ITEM_DB:resolveName(id)))
                if sendNotification then pcall(sendNotification, "Seed 1 disetel: #" .. id) end
            end
            showPlantMainDialog()
            return true
        end

        local pickS2 = pkt:match("buttonClicked|use_s2_(%d+)")
        if pickS2 then
            local id = tonumber(pickS2)
            if id and id > 0 then
                CFG.seed_2_id = id
                CFG.splice_mode = true
                persistConfig()
                addLog(string.format("[Item Database] Seed 2 (Splice) disetel ke #%d (%s)", id, BOREN_ITEM_DB:resolveName(id)))
                if sendNotification then pcall(sendNotification, "Seed 2 disetel: #" .. id) end
            end
            showPlantMainDialog()
            return true
        end

        if pkt:find("buttonClicked|btn_do_search") then
            local results = BOREN_ITEM_DB:search(q, 8)
            showPlantItemSearchDialog(q, results)
            return true
        elseif pkt:find("buttonClicked|btn_back_main") then
            showPlantMainDialog()
            return true
        end
        return true

    -- QUEUE SUB-DIALOG
    elseif pkt:find("dialog_name|plant_queue") then
        if pkt:find("buttonClicked|btn_queue_reset") then
            for _, r in ipairs(CFG.world_list) do r.status = "Ready" end
            persistConfig(); addLog("[Reset] Seluruh status antrean di-reset ke Ready.")
            showPlantQueueDialog(); return true
        elseif pkt:find("buttonClicked|btn_queue_clear") then
            CFG.world_list = {}; persistConfig(); addLog("[Queue] Antrean world dikosongkan.")
            showPlantQueueDialog(); return true
        elseif pkt:find("buttonClicked|btn_queue_save") then
            savePlantWorldsToFile(); showPlantQueueDialog(); return true
        elseif pkt:find("buttonClicked|btn_queue_load") then
            loadPlantWorldsFromFile(); showPlantQueueDialog(); return true
        elseif pkt:find("buttonClicked|btn_back_main") then
            showPlantMainDialog(); return true
        end
        return true

    -- STORAGE SUB-DIALOG
    elseif pkt:find("dialog_name|plant_storage") then
        if pkt:find("buttonClicked|btn_add_storage") then
            local sw = pkt:match("in_stor_world|([^|\r\n]+)") or ""
            local sd = pkt:match("in_stor_door|([^|\r\n]+)") or ""
            sw = sw:gsub("^%s+", ""):gsub("%s+$", ""):upper()
            sd = sd:gsub("^%s+", ""):gsub("%s+$", ""):upper()
            if sw ~= "" and sw ~= "GUDANG_SEED" then
                table.insert(CFG.storage_world_list, { name = sw, door = sd })
                persistConfig(); addLog("[Storage] Menambahkan world gudang: " .. sw)
            end
            showPlantStorageDialog(); return true
        elseif pkt:find("buttonClicked|btn_stor_clear") then
            CFG.storage_world_list = {}; persistConfig()
            showPlantStorageDialog(); return true
        elseif pkt:find("buttonClicked|btn_stor_save") then
            savePlantStoragesToFile(); showPlantStorageDialog(); return true
        elseif pkt:find("buttonClicked|btn_stor_load") then
            loadPlantStoragesFromFile(); showPlantStorageDialog(); return true
        elseif pkt:find("buttonClicked|btn_back_main") then
            showPlantMainDialog(); return true
        end
        local minB = pkt:match("in_min_bp|([^|\r\n]+)")
        local tarB = pkt:match("in_tar_bp|([^|\r\n]+)")
        if minB and tonumber(minB) then CFG.min_seed_bp = tonumber(minB) end
        if tarB and tonumber(tarB) then CFG.target_seed_bp = tonumber(tarB) end
        persistConfig()
        return true

    -- FORM TAMBAH WORLD SAAT INI (SETTING DOOR & SEED)
    elseif pkt:find("dialog_name|plant_add_curr") then
        if pkt:find("buttonClicked|btn_back_main") then
            showPlantMainDialog()
            return true
        end

        local wName = pkt:match("in_cur_world|([^|\r\n]+)") or ""
        local dId   = pkt:match("in_cur_door|([^|\r\n]+)") or ""
        local s1Val = pkt:match("in_cur_s1|([^|\r\n]+)") or ""
        local s2Val = pkt:match("in_cur_s2|([^|\r\n]+)") or ""
        local chkSplice = pkt:match("chk_cur_splice|([01])") == "1"

        wName = wName:gsub("^%s+", ""):gsub("%s+$", ""):upper()
        dId   = dId:gsub("^%s+", ""):gsub("%s+$", "")
        s1Val = s1Val:gsub("^%s+", ""):gsub("%s+$", "")
        s2Val = s2Val:gsub("^%s+", ""):gsub("%s+$", "")

        if wName == "" or wName == "EXIT" then
            wName = getCurrentWorldSafe():upper()
        end

        if wName ~= "" and wName ~= "EXIT" then
            -- 1. Tambahkan ke antrean world
            local token = (dId ~= "") and (wName .. ":" .. dId) or wName
            local added, dups, ignored, summary = parseAndValidateWorldBatch(token, false)

            -- 2. Update konfigurasi Seed 1 & Seed 2
            if s1Val ~= "" then
                local res1, name1 = BOREN_ITEM_DB:resolveSeedID(s1Val)
                if res1 > 0 then
                    CFG.seed_1_id = res1
                    CFG.seed_1_name = (name1 and name1 ~= "") and name1 or resolveSeedName(res1)
                else
                    local num1 = tonumber(s1Val)
                    if num1 and num1 > 0 then
                        CFG.seed_1_id = ensureSeedID(num1)
                        CFG.seed_1_name = resolveSeedName(CFG.seed_1_id)
                    end
                end
                STATE.buf_seed_1_id = CFG.seed_1_id
            end

            CFG.splice_mode = chkSplice
            if chkSplice and s2Val ~= "" then
                local res2, name2 = BOREN_ITEM_DB:resolveSeedID(s2Val)
                if res2 > 0 then
                    CFG.seed_2_id = res2
                    CFG.seed_2_name = (name2 and name2 ~= "") and name2 or resolveSeedName(res2)
                else
                    local num2 = tonumber(s2Val)
                    if num2 and num2 > 0 then
                        CFG.seed_2_id = ensureSeedID(num2)
                        CFG.seed_2_name = resolveSeedName(CFG.seed_2_id)
                    end
                end
                STATE.buf_seed_2_id = CFG.seed_2_id
            end

            persistConfig()
            savePlantWorldsToFile()
            updateSeedStatusDisplay()
            updateWorldDisplayList()

            local logMsg = string.format("[Tambah World] %s (Door: %s) ditambahkan. Seed: %s (#%d)",
                wName, (dId ~= "") and dId or "-", CFG.seed_1_name, CFG.seed_1_id)
            if CFG.splice_mode then
                logMsg = logMsg .. string.format(" + Splice %s (#%d)", CFG.seed_2_name, CFG.seed_2_id)
            end
            addLog(logMsg)
            if sendNotification then pcall(sendNotification, logMsg) end
            if LogToConsole then pcall(LogToConsole, "`2[BOREN PLANT] `w" .. logMsg) end
        end

        showPlantMainDialog()
        return true

    -- PACING SUB-DIALOG
    elseif pkt:find("dialog_name|plant_pacing") then
        if pkt:find("buttonClicked|preset_speed_fast") then
            CFG.plant_delay = 120; CFG.splice_delay = 110; CFG.step_delay = 85; persistConfig()
            showPlantPacingDialog(); return true
        elseif pkt:find("buttonClicked|preset_speed_norm") then
            CFG.plant_delay = 180; CFG.splice_delay = 160; CFG.step_delay = 110; persistConfig()
            showPlantPacingDialog(); return true
        elseif pkt:find("buttonClicked|preset_speed_safe") then
            CFG.plant_delay = 250; CFG.splice_delay = 220; CFG.step_delay = 140; persistConfig()
            showPlantPacingDialog(); return true
        elseif pkt:find("buttonClicked|btn_back_main") then
            showPlantMainDialog(); return true
        end
        local pd = pkt:match("in_plant_delay|([^|\r\n]+)")
        local sd = pkt:match("in_splice_delay|([^|\r\n]+)")
        local st = pkt:match("in_step_delay|([^|\r\n]+)")
        local wd = pkt:match("in_warp_delay|([^|\r\n]+)")
        if pd and tonumber(pd) then CFG.plant_delay = tonumber(pd) end
        if sd and tonumber(sd) then CFG.splice_delay = tonumber(sd) end
        if st and tonumber(st) then CFG.step_delay = tonumber(st) end
        if wd and tonumber(wd) then CFG.warp_delay = tonumber(wd) end
        persistConfig()
        return true

    -- LOGS SUB-DIALOG
    elseif pkt:find("dialog_name|plant_logs") then
        if pkt:find("buttonClicked|btn_logs_clear") then
            STATE.logs = {}; STATE.error_logs = {}
            showPlantLogsDialog(); return true
        elseif pkt:find("buttonClicked|btn_logs_refresh") then
            showPlantLogsDialog(); return true
        elseif pkt:find("buttonClicked|btn_back_main") then
            showPlantMainDialog(); return true
        end
        return true
    end

    return false
end

-- ============================================================================
-- 21. CHAT COMMAND & PACKET INTERCEPTION HOOK (/plant, /p, /boren)
-- ============================================================================

local function plantDialogOnSendPacket(arg1, arg2)
    -- Normalisasi argumen: Growlauncher dapat mengirimkan (pktStr) saja atau (pktType, pktStr)
    local pStr = (type(arg2) == "string") and arg2 or ((type(arg1) == "string") and arg1 or nil)
    local pType = (type(arg1) == "number") and arg1 or ((type(arg2) == "number") and arg2 or nil)

    if not pStr or type(pStr) ~= "string" then return false end

    -- 1. INTERSEPSI CHAT COMMAND (/plant, /p, /boren, /menu, /dialog)
    -- Format paket chat standar Growtopia: action|input\n|text|... (bisa CRLF \r\n)
    local chatText = pStr:match("text|([^\r\n]+)")
    if chatText then
        local trimmed = chatText:gsub("^%s+", ""):gsub("%s+$", ""):lower()
        if trimmed == "/plant" or trimmed == "/p" or trimmed == "/boren" or trimmed == "/menu" or trimmed == "/dialog" or trimmed:find("^/plant%s*") or trimmed:find("^/p%s*") then
            showPlantMainDialog()
            if LogToConsole then
                pcall(LogToConsole, "`2[BOREN PLANT] `wMenu Dialog dibuka via chat command: `e" .. trimmed)
            end
            return true -- Blokir paket agar server Growtopia tidak mencetak "Unknown command"
        end
    end

    -- Fallback deteksi jika paket input chat terformat khusus
    local lowerP = pStr:lower()
    if (lowerP:find("action|input", 1, true) or lowerP:find("action|chat", 1, true)) then
        if lowerP:find("/plant", 1, true) or lowerP:find("|text|/p\r") or lowerP:find("|text|/p\n") or lowerP:find("|text|/menu") or lowerP:find("|text|/boren") then
            showPlantMainDialog()
            if LogToConsole then
                pcall(LogToConsole, "`2[BOREN PLANT] `wMenu Dialog dibuka via fallback command!")
            end
            return true
        end
    end

    -- 2. INTERSEPSI BALASAN DIALOG (action|dialog_return)
    if pStr:find("action|dialog_return", 1, true) then
        if handleDialogReturn and handleDialogReturn(pStr) then
            return true
        end
        if onSendPacketDialogHook and onSendPacketDialogHook(pType, pStr) then
            return true
        end
    end

    return false
end

-- Ekspor hook ke seluruh varian variabel global Growlauncher
onSendPacket = plantDialogOnSendPacket
OnSendPacket = plantDialogOnSendPacket
_G.onSendPacket = plantDialogOnSendPacket
_G.OnSendPacket = plantDialogOnSendPacket

-- Registrasi hook resmi Growlauncher via addHook dan AddHookCallback
if addHook then
    pcall(addHook, plantDialogOnSendPacket, "onsendpacket")
    pcall(addHook, plantDialogOnSendPacket, "onSendPacket")
    pcall(addHook, onSendPacketRawCollectHook, "onsendpacketraw")
end
if AddHookCallback then
    pcall(AddHookCallback, plantDialogOnSendPacket, "onSendPacket")
    pcall(AddHookCallback, plantDialogOnSendPacket, "onsendpacket")
end
if applyHook then
    pcall(applyHook)
end

-- Inisialisasi awal saat script di-Run
addLog("[Boren Plant Dialog] Script Auto Plant (In-Game Dialog) Berhasil Dimuat!")
if LogToConsole then
    pcall(LogToConsole, "`5[BOREN PLANT] `2Script Aktif! `wKetik `c/plant `watau `c/p `wdi chat game untuk membuka Menu Form Dialog.")
end
if sendNotification then
    pcall(sendNotification, "Boren Auto Plant Siap! Ketik /plant di chat game.")
end

-- Otomatis buka dialog saat pertama kali di-run via coroutine agar engine Growlauncher siap
runCoroutine(function()
    safeSleep(200)
    showPlantMainDialog()
end)
