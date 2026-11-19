-- ============================================================================
-- COMPONENT: REUSABLE ITEM DATABASE & RESOLVER DARI GITHUB / LOKAL
-- ============================================================================
-- File: component_item_database.lua
-- Lokasi: script/component/component_item_database.lua
-- GitHub Repo: https://github.com/rendhi69/data-_id_item.git
-- Raw URL: https://raw.githubusercontent.com/rendhi69/data-_id_item/main/item_database.txt
--
-- KEGUNAAN:
--   Komponen serbaguna (plug-and-play) untuk memuat seluruh 16.480 ID item
--   Growtopia dari GitHub atau cache lokal secara otomatis. Menghilangkan
--   kebutuhan membuat tabel item lokal manual satu per satu di setiap skrip.
--
-- FITUR LENGKAP:
--   1. Auto-Load Cerdas (Cache-First + Cloud Fallback):
--      - Membaca file cache lokal terlebih dahulu untuk kecepatan instan (offline safe).
--      - Jika cache belum ada, otomatis mendownload dari GitHub via fetch().
--      - Tombol update cloud kapan saja untuk memperbarui database ke versi terbaru.
--   2. Dual Fast Hash Lookup (O(1)):
--      - resolveID("Air Vent") -> 2810
--      - resolveName(2810)     -> "Air Vent"
--      - Bebas kapitalisasi (case-insensitive: "air vent", "AIR VENT", dll).
--   3. Seed <-> Block Auto-Pairing:
--      - getSeedID("Air Vent")  -> 2811 ("Air Vent Seed")
--      - getBlockID("Air Vent Seed") -> 2810 ("Air Vent")
--   4. Kategori Presets Siap Pakai:
--      - Door / Gateway : White Door (6), Door (12), Air Vent (2810), dsb.
--      - Lock / Jammer  : SL (202), BL (204), HL (206), WL (242), DL (1796), BGL (7188), Jammer (226), Zombie Jammer (5638).
--      - Farmable Soil  : Soil Block (8772), Dirt (2), Cave Background (14), dsb.
--   5. Search Engine Item:
--      - searchItems("door", 10) -> Menghasilkan daftar nama & ID yang cocok.
--   6. UI Helper GrowLauncher:
--      - Form cari item interaktif + tombol Update dari GitHub + Display List ID.
-- ============================================================================

local BOREN_ITEM_DB = {}
BOREN_ITEM_DB.__index = BOREN_ITEM_DB

-- ============================================================================
-- KONFIGURASI DEFAULT & JALUR PENYIMPANAN
-- ============================================================================
local GITHUB_RAW_URL = "https://raw.githubusercontent.com/rendhi69/data-_id_item/main/item_database.txt"
local DEFAULT_CACHE_FILENAME = "item_database.txt"

local ANDROID_SEARCH_PATHS = {
    DEFAULT_CACHE_FILENAME,
    "script/" .. DEFAULT_CACHE_FILENAME,
    "script/component/" .. DEFAULT_CACHE_FILENAME,
    "/storage/emulated/0/Android/media/launcher.powerkuy.growlauncher/ScriptLua/" .. DEFAULT_CACHE_FILENAME,
    "/storage/emulated/0/Android/data/launcher.powerkuy.growlauncher/files/ScriptLua/" .. DEFAULT_CACHE_FILENAME,
    "/storage/emulated/0/Download/" .. DEFAULT_CACHE_FILENAME
}

-- Preset Kategori Pintu Populer
local DOOR_ID_SET = {
    [6]    = "Main Door",
    [12]   = "Door",
    [102]  = "House Entrance",
    [282]  = "Gate",
    [598]  = "Dungeon Door",
    [1422] = "Portcullis",
    [2810] = "Air Vent",
    [3272] = "Steam Door",
    [3832] = "Security Camera",
    [4544] = "Saloon Doors",
    [4992] = "Secret Passage"
}

-- Preset Kategori Pengunci & Jammer
local LOCK_AND_JAMMER_SET = {
    [202]  = "Small Lock",
    [204]  = "Big Lock",
    [206]  = "Huge Lock",
    [242]  = "World Lock",
    [1796] = "Diamond Lock",
    [7188] = "Blue Gem Lock",
    [11550]= "Robo Lock",
    [226]  = "Signal Jammer",
    [4994] = "Punch Jammer",
    [5638] = "Zombie Jammer"
}

-- Preset Kategori Soil / Tanah Penanaman
local SOIL_BLOCK_SET = {
    [8772] = "Fertile Soil Block",
    [2]    = "Dirt",
    [10]   = "Rock",
    [14]   = "Cave Background",
    [26]   = "Platform",
    [546]  = "Wood Block",
    [4584] = "Pepper Tree"
}

-- Singkatan & Alias Populer yang Sering Dipakai Pemain
local COMMON_ALIASES = {
    ["SOIL"]               = 8772, -- Fertile Soil Block
    ["SOIL BLOCK"]         = 8772,
    ["FERTILE SOIL"]       = 8772,
    ["FERTILE SOIL BLOCK"] = 8772,
    ["AIR VENT"]           = 2810,
    ["VENT"]               = 2810,
    ["SL"]                 = 202,
    ["BL"]                 = 204,
    ["HL"]                 = 206,
    ["WL"]                 = 242,
    ["DL"]                 = 1796,
    ["BGL"]                = 7188,
    ["ROBO"]               = 11550,
    ["JAMMER"]             = 226,
    ["SIGNAL JAMMER"]      = 226,
    ["PUNCH JAMMER"]       = 4994,
    ["ZOMBIE JAMMER"]      = 5638,
    ["WHITE DOOR"]         = 6,
    ["MAIN DOOR"]          = 6,
    ["DIRT"]               = 2,
    ["ROCK"]               = 10,
    ["CAVE"]               = 14,
    ["CAVE BG"]            = 14,
    ["PEPPER"]             = 4584,
    ["LAVA"]               = 4,
    ["WATER"]              = 822,
    ["WATER BUCKET"]       = 822
}

-- ============================================================================
-- HELPER INTERNAL (SAFE LOGGING & NOTIFIKASI)
-- ============================================================================
local function trimStr(s)
    return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function notifyUser(msg)
    if sendNotification then
        pcall(sendNotification, msg)
    elseif growtopia and growtopia.notify then
        pcall(growtopia.notify, msg)
    end
end

local function logConsole(msg)
    if LogToConsole then
        pcall(LogToConsole, "`9[Boren ItemDB] `0" .. tostring(msg))
    elseif print then
        print("[Boren ItemDB] " .. tostring(msg))
    end
end

-- ============================================================================
-- KONSTRUKTOR
-- ============================================================================
-- Parameter opts:
--   cache_file  : Nama file cache lokal (default: "item_database.txt")
--   auto_load   : boolean (default: true, langsung memuat saat diinisialisasi)
--   raw_url     : URL custom jika ingin menggunakan link raw lain
-- ============================================================================
function BOREN_ITEM_DB.new(opts)
    opts = opts or {}
    local self = setmetatable({}, BOREN_ITEM_DB)

    self.cache_file  = opts.cache_file or DEFAULT_CACHE_FILENAME
    self.raw_url     = opts.raw_url or GITHUB_RAW_URL
    self.loaded      = false
    self.total_items = 0

    -- Dual Hash Tables
    self.by_name     = {} -- ["SOIL BLOCK"] = 8772
    self.by_id       = {} -- [8772] = "Soil Block"
    self.items_array = {} -- { {name = "Soil Block", id = 8772}, ... }

    -- Buffer UI
    self.search_query   = ""
    self.search_results = {}

    if opts.auto_load ~= false then
        self:load()
    end

    return self
end

-- ============================================================================
-- 1. SINKRONISASI FILE (BACA LOKAL, DOWNLOAD GITHUB, SIMPAN CACHE)
-- ============================================================================
function BOREN_ITEM_DB:findLocalCacheFile()
    -- Cek custom cache file
    local candidates = { self.cache_file }
    for _, p in ipairs(ANDROID_SEARCH_PATHS) do
        table.insert(candidates, p)
    end

    for _, path in ipairs(candidates) do
        local okF, fh = pcall(io.open, path, "r")
        if okF and fh then
            fh:close()
            return path
        end
    end
    return nil
end

function BOREN_ITEM_DB:readLocalContent()
    local path = self:findLocalCacheFile()
    if not path then return nil end

    local okF, fh = pcall(io.open, path, "r")
    if okF and fh then
        local data = fh:read("*a")
        fh:close()
        if data and #data > 100 then
            return data, path
        end
    end
    return nil
end

function BOREN_ITEM_DB:saveLocalCache(content)
    if not content or #content < 100 then return false end

    -- Coba simpan ke file cache utama
    local okF, fh = pcall(io.open, self.cache_file, "w")
    if okF and fh then
        fh:write(content)
        fh:close()
        return true
    end

    -- Fallback via writeFile bawaan GL jika ada
    if writeFile then
        local ok = pcall(writeFile, self.cache_file, content)
        if ok then return true end
    end

    return false
end

function BOREN_ITEM_DB:downloadFromGitHub()
    logConsole("Mengunduh database item terbaru dari GitHub...")
    notifyUser("Mengunduh Item Database dari GitHub...")

    local urlWithBust = self.raw_url .. "?t=" .. tostring(os.time())
    local content = nil

    -- 1. fetch bawaan GrowLauncher
    if fetch then
        local okFetch, res, fetchErr = pcall(fetch, urlWithBust)
        if okFetch and res and type(res) == "string" and #res > 1000 then
            content = res
        else
            logConsole("Fetch gagal: " .. tostring(fetchErr or "respons kosong"))
        end
    end

    -- 2. Fallback via httpRequest jika tersedia
    if not content and httpRequest then
        local okReq, res = pcall(httpRequest, urlWithBust)
        if okReq and res and type(res) == "string" and #res > 1000 then
            content = res
        end
    end

    if content and #content > 1000 then
        self:saveLocalCache(content)
        logConsole(string.format("Sukses download database (%d bytes)! Disimpan ke %s", #content, self.cache_file))
        return content
    end

    return nil
end

-- ============================================================================
-- 2. PARSING & MEMORY INDEXING (FAST HASH TABLES)
-- ============================================================================
function BOREN_ITEM_DB:parseRawText(rawText)
    if not rawText or rawText == "" then return 0 end

    self.by_name     = {}
    self.by_id       = {}
    self.items_array = {}

    local count = 0
    for line in rawText:gmatch("[^\r\n]+") do
        local clean = trimStr(line)
        if clean ~= "" and clean:sub(1, 2) ~= "--" and clean:sub(1, 1) ~= "#" then
            local name, idStr = clean:match("^([^=]+)%s*=%s*(%d+)$")
            if name and idStr then
                local itemID   = tonumber(idStr)
                local itemName = trimStr(name)
                local nameKey  = itemName:upper()

                if itemID and itemName ~= "" then
                    self.by_name[nameKey] = itemID
                    self.by_id[itemID]    = itemName
                    table.insert(self.items_array, { name = itemName, id = itemID })
                    count = count + 1
                end
            end
        end
    end

    self.total_items = count
    self.loaded = (count > 0)
    return count
end

-- ============================================================================
-- 3. FUNGSI UTAMA LOAD (CACHE-FIRST + CLOUD FALLBACK)
-- ============================================================================
function BOREN_ITEM_DB:load(forceDownload)
    local rawText = nil
    local srcTag = "Lokal"

    if not forceDownload then
        local localData, localPath = self:readLocalContent()
        if localData then
            rawText = localData
            srcTag = "Cache (" .. localPath .. ")"
        end
    end

    -- Jika belum ada di lokal atau dipaksa download
    if not rawText then
        rawText = self:downloadFromGitHub()
        srcTag = "GitHub"
    end

    if rawText then
        local count = self:parseRawText(rawText)
        logConsole(string.format("Database item siap! Dimuat %d item dari %s.", count, srcTag))
        return true, count
    else
        logConsole("`4Gagal memuat database item (offline dan cache tidak ditemukan)!")
        return false, 0
    end
end

function BOREN_ITEM_DB:updateFromCloud()
    return self:load(true)
end

-- ============================================================================
-- 4. RESOLVER & QUERY ITEM (NAME <-> ID)
-- ============================================================================
function BOREN_ITEM_DB:resolveID(nameOrID, defaultID)
    if not self.loaded then self:load() end

    -- Jika input sudah number atau string angka murni
    local asNum = tonumber(nameOrID)
    if asNum and asNum > 0 then
        local cName = self.by_id[asNum] or ("Item #" .. asNum)
        return math.floor(asNum), cName
    end

    -- Jika input nama string
    local cleanName = trimStr(nameOrID):upper()
    if cleanName == "" then return defaultID or 0, "" end

    -- 1. Exact match di tabel database
    local foundID = self.by_name[cleanName]
    if foundID then
        return foundID, self.by_id[foundID]
    end

    -- 2. Cek Alias Populer (contoh: "SOIL", "WL", "AIR VENT", dll)
    local aliasID = COMMON_ALIASES[cleanName]
    if aliasID then
        return aliasID, self.by_id[aliasID] or ("Item #" .. aliasID)
    end

    -- 3. Cek bila format input berupa Seed dari alias (contoh: "SOIL SEED" -> 8773)
    if cleanName:find("%s+SEED$") then
        local baseName = cleanName:gsub("%s+SEED$", "")
        local baseAliasID = COMMON_ALIASES[baseName]
        if baseAliasID then
            local sID, sName = self:getSeedID(baseAliasID)
            if sID > 0 then return sID, sName end
        end
    end

    -- 4. Fuzzy Substring Match jika mengandung nama unik
    for _, item in ipairs(self.items_array) do
        if item.name:upper() == cleanName then
            return item.id, item.name
        end
    end

    return defaultID or 0, tostring(nameOrID or "")
end

function BOREN_ITEM_DB:resolveName(nameOrID, defaultName)
    if not self.loaded then self:load() end

    local asNum = tonumber(nameOrID)
    if asNum and asNum > 0 then
        return self.by_id[asNum] or defaultName or ("Item #" .. asNum)
    end

    local cleanName = trimStr(nameOrID):upper()
    local foundID = self.by_name[cleanName]
    if foundID then
        return self.by_id[foundID]
    end

    return defaultName or tostring(nameOrID or "")
end

-- ============================================================================
-- 5. PAIRING SEED & BLOCK CERDAS
-- ============================================================================
function BOREN_ITEM_DB:isSeed(nameOrID)
    local _, cName = self:resolveID(nameOrID)
    return (cName:lower():find(" seed", 1, true) ~= nil)
end

function BOREN_ITEM_DB:getSeedID(blockNameOrID)
    local bID, bName = self:resolveID(blockNameOrID)
    if bID <= 0 then return 0, "" end

    if self:isSeed(bID) then
        return bID, bName -- Sudah berupa seed
    end

    -- Pola standar Growtopia: "Nama Block Seed"
    local seedQuery = (bName .. " Seed"):upper()
    local sID = self.by_name[seedQuery]
    if sID then
        return sID, self.by_id[sID]
    end

    -- Fallback toleransi ID ganjil berikutnya (Block + 1)
    local neighborID = bID + 1
    local neighborName = self.by_id[neighborID]
    if neighborName and self:isSeed(neighborName) then
        return neighborID, neighborName
    end

    return 0, ""
end

function BOREN_ITEM_DB:getBlockID(seedNameOrID)
    local sID, sName = self:resolveID(seedNameOrID)
    if sID <= 0 then return 0, "" end

    if not self:isSeed(sID) then
        return sID, sName -- Sudah berupa block
    end

    -- Hapus akhiran " Seed"
    local blockName = sName:gsub("%s+[Ss]eed$", "")
    local bID = self.by_name[blockName:upper()]
    if bID then
        return bID, self.by_id[bID]
    end

    -- Fallback ID genap sebelumnya (Seed - 1)
    local neighborID = sID - 1
    local neighborName = self.by_id[neighborID]
    if neighborName and not self:isSeed(neighborName) then
        return neighborID, neighborName
    end

    return 0, ""
end

-- ============================================================================
-- 6. PRESET KATEGORI (DOOR, LOCK, JAMMER, SOIL)
-- ============================================================================
function BOREN_ITEM_DB:isDoor(nameOrID)
    local id = self:resolveID(nameOrID)
    if DOOR_ID_SET[id] then return true end
    local name = (self.by_id[id] or ""):lower()
    return name:find("door", 1, true) ~= nil or name:find("entrance", 1, true) ~= nil or name:find("vent", 1, true) ~= nil or name:find("gate", 1, true) ~= nil
end

function BOREN_ITEM_DB:isLock(nameOrID)
    local id = self:resolveID(nameOrID)
    if LOCK_AND_JAMMER_SET[id] and id ~= 226 and id ~= 4994 and id ~= 5638 then return true end
    local name = (self.by_id[id] or ""):lower()
    return name:find(" lock", 1, true) ~= nil
end

function BOREN_ITEM_DB:isJammer(nameOrID)
    local id = self:resolveID(nameOrID)
    return (id == 226 or id == 4994 or id == 5638)
end

function BOREN_ITEM_DB:isSoilOrPlatform(nameOrID)
    local id = self:resolveID(nameOrID)
    if SOIL_BLOCK_SET[id] then return true end
    local name = (self.by_id[id] or ""):lower()
    return name:find("soil", 1, true) ~= nil or name:find("platform", 1, true) ~= nil
end

function BOREN_ITEM_DB:getPresetDoors()
    local list = {}
    for id, name in pairs(DOOR_ID_SET) do
        table.insert(list, { id = id, name = name })
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

function BOREN_ITEM_DB:getPresetLocks()
    local list = {}
    for id, name in pairs(LOCK_AND_JAMMER_SET) do
        table.insert(list, { id = id, name = name })
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

-- ============================================================================
-- 7. SEARCH ENGINE ITEM (CARI ITEM & ID BERDASARKAN KATA KUNCI)
-- ============================================================================
function BOREN_ITEM_DB:search(query, maxResults)
    maxResults = math.min(100, tonumber(maxResults) or 15)
    local results = {}
    local clean = trimStr(query):upper()
    if clean == "" or not self.loaded then return results end

    -- 1. Exact match diutamakan
    local exactID = self.by_name[clean]
    if exactID then
        table.insert(results, { name = self.by_id[exactID], id = exactID, exact = true })
    end

    -- 2. Substring match
    for _, item in ipairs(self.items_array) do
        if #results >= maxResults then break end
        if item.id ~= exactID and item.name:upper():find(clean, 1, true) then
            table.insert(results, { name = item.name, id = item.id, exact = false })
        end
    end

    return results
end

-- ============================================================================
-- 8. UI COMPONENT INTEGRATION (GROWLAUNCHER)
-- ============================================================================
local function jsonEncodeSimple(tbl)
    if json and json.encode then
        local ok, res = pcall(json.encode, tbl)
        if ok and res then return res end
    end
    local parts = {}
    for i, row in ipairs(tbl) do
        table.insert(parts, string.format('["%s","%s"]', tostring(row[1] or ""):gsub('"', '\\"'), tostring(row[2] or ""):gsub('"', '\\"')))
    end
    return "[" .. table.concat(parts, ",") .. "]"
end

function BOREN_ITEM_DB:updateDisplaySearchResults()
    if not editValue then return end
    local rows = {}
    for i, it in ipairs(self.search_results) do
        table.insert(rows, { string.format("%d. %s", i, it.name), "ID: " .. tostring(it.id) })
    end
    if #rows == 0 then
        local statusTxt = self.loaded and ("Total " .. self.total_items .. " item siap dicari") or "Database belum dimuat"
        table.insert(rows, { statusTxt, "Ketik nama item lalu klik Cari" })
    end
    pcall(editValue, "itemdb_disp_results", jsonEncodeSimple(rows))
end

function BOREN_ITEM_DB:attachToUI(uiTab, prefix)
    if not uiTab then return end
    prefix = prefix or "idb_"

    uiTab:addLabel(string.format("Item Database (%d Items):", self.total_items))
    uiTab:addInputString("Cari Nama Item", self.search_query, "Ketik nama", "Contoh: Air Vent / Soil / Jammer", "Search", prefix .. "input_search")
    uiTab:addButton("🔍 Cari ID Item", prefix .. "btn_search")
    uiTab:addButton("🔄 Update Database dari GitHub", prefix .. "btn_update_cloud")
    uiTab:addDisplayList("Hasil Pencarian Item", "Default", "itemdb_disp_results")
    self:updateDisplaySearchResults()
end

function BOREN_ITEM_DB:handleUIValue(name, val, prefix)
    prefix = prefix or "idb_"
    if name == prefix .. "input_search" then
        self.search_query = trimStr(val)
        return true
    elseif name == prefix .. "btn_search" then
        local q = self.search_query
        if q == "" and readGLString then
            q = readGLString(prefix .. "input_search", "")
        end
        if q ~= "" then
            self.search_results = self:search(q, 20)
            self:updateDisplaySearchResults()
            notifyUser(string.format("Ditemukan %d item untuk: '%s'", #self.search_results, q))
        else
            notifyUser("Ketik nama item yang ingin dicari!")
        end
        return true
    elseif name == prefix .. "btn_update_cloud" then
        local ok, count = self:updateFromCloud()
        if ok then
            notifyUser(string.format("Sukses update %d item dari GitHub!", count))
            self:updateDisplaySearchResults()
        else
            notifyUser("Gagal update dari GitHub. Periksa koneksi internet.")
        end
        return true
    end
    return false
end

-- Daftarkan ke Global agar bisa dipanggil langsung
_G.BOREN_ITEM_DB = BOREN_ITEM_DB
return BOREN_ITEM_DB
