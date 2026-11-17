-- ============================================================================
-- BOREN HUB IMGUI - MODUL AUTO DIRT FARM (ENGINE + UI)
-- File: imgui_hub/mod_dirt_farm.lua
-- Fitur:
--   - Clear sisi pinggir (X=0,1,98,99) & lorong horizontal (Y=25..53)
--   - Pasang Wooden Platform (ID 102) di sisi tangga X=1 & X=98
--   - Auto Trash sampah (Dirt / Cave BG / Rock) saat penuh
--   - Restock Platform dari World Storage
--   - Multi-World Queue + Save / Import / Export / Reset Status
-- ============================================================================

local DF = {
    id    = "dirt_farm",
    label = "Dirt Farm",
}

DF.CFG = {
    storage_raw    = "",
    loop_enabled   = false,
    platform_id    = 102,
    clear_side     = true,
    clear_rows     = true,
    place_platform = true,
    auto_trash     = true,
    trash_thresh   = 180,
    punch_delay    = 170,
    place_delay    = 170,
    step_delay     = 110,
    warp_delay     = 3500,
    use_modfly     = true,
}

DF.STATE = {
    enabled      = false,
    running      = false,
    status_text  = "Idle",
    rows         = {},   -- { { name="W", door="D", status="Ready" }, ... }
    selected_idx = 0,
    selected_st  = 0,
    logs         = {},
}

local HUB_REF = nil
local activeSub = "worlds" -- "worlds" | "storage" | "settings" | "logs"
local addWorldBuf = ""
local addStorageBuf = ""
local uiNotice = ""
local CACHED_PATH = nil

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
    if isSystemWindows() then
        CACHED_PATH = "boren_hub_df_data.txt"
        return CACHED_PATH
    end
    local dirs = {
        "/storage/emulated/0/Android/media/launcher.powerkuy.growlauncher/ScriptLua/",
        "/storage/emulated/0/Android/data/launcher.powerkuy.growlauncher/files/ScriptLua/",
        "/storage/emulated/0/Download/",
    }
    for _, d in ipairs(dirs) do
        local p = d .. "boren_hub_df_data.txt"
        local okR, fR = pcall(io.open, p, "r")
        if okR and fR then fR:close(); CACHED_PATH = p; return p end
        local okW, fW = pcall(io.open, p, "a")
        if okW and fW then fW:close(); CACHED_PATH = p; return p end
    end
    CACHED_PATH = "boren_hub_df_data.txt"
    return CACHED_PATH
end

local function addLogUI(msg)
    local clean = tostring(msg or ""):gsub("`.", "")
    local ts = ""
    if os and type(os.date) == "function" then
        local okD, d = pcall(os.date, "%H:%M:%S")
        if okD and d then ts = "[" .. d .. "] " end
    end
    local entry = ts .. "[DF] " .. clean
    table.insert(DF.STATE.logs, 1, entry)
    if #DF.STATE.logs > 60 then table.remove(DF.STATE.logs) end
    if HUB_REF and HUB_REF.addLog then HUB_REF.addLog(entry) end
end

local function addLog(msg)
    addLogUI(msg)
    if LogToConsole then pcall(LogToConsole, "`e[Boren DF] `w" .. tostring(msg or "")) end
end

local function safeSleep(ms)
    ms = tonumber(ms) or 50
    if ms < 10 then ms = 10 end
    local fn = sleep or CSleep
    if fn then pcall(fn, ms) end
end

local function parseWorldLine(raw)
    local s = trimStr(raw)
    if s == "" or s:sub(1, 1) == "#" then return nil end
    s = s:gsub("|", ":")
    local w, d = s:match("^([^:]+):(.*)$")
    if w then
        w = trimStr(w):upper()
        d = trimStr(d):upper()
        if w == "" then return nil end
        return { name = w, door = d, status = "Ready" }
    end
    return { name = s:upper(), door = "", status = "Ready" }
end

local function getStorageList()
    local list = {}
    local raw = trimStr(DF.CFG.storage_raw)
    if raw == "" then return list end
    for tok in raw:gmatch("[^,\r\n;]+") do
        local p = parseWorldLine(tok)
        if p then table.insert(list, { name = p.name, door = p.door }) end
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
    DF.CFG.storage_raw = table.concat(out, ",")
    DF.saveData()
end

function DF.saveData()
    local lines = {
        "STORAGE=" .. tostring(DF.CFG.storage_raw or ""),
        "LOOP=" .. (DF.CFG.loop_enabled and "1" or "0"),
        "PLAT=" .. tostring(tonumber(DF.CFG.platform_id) or 102),
        "CSIDE=" .. (DF.CFG.clear_side and "1" or "0"),
        "CROWS=" .. (DF.CFG.clear_rows and "1" or "0"),
        "PPLAT=" .. (DF.CFG.place_platform and "1" or "0"),
        "TRASH=" .. (DF.CFG.auto_trash and "1" or "0"),
        "PUNCHD=" .. tostring(tonumber(DF.CFG.punch_delay) or 170),
        "PLACED=" .. tostring(tonumber(DF.CFG.place_delay) or 170),
        "STEPD=" .. tostring(tonumber(DF.CFG.step_delay) or 110),
        "MODFLY=" .. (DF.CFG.use_modfly and "1" or "0"),
    }
    for _, r in ipairs(DF.STATE.rows) do
        local line = r.name .. ":" .. tostring(r.door or "") .. "|" .. tostring(r.status or "Ready")
        table.insert(lines, "ROW=" .. line)
    end
    local ok, f = pcall(io.open, getDataPath(), "w")
    if ok and f then f:write(table.concat(lines, "\n")); f:close() end
end

function DF.loadData()
    local ok, f = pcall(io.open, getDataPath(), "r")
    if not ok or not f then return end
    local txt = f:read("*a"); f:close()
    if not txt or txt == "" then return end
    DF.STATE.rows = {}
    for line in txt:gmatch("[^\r\n]+") do
        local k, v = line:match("^([A-Z]+)=(.*)$")
        if k == "STORAGE" then DF.CFG.storage_raw = trimStr(v)
        elseif k == "LOOP" then DF.CFG.loop_enabled = (v == "1")
        elseif k == "PLAT" then DF.CFG.platform_id = tonumber(v) or 102
        elseif k == "CSIDE" then DF.CFG.clear_side = (v ~= "0")
        elseif k == "CROWS" then DF.CFG.clear_rows = (v ~= "0")
        elseif k == "PPLAT" then DF.CFG.place_platform = (v ~= "0")
        elseif k == "TRASH" then DF.CFG.auto_trash = (v ~= "0")
        elseif k == "PUNCHD" then DF.CFG.punch_delay = tonumber(v) or 170
        elseif k == "PLACED" then DF.CFG.place_delay = tonumber(v) or 170
        elseif k == "STEPD" then DF.CFG.step_delay = tonumber(v) or 110
        elseif k == "MODFLY" then DF.CFG.use_modfly = (v ~= "0")
        elseif k == "ROW" then
            local wd, st = v:match("^(.-)|(.*)$")
            local p = parseWorldLine(wd or v)
            if p then
                p.status = (st and st ~= "") and st or "Ready"
                table.insert(DF.STATE.rows, p)
            end
        end
    end
end

-- ============================================================================
-- 2. GAME HELPERS (WARP, MOVE, PUNCH, PLACE, TRASH, RESTOCK)
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

local function getCurrentWorldSafe()
    local fn = getCurrentWorldName or getWorld or getCurrentWorld
    if not fn then return "" end
    local ok, res = pcall(fn)
    if ok and type(res) == "string" then return res:upper() end
    if ok and type(res) == "table" and res.name then return tostring(res.name):upper() end
    return ""
end

local function getTileSafe(tx, ty)
    if not getTile or tx < 0 or tx > 99 or ty < 0 or ty > 53 then return nil end
    local ok, t = pcall(getTile, tx, ty)
    return (ok and t) and t or nil
end

local function getInvCount(id)
    id = tonumber(id) or 0
    if id <= 0 then return 0 end
    if getInventory then
        local ok, inv = pcall(getInventory)
        if ok and type(inv) == "table" then
            for _, it in pairs(inv) do
                local iid = tonumber(it.id or it.itemid or it.itemId or 0) or 0
                if iid == id then return tonumber(it.count or it.amount or 0) or 0 end
            end
            return 0
        end
    end
    return 0
end

local function applyCheats()
    if not editToggle then return end
    if DF.CFG.use_modfly then pcall(editToggle, "ModFly", true) end
    pcall(editToggle, "Anti Lava", true)
    pcall(editToggle, "No Lava", true)
end

local function moveSafeTo(tx, ty)
    if not DF.STATE.running then return false end
    tx = math.max(0, math.min(99, math.floor(tx or 0)))
    ty = math.max(0, math.min(53, math.floor(ty or 0)))
    local cx, cy = getPlayerPos()
    if math.abs(cx - tx) <= 1 and math.abs(cy - ty) <= 1 then return true end
    local pFn = FindPath or findPath
    if not pFn then return false end
    if DF.CFG.use_modfly and editToggle then pcall(editToggle, "ModFly", true) end

    local dist = math.max(math.abs(cx - tx), math.abs(cy - ty))
    pcall(pFn, tx, ty)
    local maxW = (dist <= 3) and math.max(160, (tonumber(DF.CFG.step_delay) or 110) * 3) or math.max(3000, math.min(20000, dist * 220))
    local waited, lastX, lastY, stuck = 0, cx, cy, 0
    while waited < maxW and DF.STATE.running do
        safeSleep(dist <= 3 and 30 or 70)
        waited = waited + (dist <= 3 and 30 or 70)
        local nx, ny = getPlayerPos()
        if math.abs(nx - tx) <= 1 and math.abs(ny - ty) <= 1 then
            safeSleep(DF.CFG.step_delay or 50)
            return true
        end
        if nx == lastX and ny == lastY then
            stuck = stuck + 1
            if stuck == 20 then pcall(pFn, tx, ty)
            elseif stuck >= 38 then break end
        else
            stuck = 0; lastX, lastY = nx, ny
        end
    end
    local fx, fy = getPlayerPos()
    return (math.abs(fx - tx) <= 1 and math.abs(fy - ty) <= 1)
end

local function warpToWorld(wName, doorID)
    wName = trimStr(wName):upper()
    doorID = trimStr(doorID):upper()
    if wName == "" then return false end
    if getCurrentWorldSafe() == wName and doorID == "" then applyCheats(); return true end
    local joinStr = (doorID ~= "") and (wName .. "|" .. doorID) or wName
    for _ = 1, 2 do
        if not DF.STATE.running then return false end
        if sendPacket then
            pcall(sendPacket, 3, "action|join_request\nname|" .. joinStr .. "\ninvitedWorld|0")
        elseif growtopia and growtopia.warpTo then
            pcall(growtopia.warpTo, joinStr)
        end
        local w = 0
        local lim = math.max(2000, tonumber(DF.CFG.warp_delay) or 3500)
        while w < lim and DF.STATE.running do
            safeSleep(250); w = w + 250
            if getCurrentWorldSafe() == wName then
                safeSleep(600); applyCheats(); return true
            end
        end
    end
    return getCurrentWorldSafe() == wName
end

local function rawAction(tx, ty, val)
    if not sendPacketRaw then return false end
    local p = getLocalSafe()
    local px = (p and (p.posX or (p.pos and p.pos.x))) or (tx * 32)
    local py = (p and (p.posY or (p.pos and p.pos.y))) or (ty * 32)
    return pcall(sendPacketRaw, false, {
        type = 3, value = val, px = tx, py = ty, x = px, y = py,
        state = (px > tx * 32) and 48 or 32,
    })
end

local function checkAutoTrash()
    if not DF.CFG.auto_trash or not sendPacket then return end
    local thresh = math.max(50, tonumber(DF.CFG.trash_thresh) or 180)
    local junks = { 2, 3, 14, 15, 4, 5, 10, 11 }
    for _, jid in ipairs(junks) do
        local cnt = getInvCount(jid)
        if cnt >= thresh then
            pcall(sendPacket, 2, "action|trash\n|itemID|" .. tostring(jid) .. "\n")
            safeSleep(300)
            pcall(sendPacket, 2, "action|dialog_return\ndialog_name|trash_item\nitemID|" .. tostring(jid) .. "|\ncount|" .. tostring(cnt) .. "\n")
            safeSleep(350)
        end
    end
end

local function isClearableTile(tx, ty)
    local t = getTileSafe(tx, ty)
    if not t then return false end
    local fg = tonumber(t.fg) or 0
    -- Dirt(2), Lava(4), Rock(10), CaveBG(14) — hindari Bedrock(8), MainDoor(6), Lock(242/202/204/206)
    return (fg == 2 or fg == 4 or fg == 10 or fg == 14)
end

local function breakTileAt(tx, ty)
    if not isClearableTile(tx, ty) then return true end
    local standY = math.max(0, ty - 1)
    if not moveSafeTo(tx, standY) then
        moveSafeTo(math.max(0, tx - 1), ty)
    end
    local pDelay = tonumber(DF.CFG.punch_delay) or 170
    for _ = 1, 12 do
        if not DF.STATE.running then return false end
        if not isClearableTile(tx, ty) then return true end
        rawAction(tx, ty, 18)
        safeSleep(pDelay)
    end
    return true
end

local function restockPlatform(farmRow)
    local platID = tonumber(DF.CFG.platform_id) or 102
    if getInvCount(platID) >= 5 then return true end
    local storages = getStorageList()
    if #storages == 0 then
        addLog("[DF] Platform habis & belum ada World Storage!")
        return false
    end
    for _, st in ipairs(storages) do
        if not DF.STATE.running then return false end
        if warpToWorld(st.name, st.door) then
            safeSleep(600)
            if editToggle then pcall(editToggle, "Auto Collect", true) end
            local getObjs = getObjects or getObjectList
            local okO, objs = getObjs and pcall(getObjs) or false, nil
            if okO and type(objs) == "table" then
                for _, o in pairs(objs) do
                    if not DF.STATE.running or getInvCount(platID) >= 120 then break end
                    local oid = tonumber(o and (o.itemid or o.itemId or o.item_id or 0)) or 0
                    if o and o.id and oid == platID then
                        local rx = (o.pos and o.pos.x) or o.posX or o.x or 0
                        local ry = (o.pos and o.pos.y) or o.posY or o.y or 0
                        moveSafeTo(math.floor((rx + 10) / 32), math.floor((ry + 10) / 32))
                        if sendPacketRaw then pcall(sendPacketRaw, false, { type = 11, value = o.id, x = rx, y = ry }) end
                        safeSleep(160)
                    end
                end
            end
            if getInvCount(platID) >= 1 then
                return warpToWorld(farmRow.name, farmRow.door)
            end
        end
    end
    return false
end

local function processDirtFarmWorld(row)
    row.status = "Warping..."
    DF.STATE.status_text = "Warp: " .. row.name
    if not warpToWorld(row.name, row.door) then
        row.status = "Inaccessible"
        DF.saveData()
        return false
    end
    safeSleep(500)

    -- 1. Clear sisi pinggir X = 0, 1, 98, 99
    if DF.CFG.clear_side then
        row.status = "Clear Sides..."
        DF.STATE.status_text = row.name .. " Clear Sisi"
        for _, sx in ipairs({ 0, 1, 98, 99 }) do
            for sy = 1, 53 do
                if not DF.STATE.running then return false end
                if isClearableTile(sx, sy) then
                    breakTileAt(sx, sy)
                    checkAutoTrash()
                end
            end
        end
    end

    -- 2. Clear lorong tanam (baris ganjil Y = 25, 27, ..., 53)
    if DF.CFG.clear_rows then
        local goingRight = true
        for sy = 25, 53, 2 do
            if not DF.STATE.running then return false end
            row.status = "Clear Y=" .. tostring(sy)
            DF.STATE.status_text = row.name .. " Clear Y=" .. tostring(sy)
            local xStart = goingRight and 2 or 97
            local xEnd   = goingRight and 97 or 2
            local xStep  = goingRight and 1 or -1
            for sx = xStart, xEnd, xStep do
                if not DF.STATE.running then return false end
                if isClearableTile(sx, sy) then
                    breakTileAt(sx, sy)
                    checkAutoTrash()
                end
            end
            goingRight = not goingRight
        end
    end

    -- 3. Pasang Wooden Platform di tangga kiri (X=1) & kanan (X=98) baris genap (Y=2..52)
    if DF.CFG.place_platform then
        local platID = tonumber(DF.CFG.platform_id) or 102
        local pDelay = tonumber(DF.CFG.place_delay) or 170
        row.status = "Place Plat..."
        DF.STATE.status_text = row.name .. " Platform"
        for _, px in ipairs({ 1, 98 }) do
            for py = 2, 52, 2 do
                if not DF.STATE.running then return false end
                local t = getTileSafe(px, py)
                if t and (tonumber(t.fg) or 0) == 0 then
                    if getInvCount(platID) <= 0 then
                        if not restockPlatform(row) then
                            row.status = "No Plat"
                            DF.saveData()
                            return false
                        end
                    end
                    if moveSafeTo(px, math.max(0, py - 1)) then
                        rawAction(px, py, platID)
                        safeSleep(pDelay)
                    end
                end
            end
        end
    end

    row.status = "Done"
    DF.saveData()
    addLog("[Selesai] Dirt Farm " .. row.name .. " tuntas!")
    return true
end

local function mainLoop()
    DF.STATE.running = true
    applyCheats()
    addLog("Auto Dirt Farm dimulai.")
    while DF.STATE.running do
        for _, row in ipairs(DF.STATE.rows) do
            if not DF.STATE.running then break end
            if row.status ~= "Done" and row.status ~= "Inaccessible" then
                processDirtFarmWorld(row)
                safeSleep(400)
            end
        end
        if not DF.STATE.running then break end
        if DF.CFG.loop_enabled and #DF.STATE.rows > 0 then
            for _, r in ipairs(DF.STATE.rows) do
                if r.status ~= "Inaccessible" then r.status = "Ready" end
            end
            DF.saveData()
            safeSleep(2500)
        else
            break
        end
    end
    DF.STATE.running = false
    DF.STATE.enabled = false
    DF.STATE.status_text = "Idle"
    addLog("Auto Dirt Farm berhenti.")
end

function DF.start()
    if DF.STATE.running then return end
    if #DF.STATE.rows == 0 then
        addLogUI("Daftar world Dirt Farm kosong!")
        DF.STATE.status_text = "List Kosong"
        DF.STATE.enabled = false
        return
    end
    DF.STATE.enabled = true
    local function safeRunner()
        local ok, err = xpcall(mainLoop, function(e)
            return tostring(e) .. "\n" .. (debug and debug.traceback and debug.traceback() or "")
        end)
        if not ok then
            addLog("`4[DF Crash] `w" .. tostring(err))
            DF.STATE.running = false
            DF.STATE.enabled = false
            DF.STATE.status_text = "Error"
        end
    end
    if runCoroutine then pcall(runCoroutine, safeRunner)
    else coroutine.resume(coroutine.create(safeRunner)) end
end

function DF.stop()
    DF.STATE.running = false
    DF.STATE.enabled = false
    DF.STATE.status_text = "Stopped"
end

-- ============================================================================
-- 3. UI RENDERER (SUB-MENU ATAS: List World | Storage & Tool | Settings | Logs)
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
    ImGui.Text("Enable:")
    ImGui.SameLine()
    if autoBtn(DF.STATE.enabled and "  ON  ##df_en" or "  OFF  ##df_en") then
        if DF.STATE.enabled then DF.stop() else DF.start() end
    end
    ImGui.SameLine()
    ImGui.Text(" | Loop:")
    ImGui.SameLine()
    if autoBtn(DF.CFG.loop_enabled and "  ON  ##df_lp" or "  OFF  ##df_lp") then
        DF.CFG.loop_enabled = not DF.CFG.loop_enabled
        DF.saveData()
    end
    ImGui.SameLine()
    if autoBtn("Remove Inaccessible##df") then
        local kept, rem = {}, 0
        for _, r in ipairs(DF.STATE.rows) do
            if tostring(r.status):lower():find("inaccessible", 1, true) then rem = rem + 1
            else table.insert(kept, r) end
        end
        DF.STATE.rows = kept; DF.STATE.selected_idx = 0; DF.saveData()
        uiNotice = "Dihapus " .. tostring(rem) .. " world inaccessible."
    end

    ImGui.Text(string.format("Status: %s | World: %d | Platform ID: %d",
        tostring(DF.STATE.status_text), #DF.STATE.rows, tonumber(DF.CFG.platform_id) or 102))
    if uiNotice ~= "" then ImGui.Text("Info: " .. uiNotice) end

    ImGui.Separator()

    if ImGui.BeginTable("BorenDFTable", 3) then
        ImGui.TableSetupColumn("World Name")
        ImGui.TableSetupColumn("Door ID")
        ImGui.TableSetupColumn("Status")
        ImGui.TableHeadersRow()

        if #DF.STATE.rows == 0 then
            ImGui.TableNextRow()
            ImGui.TableSetColumnIndex(0); ImGui.Text("(Kosong)")
            ImGui.TableSetColumnIndex(1); ImGui.Text("-")
            ImGui.TableSetColumnIndex(2); ImGui.Text("Tambah di bawah")
        else
            for i, r in ipairs(DF.STATE.rows) do
                ImGui.TableNextRow()
                ImGui.TableSetColumnIndex(0)
                local sel = (DF.STATE.selected_idx == i)
                if autoBtn((sel and "> " or "") .. tostring(r.name) .. "##dfr" .. tostring(i)) then
                    DF.STATE.selected_idx = sel and 0 or i
                end
                ImGui.TableSetColumnIndex(1); ImGui.Text(r.door ~= "" and r.door or "-")
                ImGui.TableSetColumnIndex(2); ImGui.Text(tostring(r.status or "Ready"))
            end
        end
        ImGui.EndTable()
    end

    ImGui.Separator()
    ImGui.Text("Tambah World DF (Format WORLD:DOORID):")
    ImGui.PushItemWidth(math.max(160, w - 12))
    local ch, nv = ImGui.InputText("##df_add_w", tostring(addWorldBuf or ""), 256)
    ImGui.PopItemWidth()
    if ch and type(nv) == "string" then addWorldBuf = nv end

    if autoBtn(" + Add World ##df") then
        local p = parseWorldLine(addWorldBuf)
        if p then
            table.insert(DF.STATE.rows, p); addWorldBuf = ""; DF.saveData()
            addLogUI("World DF ditambah: " .. p.name)
            uiNotice = "Ditambahkan: " .. p.name
        else
            uiNotice = "Format: WORLD:DOORID"
        end
    end
    ImGui.SameLine()
    if autoBtn(" + World Ini ##df") then
        local curW = getCurrentWorldSafe()
        if curW ~= "" and curW ~= "EXIT" then addWorldBuf = curW .. ":" ; uiNotice = "Terisi " .. curW
        else uiNotice = "Masuk ke world dulu!" end
    end
    ImGui.SameLine()
    if autoBtn(" - Hapus ##df") then
        local idx = DF.STATE.selected_idx
        if idx < 1 or idx > #DF.STATE.rows then idx = #DF.STATE.rows end
        if idx >= 1 and idx <= #DF.STATE.rows then
            local rem = table.remove(DF.STATE.rows, idx)
            DF.STATE.selected_idx = 0; DF.saveData()
            uiNotice = "Dihapus: " .. tostring(rem and rem.name or "")
        end
    end
    ImGui.SameLine()
    if autoBtn(" Save ##df") then DF.saveData(); uiNotice = "Tersimpan " .. tostring(#DF.STATE.rows) .. " world!" end

    if autoBtn(" Import ##df") then
        local clip = ""
        if ImGui.GetClipboardText then local ok, c = pcall(ImGui.GetClipboardText); if ok and type(c) == "string" then clip = c end end
        local n = 0
        for line in clip:gmatch("[^\r\n]+") do
            local p = parseWorldLine(line)
            if p then table.insert(DF.STATE.rows, p); n = n + 1 end
        end
        if n > 0 then DF.saveData(); uiNotice = "Import " .. tostring(n) .. " world!" else uiNotice = "Clipboard kosong/invalid." end
    end
    ImGui.SameLine()
    if autoBtn(" Export ##df") then
        local out = {}
        for _, r in ipairs(DF.STATE.rows) do table.insert(out, r.door ~= "" and (r.name .. ":" .. r.door) or r.name) end
        if ImGui.SetClipboardText then pcall(ImGui.SetClipboardText, table.concat(out, "\n")); uiNotice = "Export " .. tostring(#out) .. " world!" end
    end
    ImGui.SameLine()
    if autoBtn(" Reset Status ##df") then
        for _, r in ipairs(DF.STATE.rows) do r.status = "Ready" end
        DF.saveData(); uiNotice = "Status di-reset ke Ready."
    end
end

local function renderStorageSub()
    local w = availX()
    local storages = getStorageList()
    ImGui.Text("Storage Platform / Tool (" .. tostring(#storages) .. "):")
    if uiNotice ~= "" then ImGui.Text("Info: " .. uiNotice) end

    if ImGui.BeginTable("BorenDFStorTable", 2) then
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
                local sel = (DF.STATE.selected_st == i)
                if autoBtn((sel and "> " or "") .. st.name .. "##dfst" .. tostring(i)) then
                    DF.STATE.selected_st = sel and 0 or i
                end
                ImGui.TableSetColumnIndex(1); ImGui.Text(st.door ~= "" and st.door or "-")
            end
        end
        ImGui.EndTable()
    end

    ImGui.Separator()
    ImGui.Text("Tambah Storage (WORLD:DOORID):")
    ImGui.PushItemWidth(math.max(160, w - 12))
    local ch, nv = ImGui.InputText("##df_add_st", tostring(addStorageBuf or ""), 256)
    ImGui.PopItemWidth()
    if ch and type(nv) == "string" then addStorageBuf = nv end

    if autoBtn(" + Add Storage ##df") then
        local p = parseWorldLine(addStorageBuf)
        if p then
            table.insert(storages, { name = p.name, door = p.door })
            setStorageList(storages); addStorageBuf = ""; uiNotice = "Storage ditambah: " .. p.name
        else uiNotice = "Format: WORLD:DOORID" end
    end
    ImGui.SameLine()
    if autoBtn(" - Hapus ##dfst") then
        local idx = DF.STATE.selected_st
        if idx < 1 or idx > #storages then idx = #storages end
        if idx >= 1 and idx <= #storages then
            table.remove(storages, idx); DF.STATE.selected_st = 0; setStorageList(storages); uiNotice = "Storage dihapus."
        end
    end
end

local function renderSettingsSub()
    ImGui.Text("Pengaturan Dirt Farm")
    ImGui.Separator()
    ImGui.Text("Clear Sisi Pinggir:"); ImGui.SameLine()
    if autoBtn(DF.CFG.clear_side and "  ON  ##dfc1" or "  OFF  ##dfc1") then DF.CFG.clear_side = not DF.CFG.clear_side; DF.saveData() end

    ImGui.Text("Clear Lorong Baris:"); ImGui.SameLine()
    if autoBtn(DF.CFG.clear_rows and "  ON  ##dfc2" or "  OFF  ##dfc2") then DF.CFG.clear_rows = not DF.CFG.clear_rows; DF.saveData() end

    ImGui.Text("Pasang Platform (102):"); ImGui.SameLine()
    if autoBtn(DF.CFG.place_platform and "  ON  ##dfc3" or "  OFF  ##dfc3") then DF.CFG.place_platform = not DF.CFG.place_platform; DF.saveData() end

    ImGui.Text("Auto Trash Sampah:"); ImGui.SameLine()
    if autoBtn(DF.CFG.auto_trash and "  ON  ##dfc4" or "  OFF  ##dfc4") then DF.CFG.auto_trash = not DF.CFG.auto_trash; DF.saveData() end

    ImGui.Text("ModFly:"); ImGui.SameLine()
    if autoBtn(DF.CFG.use_modfly and "  ON  ##dfc5" or "  OFF  ##dfc5") then DF.CFG.use_modfly = not DF.CFG.use_modfly; DF.saveData() end

    ImGui.Separator()
    ImGui.Text("Punch Delay: " .. tostring(DF.CFG.punch_delay) .. " ms"); ImGui.SameLine()
    if autoBtn(" -20 ##dfp1") then DF.CFG.punch_delay = math.max(80, (tonumber(DF.CFG.punch_delay) or 170) - 20); DF.saveData() end
    ImGui.SameLine()
    if autoBtn(" +20 ##dfp2") then DF.CFG.punch_delay = math.min(400, (tonumber(DF.CFG.punch_delay) or 170) + 20); DF.saveData() end

    ImGui.Text("Place Delay: " .. tostring(DF.CFG.place_delay) .. " ms"); ImGui.SameLine()
    if autoBtn(" -20 ##dfl1") then DF.CFG.place_delay = math.max(80, (tonumber(DF.CFG.place_delay) or 170) - 20); DF.saveData() end
    ImGui.SameLine()
    if autoBtn(" +20 ##dfl2") then DF.CFG.place_delay = math.min(400, (tonumber(DF.CFG.place_delay) or 170) + 20); DF.saveData() end
end

local function renderLogsSub()
    if autoBtn(" Clear Logs ##df") then DF.STATE.logs = {} end
    ImGui.Separator()
    if #DF.STATE.logs == 0 then ImGui.Text("Belum ada log Dirt Farm.")
    else
        for i = 1, math.min(20, #DF.STATE.logs) do ImGui.TextWrapped(tostring(DF.STATE.logs[i])) end
    end
end

function DF.render(hub)
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

function DF.init(hub)
    HUB_REF = hub
    DF.loadData()
end

return DF
