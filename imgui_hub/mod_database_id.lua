-- ============================================================================
-- BOREN STORE IMGUI - MODUL FITUR: DATABASE ID (ITEM ID 16.480+ & PACK DB)
-- File: imgui_hub/mod_database_id.lua
-- ============================================================================
-- Modul fitur standalone untuk mencari ID Item Growtopia & Database Pack.
-- Hanya tampil saat fitur "Database ID" dipilih di sidebar (tidak menabrak
-- fitur lain). Otomatis terdeteksi oleh manifest.lua & boot.lua.
-- ============================================================================

local DB = {}

DB.META = {
    type    = "boren_gl_feature",
    id      = "database_id",
    label   = "Database ID",
    order   = 50,
    enabled = true,
}

local DEFAULT_ITEM_DB_URL   = "https://raw.githubusercontent.com/rendhi69/data-_id_item/main/item_database.txt"
local DEFAULT_DEBUGPACK_URL = "https://raw.githubusercontent.com/rendhi69/data-_id_item/main/debugpack.txt"

local FALLBACK_ITEMS = {
    { id = 2,    name = "Dirt" },
    { id = 3,    name = "Dirt Seed" },
    { id = 4,    name = "Lava" },
    { id = 10,   name = "Rock" },
    { id = 14,   name = "Cave Background" },
    { id = 202,  name = "Small Lock" },
    { id = 204,  name = "Big Lock" },
    { id = 206,  name = "Huge Lock" },
    { id = 226,  name = "Signal Jammer" },
    { id = 242,  name = "World Lock" },
    { id = 340,  name = "Chandelier" },
    { id = 341,  name = "Chandelier Seed" },
    { id = 822,  name = "Water Bucket" },
    { id = 1796, name = "Diamond Lock" },
    { id = 2810, name = "Air Vent" },
    { id = 2811, name = "Air Vent Seed" },
    { id = 3004, name = "Fish Tank" },
    { id = 3005, name = "Fish Tank Seed" },
    { id = 4584, name = "Pepper Tree" },
    { id = 4585, name = "Pepper Tree Seed" },
    { id = 5666, name = "Laser Grid" },
    { id = 5667, name = "Laser Grid Seed" },
    { id = 7188, name = "Blue Gem Lock" },
    { id = 8772, name = "Fertile Soil Block" },
    { id = 8773, name = "Fertile Soil Block Seed" },
}

DB.STATE = {
    items        = {}, -- { { id = 4585, name = "Pepper Tree Seed", low = "pepper tree seed" }, ... }
    by_id        = {}, -- [4585] = "Pepper Tree Seed"
    by_name      = {}, -- ["PEPPER TREE SEED"] = 4585
    packs        = {}, -- fallback pack list bila mod_buy_pack belum dimuat
    total        = 0,
    loaded       = false,
    loading      = false,
    pack_loading = false,
    source       = "Bawaan",
    status       = "Siap",
    revision     = 0,
}

local HUB_REF     = nil
local activeMode  = "item" -- "item" | "pack"
local queryBuf    = ""
local uiNotice    = ""
local lastKey     = nil
local cachedHits  = {}
local cachedTotal = 0
local cachePath   = nil
local autoBooted  = false

-- ============================================================================
-- 1. HELPERS & CACHE FILE PATH
-- ============================================================================
local function trimStr(s)
    local out = (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
    return out
end

local function nowMs()
    if getTime then
        local ok, ms = pcall(getTime)
        if ok and tonumber(ms) then return math.floor(tonumber(ms)) end
    end
    if os and os.clock then
        local ok, c = pcall(os.clock)
        if ok and tonumber(c) then return math.floor(tonumber(c) * 1000) end
    end
    return math.random(100000, 999999)
end

local function getItemDbUrl()
    if HUB_REF and HUB_REF.LINKS and HUB_REF.LINKS.raw_item_db and HUB_REF.LINKS.raw_item_db ~= "" then
        return tostring(HUB_REF.LINKS.raw_item_db)
    end
    return DEFAULT_ITEM_DB_URL
end

local function getPackDbUrl()
    if HUB_REF and HUB_REF.LINKS and HUB_REF.LINKS.raw_debugpack and HUB_REF.LINKS.raw_debugpack ~= "" then
        return tostring(HUB_REF.LINKS.raw_debugpack)
    end
    return DEFAULT_DEBUGPACK_URL
end

local function getCachePath()
    if cachePath then return cachePath end
    if package and package.config and package.config:sub(1, 1) == "\\" then
        cachePath = "boren_item_db_cache.txt"
        return cachePath
    end
    local dirs = {
        "/storage/emulated/0/Android/media/launcher.powerkuy.growlauncher/ScriptLua/",
        "/storage/emulated/0/Android/data/launcher.powerkuy.growlauncher/files/ScriptLua/",
        "/storage/emulated/0/Download/",
    }
    for _, d in ipairs(dirs) do
        local p = d .. "boren_item_db_cache.txt"
        local okR, fR = pcall(io.open, p, "r")
        if okR and fR then fR:close(); cachePath = p; return p end
        local okW, fW = pcall(io.open, p, "a")
        if okW and fW then fW:close(); cachePath = p; return p end
    end
    cachePath = "boren_item_db_cache.txt"
    return cachePath
end

local function seedFallbackItems()
    if #DB.STATE.items > 0 then return end
    for _, it in ipairs(FALLBACK_ITEMS) do
        DB.STATE.items[#DB.STATE.items + 1] = { id = it.id, name = it.name, low = it.name:lower() }
        DB.STATE.by_id[it.id] = it.name
        DB.STATE.by_name[it.name:upper()] = it.id
    end
    DB.STATE.total = #DB.STATE.items
    DB.STATE.revision = DB.STATE.revision + 1
end
seedFallbackItems()

-- ============================================================================
-- 2. PARSER & LOADER (CACHE-FIRST + GITHUB FALLBACK VIA COROUTINE)
-- ============================================================================
local function parseItemDbRaw(rawText)
    if type(rawText) ~= "string" or #rawText < 200 then return 0 end
    local list, byId, byName = {}, {}, {}
    local cnt = 0
    for line in rawText:gmatch("[^\r\n]+") do
        local first = line:sub(1, 2)
        if first ~= "--" and first ~= "//" and line ~= "" then
            local namePart, idPart = line:match("^(.+)%s*=%s*(%d+)%s*$")
            if namePart and idPart then
                local nm = trimStr(namePart)
                local idNum = tonumber(idPart)
                if nm ~= "" and idNum and idNum > 0 then
                    cnt = cnt + 1
                    list[cnt] = { id = idNum, name = nm, low = nm:lower() }
                    byId[idNum] = nm
                    byName[nm:upper()] = idNum
                end
            end
        end
    end
    if cnt >= 100 then
        DB.STATE.items    = list
        DB.STATE.by_id    = byId
        DB.STATE.by_name  = byName
        DB.STATE.total    = cnt
        DB.STATE.loaded   = true
        DB.STATE.revision = DB.STATE.revision + 1
    end
    return cnt
end

local function parseDebugPackRaw(rawText)
    local list = {}
    if type(rawText) ~= "string" or rawText == "" then return list end
    for line in rawText:gmatch("[^\r\n]+") do
        local t = trimStr(line)
        if t ~= "" and not t:match("^%-%-") and not t:match("^packs%s*=") and t ~= "]]" then
            local p1, p2, p3, p4 = t:match("^([^:]+):([^:]+):([^:]*):(.*)$")
            if p1 and p2 then
                local nm = trimStr(p1)
                local cd = trimStr(p2)
                local prStr = trimStr(p3)
                local pr = tonumber(prStr) or 0
                local it = trimStr(p4)
                if nm ~= "" and cd ~= "" then
                    list[#list + 1] = { name = nm, id = cd, price = pr, items = it }
                end
            end
        end
    end
    return list
end

local function getActivePackList()
    if HUB_REF and HUB_REF.buy_pack and HUB_REF.buy_pack.STATE
        and type(HUB_REF.buy_pack.STATE.pack_db) == "table"
        and #HUB_REF.buy_pack.STATE.pack_db > 0
    then
        return HUB_REF.buy_pack.STATE.pack_db
    end
    return DB.STATE.packs
end

function DB.loadItemsAsync(forceOnline)
    if DB.STATE.loading then return end
    if DB.STATE.loaded and (not forceOnline) then return end
    DB.STATE.loading = true
    DB.STATE.status = forceOnline and "Mengunduh ulang Item DB dari GitHub..." or "Memuat database item..."

    local function worker()
        local ok, err = pcall(function()
            local loadedCnt = 0
            if not forceOnline then
                local cands = {
                    getCachePath(),
                    "item_database.txt",
                    "script/item_database.txt",
                    "/storage/emulated/0/Android/media/launcher.powerkuy.growlauncher/ScriptLua/item_database.txt",
                    "/storage/emulated/0/Download/item_database.txt",
                }
                for _, cp in ipairs(cands) do
                    local okO, fh = pcall(io.open, cp, "r")
                    if okO and fh then
                        local raw = fh:read("*a")
                        fh:close()
                        local n = parseItemDbRaw(raw)
                        if n >= 100 then
                            loadedCnt = n
                            DB.STATE.source = "Cache Lokal"
                            DB.STATE.status = string.format("Siap: %d item (Cache Lokal)", n)
                            break
                        end
                    end
                end
            end

            if loadedCnt < 100 or forceOnline then
                local url = getItemDbUrl()
                local raw = nil
                if HUB_REF and HUB_REF.fetchRawUrl then
                    if forceOnline and HUB_REF.refreshCacheTag then pcall(HUB_REF.refreshCacheTag) end
                    raw = HUB_REF.fetchRawUrl(url)
                elseif fetch then
                    local okF, res = pcall(fetch, url .. "?v=" .. tostring(nowMs()))
                    if okF and type(res) == "string" and #res > 500 then raw = res end
                end
                if raw then
                    local n = parseItemDbRaw(raw)
                    if n >= 100 then
                        loadedCnt = n
                        DB.STATE.source = "GitHub"
                        DB.STATE.status = string.format("Siap: %d item (GitHub)", n)
                        local okW, fw = pcall(io.open, getCachePath(), "w")
                        if okW and fw then fw:write(raw); fw:close() end
                    end
                end
            end

            if loadedCnt < 100 then
                DB.STATE.status = string.format("Offline: %d item bawaan (klik Update DB)", DB.STATE.total)
            end
        end)
        if not ok then
            DB.STATE.status = "Gagal muat DB: " .. tostring(err)
        end
        DB.STATE.loading = false
    end

    if runCoroutine then pcall(runCoroutine, worker)
    else worker() end
end

function DB.loadPacksAsync(forceOnline)
    if DB.STATE.pack_loading then return end
    if (not forceOnline) and #getActivePackList() > 0 then return end
    DB.STATE.pack_loading = true

    local function worker()
        pcall(function()
            if HUB_REF and HUB_REF.buy_pack and type(HUB_REF.buy_pack.loadPackDatabase) == "function" then
                if forceOnline and HUB_REF.refreshCacheTag then pcall(HUB_REF.refreshCacheTag) end
                pcall(HUB_REF.buy_pack.loadPackDatabase, forceOnline)
                DB.STATE.revision = DB.STATE.revision + 1
                return
            end
            local url = getPackDbUrl()
            local raw = nil
            if HUB_REF and HUB_REF.fetchRawUrl then
                if forceOnline and HUB_REF.refreshCacheTag then pcall(HUB_REF.refreshCacheTag) end
                raw = HUB_REF.fetchRawUrl(url)
            elseif fetch then
                local okF, res = pcall(fetch, url .. "?v=" .. tostring(nowMs()))
                if okF and type(res) == "string" and #res > 50 then raw = res end
            end
            if raw then
                local parsed = parseDebugPackRaw(raw)
                if #parsed > 0 then
                    DB.STATE.packs = parsed
                    DB.STATE.revision = DB.STATE.revision + 1
                end
            end
        end)
        DB.STATE.pack_loading = false
    end

    if runCoroutine then pcall(runCoroutine, worker)
    else worker() end
end

-- ============================================================================
-- 3. PUBLIC LOOKUP & FAST MEMOIZED SEARCH API
-- ============================================================================
function DB.resolveName(idNum)
    return DB.STATE.by_id[tonumber(idNum) or -1]
end

function DB.resolveID(nameStr)
    return DB.STATE.by_name[trimStr(nameStr):upper()]
end

function DB.search(queryStr, maxLimit)
    local limit = maxLimit or 20
    local q = trimStr(queryStr):lower()
    if q == "" then
        local defOut = {}
        local presets = { 4585, 5667, 341, 3005, 8772, 2810, 242, 202, 2, 14 }
        for _, pid in ipairs(presets) do
            local nm = DB.STATE.by_id[pid]
            if nm then defOut[#defOut + 1] = { id = pid, name = nm } end
        end
        return defOut, #defOut
    end

    local exactHits, prefixHits, otherHits = {}, {}, {}
    local totalFound = 0
    local numQ = tonumber(q)
    if numQ and math.floor(numQ) == numQ then
        local exactNm = DB.STATE.by_id[numQ]
        if exactNm then
            exactHits[#exactHits + 1] = { id = numQ, name = exactNm }
            totalFound = totalFound + 1
        end
        for _, it in ipairs(DB.STATE.items) do
            if it.id ~= numQ then
                local idStr = tostring(it.id)
                if idStr:sub(1, #q) == q then
                    totalFound = totalFound + 1
                    if #prefixHits < limit then prefixHits[#prefixHits + 1] = it end
                elseif it.low:find(q, 1, true) then
                    totalFound = totalFound + 1
                    if #otherHits < limit then otherHits[#otherHits + 1] = it end
                end
            end
        end
    else
        local words = {}
        for w in q:gmatch("%S+") do words[#words + 1] = w end
        for _, it in ipairs(DB.STATE.items) do
            local low = it.low
            local matched = true
            for i = 1, #words do
                if not low:find(words[i], 1, true) then matched = false; break end
            end
            if matched then
                totalFound = totalFound + 1
                if low == q then
                    if #exactHits < limit then exactHits[#exactHits + 1] = it end
                elseif low:sub(1, #q) == q then
                    if #prefixHits < limit then prefixHits[#prefixHits + 1] = it end
                else
                    if #otherHits < limit then otherHits[#otherHits + 1] = it end
                end
            end
        end
    end

    local out = {}
    for _, list in ipairs({ exactHits, prefixHits, otherHits }) do
        for _, it in ipairs(list) do
            if #out >= limit then break end
            out[#out + 1] = it
        end
        if #out >= limit then break end
    end
    return out, totalFound
end

local function searchPacks(queryStr, maxLimit)
    local limit = maxLimit or 20
    local q = trimStr(queryStr):lower()
    local packs = getActivePackList()
    local out, total = {}, 0
    for _, pk in ipairs(packs) do
        local hay = (tostring(pk.name or "") .. " " .. tostring(pk.id or "") .. " " .. tostring(pk.items or "")):lower()
        if q == "" or hay:find(q, 1, true) then
            total = total + 1
            if #out < limit then out[#out + 1] = pk end
        end
    end
    return out, total
end

local function refreshSearchCache()
    local packCnt = #getActivePackList()
    local key = activeMode .. "|" .. queryBuf .. "|" .. tostring(DB.STATE.revision) .. "|" .. tostring(packCnt)
    if key == lastKey then return end
    lastKey = key
    if activeMode == "pack" then
        cachedHits, cachedTotal = searchPacks(queryBuf, 20)
    else
        cachedHits, cachedTotal = DB.search(queryBuf, 20)
    end
end

-- ============================================================================
-- 4. UI HELPERS (KONSISTEN DENGAN HUB.ui_kit BOREN STORE)
-- ============================================================================
local function cleanInputStr(v)
    return (tostring(v or ""):gsub("%z.*", ""))
end

local function safeInputText(id, curVal, maxLen, onDoubleTapFn)
    local k = HUB_REF and HUB_REF.ui_kit
    if k and k.safeInputText then
        return k.safeInputText(id, curVal, maxLen, onDoubleTapFn)
    end
    local s = cleanInputStr(curVal)
    local ok, r1, r2 = pcall(ImGui.InputText, id, s, maxLen or 128)
    if not ok then
        ok, r1, r2 = pcall(ImGui.InputText, id, s)
        if not ok then return false, s end
    end
    if type(r1) == "boolean" and type(r2) == "string" then
        local c = cleanInputStr(r2)
        if r1 or c ~= s then return true, c end
        return false, s
    elseif type(r1) == "string" then
        local c = cleanInputStr(r1)
        if (r2 == true) or c ~= s then return true, c end
        return false, s
    elseif type(r2) == "string" then
        local c = cleanInputStr(r2)
        if c ~= s then return true, c end
    end
    return false, s
end

local function safeAvailX()
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

local function autoBtn(lbl)
    local ok, res = pcall(ImGui.Button, lbl)
    return ok and (res == true)
end

local function uiGap(px)
    local k = HUB_REF and HUB_REF.ui_kit
    if k and k.gap then k.gap(px); return end
    if ImGui and ImGui.Spacing then pcall(ImGui.Spacing) end
end

local function uiSection(title, skipTopSep)
    local k = HUB_REF and HUB_REF.ui_kit
    if k and k.section then k.section(title, skipTopSep); return end
    if not skipTopSep and ImGui and ImGui.Separator then pcall(ImGui.Separator) end
    if title and title ~= "" then ImGui.Text(title) end
end

local function uiSectionWithKetik(title, btnId, onKetikClick, skipTopSep)
    local k = HUB_REF and HUB_REF.ui_kit
    if k and k.sectionWithKetik and k.openInputDialog then
        k.sectionWithKetik(title, btnId, onKetikClick, skipTopSep)
        return
    end
    uiSection(title, skipTopSep)
end

local function tabBtn(lbl, isActive)
    local k = HUB_REF and HUB_REF.ui_kit
    if k and k.tabBtn then return k.tabBtn(lbl, isActive) end
    return autoBtn(isActive and ("[" .. lbl .. "]") or (" " .. lbl .. " "))
end

local function coloredText(colKey, txt)
    local k = HUB_REF and HUB_REF.ui_kit
    if k and k.coloredText and k.getPal then
        local pal = k.getPal()
        k.coloredText(pal and pal[colKey], txt)
        return
    end
    ImGui.Text(tostring(txt or ""))
end

local function copyToClip(label, textVal)
    if ImGui and ImGui.SetClipboardText then
        pcall(ImGui.SetClipboardText, tostring(textVal or ""))
        uiNotice = label .. " disalin ke clipboard!"
    else
        uiNotice = "Clipboard tidak tersedia."
    end
end

local function readClipFirstLine()
    local k = HUB_REF and HUB_REF.ui_kit
    if k and k.readClipboardLines then
        local lines = k.readClipboardLines()
        return lines[1] or ""
    end
    if ImGui and ImGui.GetClipboardText then
        local ok, c = pcall(ImGui.GetClipboardText)
        if ok and type(c) == "string" then
            return trimStr(c:match("([^\r\n]+)") or "")
        end
    end
    return ""
end

local function renderActionBar(tableId, availW, buttons)
    local k = HUB_REF and HUB_REF.ui_kit
    if k and k.renderActionBar then return k.renderActionBar(tableId, availW, buttons) end
    local clicked = nil
    for i, b in ipairs(buttons) do
        if i > 1 then ImGui.SameLine() end
        if autoBtn(b.label) then clicked = i end
    end
    return clicked
end

-- ============================================================================
-- 5. RENDER PANEL KHUSUS FITUR DATABASE ID (TIDAK MENABRAK FITUR LAIN)
-- ============================================================================
function DB.render(hub)
    if hub then HUB_REF = hub end
    if not autoBooted then
        autoBooted = true
        DB.loadItemsAsync(false)
        DB.loadPacksAsync(false)
    end

    local availW = safeAvailX()

    -- Sub-tab atas khusus fitur Database ID
    if tabBtn("Item ID (" .. tostring(DB.STATE.total) .. ")##db_tab_item", activeMode == "item") then
        activeMode = "item"
        DB.loadItemsAsync(false)
    end
    ImGui.SameLine()
    if tabBtn("Pack DB (" .. tostring(#getActivePackList()) .. ")##db_tab_pack", activeMode == "pack") then
        activeMode = "pack"
        DB.loadPacksAsync(false)
    end
    ImGui.Separator()

    -- Bagian Pencarian
    local secTitle = (activeMode == "item")
        and "Cari Item ID (Ketik Nama Item atau Angka ID)"
        or  "Cari Pack Database (Ketik Nama Pack, Kode, atau Item ID)"
    uiSectionWithKetik(secTitle, "db_ktk_q", function()
        local k = HUB_REF and HUB_REF.ui_kit
        if k and k.openInputDialog then
            k.openInputDialog("boren_in_db_q", "Cari Database ID", {
                { id = "f_q", label = "Nama / ID", default = queryBuf, maxLen = 64 },
            }, "Cari", function(vals)
                queryBuf = trimStr(vals.f_q or "")
            end)
        end
    end, true)

    ImGui.PushItemWidth(math.max(180, math.floor(availW - 14)))
    local chQ, newQ = safeInputText("##boren_db_search", queryBuf, 128)
    ImGui.PopItemWidth()
    if chQ then queryBuf = newQ end

    uiGap(4)
    local isBusy = (activeMode == "pack") and DB.STATE.pack_loading or DB.STATE.loading
    local act = renderActionBar("BorenDbActs", availW, {
        { label = "Paste##db_pst", style = "accent" },
        { label = "Clear##db_clr", style = "muted" },
        { label = isBusy and "Memuat...##db_upd" or "Update DB##db_upd" },
    })
    if act == 1 then
        local clip = readClipFirstLine()
        if clip ~= "" then
            queryBuf = clip
            uiNotice = "Paste pencarian: " .. clip
        else
            uiNotice = "Clipboard kosong!"
        end
    elseif act == 2 then
        queryBuf = ""
        uiNotice = "Pencarian dibersihkan."
    elseif act == 3 then
        if activeMode == "pack" then
            DB.loadPacksAsync(true)
            uiNotice = "Memperbarui Pack DB dari GitHub..."
        else
            DB.loadItemsAsync(true)
            uiNotice = "Memperbarui Item DB dari GitHub..."
        end
    end

    uiGap(4)
    refreshSearchCache()
    local statusLine = (activeMode == "item")
        and ((queryBuf == "")
            and (DB.STATE.status .. "  |  Menampilkan item populer")
            or  string.format("Ditemukan: %d item (tampil maks 20)  |  Total DB: %d", cachedTotal, DB.STATE.total))
        or string.format("Ditemukan: %d pack (tampil maks 20)  |  Total Pack: %d", cachedTotal, #getActivePackList())
    coloredText("textMuted", statusLine)
    if uiNotice ~= "" then
        coloredText("textPurple", "Info: " .. uiNotice)
    end

    uiGap(4)
    if activeMode == "item" then
        if ImGui.BeginTable("BorenDbItemTable", 3) then
            ImGui.TableSetupColumn("ID")
            ImGui.TableSetupColumn("Nama Item")
            ImGui.TableSetupColumn("Aksi")
            ImGui.TableHeadersRow()

            if #cachedHits == 0 then
                ImGui.TableNextRow()
                ImGui.TableSetColumnIndex(0); ImGui.Text("-")
                ImGui.TableSetColumnIndex(1); ImGui.Text("Tidak ditemukan untuk '" .. tostring(queryBuf) .. "'")
                ImGui.TableSetColumnIndex(2); ImGui.Text("-")
            else
                for i, it in ipairs(cachedHits) do
                    ImGui.TableNextRow()
                    ImGui.TableSetColumnIndex(0)
                    coloredText("textCyan", tostring(it.id))

                    ImGui.TableSetColumnIndex(1)
                    ImGui.Text(tostring(it.name))

                    ImGui.TableSetColumnIndex(2)
                    if autoBtn(" Copy ID ##db_ci_" .. tostring(i)) then
                        copyToClip("ID " .. tostring(it.id) .. " (" .. tostring(it.name) .. ")", tostring(it.id))
                    end
                    ImGui.SameLine()
                    if autoBtn(" Copy Nama ##db_cn_" .. tostring(i)) then
                        copyToClip("Nama (" .. tostring(it.name) .. ")", tostring(it.name))
                    end
                end
            end
            ImGui.EndTable()
        end
    else
        if ImGui.BeginTable("BorenDbPackTable", 4) then
            ImGui.TableSetupColumn("Pack")
            ImGui.TableSetupColumn("Kode")
            ImGui.TableSetupColumn("Gems / Item ID")
            ImGui.TableSetupColumn("Aksi")
            ImGui.TableHeadersRow()

            if #cachedHits == 0 then
                ImGui.TableNextRow()
                ImGui.TableSetColumnIndex(0); ImGui.Text("-")
                ImGui.TableSetColumnIndex(1); ImGui.Text("Pack tidak ditemukan")
                ImGui.TableSetColumnIndex(2); ImGui.Text("-")
                ImGui.TableSetColumnIndex(3); ImGui.Text("-")
            else
                for i, pk in ipairs(cachedHits) do
                    ImGui.TableNextRow()
                    ImGui.TableSetColumnIndex(0); ImGui.Text(tostring(pk.name or ""))
                    ImGui.TableSetColumnIndex(1); coloredText("textCyan", tostring(pk.id or ""))
                    ImGui.TableSetColumnIndex(2); ImGui.Text(string.format("%dg | %s", tonumber(pk.price) or 0, tostring(pk.items or "-")))
                    ImGui.TableSetColumnIndex(3)
                    if autoBtn(" Copy ID ##db_pi_" .. tostring(i)) then
                        local val = (pk.items and pk.items ~= "") and tostring(pk.items) or tostring(pk.id or "")
                        copyToClip("Pack " .. tostring(pk.name or "") .. " (" .. val .. ")", val)
                    end
                    ImGui.SameLine()
                    if autoBtn(" Kode ##db_pk_" .. tostring(i)) then
                        copyToClip("Kode Pack (" .. tostring(pk.id or "") .. ")", tostring(pk.id or ""))
                    end
                end
            end
            ImGui.EndTable()
        end
    end
end

-- Shortcut chat /id <nama atau angka>
function DB.handleSendPacket(pktType, pktStr)
    if type(pktStr) ~= "string" then return false end
    local txt = pktStr:match("text|([^\n\r]+)")
    if not txt then return false end
    local trimmed = trimStr(txt)
    if trimmed:lower():sub(1, 4) == "/id " then
        local arg = trimStr(trimmed:sub(5))
        if arg ~= "" then
            queryBuf = arg
            activeMode = "item"
            if not DB.STATE.loaded then DB.loadItemsAsync(false) end
            local hits = DB.search(arg, 5)
            if LogToConsole then
                if #hits == 0 then
                    pcall(LogToConsole, "`e[BOREN DB] `4Tidak ditemukan: `w" .. arg)
                else
                    for _, it in ipairs(hits) do
                        pcall(LogToConsole, string.format("`e[BOREN DB] `2%d `w= %s", it.id, it.name))
                    end
                end
            end
        end
        return true
    end
    return false
end

function DB.init(hub)
    HUB_REF = hub
    if hub then hub.item_db = DB end
end

return DB
