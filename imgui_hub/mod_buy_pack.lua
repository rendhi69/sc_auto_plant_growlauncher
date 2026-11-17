-- ============================================================================
-- BOREN HUB IMGUI - MODUL AUTO BUY PACK & ANTI-RETAKE DROP (ENGINE + UI)
-- File: imgui_hub/mod_buy_pack.lua
-- Database Pack diambil dinamis dari:
--   https://raw.githubusercontent.com/rendhi69/data-_id_item/main/debugpack.txt
-- ============================================================================

local BP = {
    id    = "buy_pack",
    label = "Buy Pack",
}

local DEBUGPACK_URL = "https://raw.githubusercontent.com/rendhi69/data-_id_item/main/debugpack.txt"

-- Fallback ringkas jika offline
local FALLBACK_PACKS = [[
World Lock:world_lock:2000:242
World Lock Pack:world_lock_10_pack:20000:242
Small Seed Pack:5seed:100:5706
Small Seed Pack Collection:ssp_10_pack:1000:5706
Rare Seed Pack:rare_seed:1000:2293
Surgery Starter Pack:surg_starter_pack:5000:1248,1246,1244,1242,8558,1256,1240
Surgical Kit:surgical_kit:12000:9310,4316,4310,1270,1258,1268,1260,4308,4318,4312,4314,1264,1266,1263,4296
Vending Machine:vending_machine:8000:2978
DigiVendMachine:digi_vend:12000:9268
Signal Jammer:signal_jammer:2000:226
Builder's Lock:builders_lock:50000:4994
Small Lock:small_lock:50:202
Big Lock:big_lock:200:204
Huge Lock:huge_lock:500:206
5-pack of Grow Spray Fertilizer:grow_spray:200:228
Deluxe Grow Spray:deluxe_grow_spray:900:1778
City Pack:city_pack:8000:1008,1002,988,1006,1004,998,996,990,992,986,994
Fishin' Pack:fishin_pack:10000:2912,3044,3004,3002,2914,5524,5522
Crime Wave:crime_wave:5000:2293
Geiger Counter:geiger:25000:2204
]]

BP.CFG = {
    pack_name     = "World Lock",
    pack_id       = "world_lock",
    pack_price    = 2000,
    pack_items    = "242",
    target_qty    = 0,         -- 0 = beli sampai gems habis
    save_world    = "",        -- Format WORLD:DOOR
    auto_drop     = true,
    drop_thresh   = 100,       -- Drop jika salah satu item >= 100 atau selesai beli
    buy_delay     = 900,
    drop_delay    = 450,
    warp_delay    = 3500,
}

BP.STATE = {
    enabled          = false,
    running          = false,
    anti_take_active = false,
    buying_now       = false,
    pending_drop_id  = 0,
    pending_drop_amt = 0,
    bought_count     = 0,
    status_text      = "Idle",
    pack_db          = {},     -- { { name=..., id=..., price=..., items=... }, ... }
    logs             = {},
}

local HUB_REF = nil
local activeSub = "main" -- "main" | "search" | "settings" | "logs"
local searchBuf = ""
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
-- 1. SAFE HELPERS, PARSER DEBUGPACK & PERSISTENCE
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
    if isSystemWindows() then CACHED_PATH = "boren_hub_buypack_data.txt"; return CACHED_PATH end
    local dirs = {
        "/storage/emulated/0/Android/media/launcher.powerkuy.growlauncher/ScriptLua/",
        "/storage/emulated/0/Android/data/launcher.powerkuy.growlauncher/files/ScriptLua/",
        "/storage/emulated/0/Download/",
    }
    for _, d in ipairs(dirs) do
        local p = d .. "boren_hub_buypack_data.txt"
        local okR, fR = pcall(io.open, p, "r")
        if okR and fR then fR:close(); CACHED_PATH = p; return p end
        local okW, fW = pcall(io.open, p, "a")
        if okW and fW then fW:close(); CACHED_PATH = p; return p end
    end
    CACHED_PATH = "boren_hub_buypack_data.txt"
    return CACHED_PATH
end

local function addLogUI(msg)
    local clean = tostring(msg or ""):gsub("`.", "")
    local ts = ""
    if os and type(os.date) == "function" then
        local okD, d = pcall(os.date, "%H:%M:%S")
        if okD and d then ts = "[" .. d .. "] " end
    end
    local entry = ts .. "[PACK] " .. clean
    table.insert(BP.STATE.logs, 1, entry)
    if #BP.STATE.logs > 60 then table.remove(BP.STATE.logs) end
    if HUB_REF and HUB_REF.addLog then HUB_REF.addLog(entry) end
end

local function addLog(msg)
    addLogUI(msg)
    if LogToConsole then pcall(LogToConsole, "`e[Boren Pack] `w" .. tostring(msg or "")) end
end

local function safeSleep(ms)
    ms = tonumber(ms) or 50
    if ms < 10 then ms = 10 end
    local fn = sleep or CSleep
    if fn then pcall(fn, ms) end
end

local function parseDebugPackText(raw)
    local list = {}
    if not raw or raw == "" then return list end
    for line in raw:gmatch("[^\r\n]+") do
        local t = trimStr(line)
        if t ~= "" and not t:match("^%-%-") and not t:match("^packs%s*=") and t ~= "]]" then
            local p1, p2, p3, p4 = t:match("^([^:]+):([^:]+):([^:]*):(.*)$")
            if p1 and p2 then
                local name = trimStr(p1)
                local code = trimStr(p2)
                local price = tonumber(trimStr(p3)) or 0
                local items = trimStr(p4)
                if name ~= "" and code ~= "" then
                    table.insert(list, { name = name, id = code, price = price, items = items })
                end
            end
        end
    end
    return list
end

function BP.loadPackDatabase()
    local raw = nil
    if HUB_REF and HUB_REF.fetchRawUrl then
        raw = HUB_REF.fetchRawUrl(DEBUGPACK_URL)
    elseif fetch then
        local ok, res = pcall(fetch, DEBUGPACK_URL)
        if ok and type(res) == "string" and res:find("world_lock", 1, true) then
            raw = res
        end
    end
    local parsed = parseDebugPackText(raw)
    if #parsed == 0 then
        parsed = parseDebugPackText(FALLBACK_PACKS)
    end
    BP.STATE.pack_db = parsed
end

function BP.saveData()
    local lines = {
        "PNAME=" .. tostring(BP.CFG.pack_name or ""),
        "PID=" .. tostring(BP.CFG.pack_id or ""),
        "PPRICE=" .. tostring(tonumber(BP.CFG.pack_price) or 0),
        "PITEMS=" .. tostring(BP.CFG.pack_items or ""),
        "QTY=" .. tostring(tonumber(BP.CFG.target_qty) or 0),
        "SAVEW=" .. tostring(BP.CFG.save_world or ""),
        "ADROP=" .. (BP.CFG.auto_drop and "1" or "0"),
        "BDELAY=" .. tostring(tonumber(BP.CFG.buy_delay) or 900),
        "DDELAY=" .. tostring(tonumber(BP.CFG.drop_delay) or 450),
    }
    local ok, f = pcall(io.open, getDataPath(), "w")
    if ok and f then f:write(table.concat(lines, "\n")); f:close() end
end

function BP.loadData()
    local ok, f = pcall(io.open, getDataPath(), "r")
    if not ok or not f then return end
    local txt = f:read("*a"); f:close()
    if not txt or txt == "" then return end
    for line in txt:gmatch("[^\r\n]+") do
        local k, v = line:match("^([A-Z]+)=(.*)$")
        if k == "PNAME" then BP.CFG.pack_name = trimStr(v)
        elseif k == "PID" then BP.CFG.pack_id = trimStr(v)
        elseif k == "PPRICE" then BP.CFG.pack_price = tonumber(v) or 0
        elseif k == "PITEMS" then BP.CFG.pack_items = trimStr(v)
        elseif k == "QTY" then BP.CFG.target_qty = tonumber(v) or 0
        elseif k == "SAVEW" then BP.CFG.save_world = trimStr(v)
        elseif k == "ADROP" then BP.CFG.auto_drop = (v ~= "0")
        elseif k == "BDELAY" then BP.CFG.buy_delay = tonumber(v) or 900
        elseif k == "DDELAY" then BP.CFG.drop_delay = tonumber(v) or 450
        end
    end
end

-- ============================================================================
-- 2. GAME HELPERS & AUTO BUY / DROP ENGINE
-- ============================================================================
local function getGemsSafe()
    if getGems then
        local ok, g = pcall(getGems)
        if ok and tonumber(g) then return math.floor(tonumber(g)) end
    end
    return 0
end

local function getCurrentWorldSafe()
    local fn = getCurrentWorldName or getWorld or getCurrentWorld
    if not fn then return "" end
    local ok, res = pcall(fn)
    if ok and type(res) == "string" then return res:upper() end
    if ok and type(res) == "table" and res.name then return tostring(res.name):upper() end
    return ""
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

local function warpToSaveWorld()
    local raw = trimStr(BP.CFG.save_world)
    if raw == "" then return true end
    raw = raw:gsub("|", ":")
    local wName, dId = raw:match("^([^:]+):(.*)$")
    wName = trimStr(wName or raw):upper()
    dId   = trimStr(dId or ""):upper()
    if wName == "" then return true end
    if getCurrentWorldSafe() == wName and dId == "" then return true end

    local joinStr = (dId ~= "") and (wName .. "|" .. dId) or wName
    for _ = 1, 2 do
        if not BP.STATE.running then return false end
        if sendPacket then pcall(sendPacket, 3, "action|join_request\nname|" .. joinStr .. "\ninvitedWorld|0")
        elseif growtopia and growtopia.warpTo then pcall(growtopia.warpTo, joinStr) end
        local w, lim = 0, math.max(2000, tonumber(BP.CFG.warp_delay) or 3500)
        while w < lim and BP.STATE.running do
            safeSleep(250); w = w + 250
            if getCurrentWorldSafe() == wName then safeSleep(600); return true end
        end
    end
    return getCurrentWorldSafe() == wName
end

local function getPackItemIDList()
    local ids = {}
    for num in tostring(BP.CFG.pack_items or ""):gmatch("%d+") do
        local id = tonumber(num)
        if id and id > 0 then table.insert(ids, id) end
    end
    return ids
end

local function dropPackItemsSafe()
    if not BP.CFG.auto_drop then return end
    local ids = getPackItemIDList()
    if #ids == 0 then return end

    BP.STATE.anti_take_active = true
    if editToggle then pcall(editToggle, "Auto Collect", false) end

    local dDelay = math.max(250, tonumber(BP.CFG.drop_delay) or 450)
    for _, itemID in ipairs(ids) do
        if not BP.STATE.running then break end
        local amt = getInvCount(itemID)
        if amt > 0 then
            BP.STATE.pending_drop_id = itemID
            BP.STATE.pending_drop_amt = amt
            if growtopia and growtopia.confirmDropItem then
                pcall(growtopia.confirmDropItem, itemID, amt)
            elseif sendPacket then
                pcall(sendPacket, 2, string.format("action|drop\n|itemID|%d\n", itemID))
            end
            safeSleep(dDelay)
            BP.STATE.pending_drop_id = 0
            BP.STATE.pending_drop_amt = 0
        end
    end

    safeSleep(200)
    BP.STATE.anti_take_active = false
end

local function mainLoop()
    BP.STATE.running = true
    BP.STATE.bought_count = 0
    local packCode = trimStr(BP.CFG.pack_id)
    if packCode == "" then
        addLog("[Peringatan] Pack ID kosong! Pilih pack di tab 'Cari Pack'.")
        BP.STATE.running = false; BP.STATE.enabled = false; return
    end

    BP.STATE.status_text = "Warp Save..."
    if trimStr(BP.CFG.save_world) ~= "" then
        if not warpToSaveWorld() then
            addLog("[Gagal] Tidak bisa masuk World Save: " .. tostring(BP.CFG.save_world))
            BP.STATE.status_text = "Gagal Warp"
            BP.STATE.running = false; BP.STATE.enabled = false; return
        end
    end

    local targetQty = math.max(0, math.floor(tonumber(BP.CFG.target_qty) or 0))
    local price = math.max(0, math.floor(tonumber(BP.CFG.pack_price) or 0))
    local bDelay = math.max(400, tonumber(BP.CFG.buy_delay) or 900)
    local ids = getPackItemIDList()

    addLog(string.format("Mulai Auto Buy: %s (%s) | Target: %s",
        tostring(BP.CFG.pack_name), packCode, targetQty > 0 and tostring(targetQty) or "Habiskan Gems"))

    while BP.STATE.running do
        if targetQty > 0 and BP.STATE.bought_count >= targetQty then
            addLog("Target pembelian tercapai (" .. tostring(BP.STATE.bought_count) .. " pack)!")
            break
        end

        local curGems = getGemsSafe()
        if price > 0 and curGems > 0 and curGems < price then
            addLog(string.format("Gems tidak cukup (%d < %d). Selesai!", curGems, price))
            break
        end

        BP.STATE.buying_now = true
        BP.STATE.status_text = string.format("Buy #%d (%s)", BP.STATE.bought_count + 1, packCode)
        if sendPacket then
            pcall(sendPacket, 2, "action|buy\nitem|" .. packCode .. "\n")
        end
        safeSleep(bDelay)
        BP.STATE.buying_now = false
        BP.STATE.bought_count = BP.STATE.bought_count + 1

        -- Cek apakah ada item pack yang sudah mendekati penuh di backpack -> Drop!
        if BP.CFG.auto_drop and #ids > 0 then
            local needDrop = false
            for _, id in ipairs(ids) do
                if getInvCount(id) >= (tonumber(BP.CFG.drop_thresh) or 100) then
                    needDrop = true; break
                end
            end
            if needDrop then
                BP.STATE.status_text = "Dropping..."
                dropPackItemsSafe()
            end
        end
    end

    -- Drop sisa item di akhir sesi
    if BP.CFG.auto_drop and BP.STATE.bought_count > 0 then
        BP.STATE.status_text = "Final Drop..."
        dropPackItemsSafe()
    end

    BP.STATE.anti_take_active = false
    BP.STATE.buying_now = false
    BP.STATE.running = false
    BP.STATE.enabled = false
    BP.STATE.status_text = "Selesai (" .. tostring(BP.STATE.bought_count) .. ")"
    addLog("Auto Buy Pack selesai. Total beli: " .. tostring(BP.STATE.bought_count))
end

function BP.start()
    if BP.STATE.running then return end
    if trimStr(BP.CFG.pack_id) == "" then
        addLogUI("Pack ID kosong! Pilih di tab Cari Pack.")
        BP.STATE.status_text = "Pilih Pack!"
        BP.STATE.enabled = false
        return
    end
    BP.STATE.enabled = true
    local function safeRunner()
        local ok, err = xpcall(mainLoop, function(e)
            return tostring(e) .. "\n" .. (debug and debug.traceback and debug.traceback() or "")
        end)
        if not ok then
            addLog("`4[BuyPack Crash] `w" .. tostring(err))
            BP.STATE.anti_take_active = false
            BP.STATE.buying_now = false
            BP.STATE.running = false
            BP.STATE.enabled = false
            BP.STATE.status_text = "Error"
        end
    end
    if runCoroutine then pcall(runCoroutine, safeRunner)
    else coroutine.resume(coroutine.create(safeRunner)) end
end

function BP.stop()
    BP.STATE.running = false
    BP.STATE.enabled = false
    BP.STATE.anti_take_active = false
    BP.STATE.buying_now = false
    BP.STATE.status_text = "Stopped"
end

-- Hook Variant untuk auto-confirm drop_item & suppress popup store saat buying
function BP.handleVariant(var)
    if not BP.STATE.running or type(var) ~= "table" then return false end
    local v0 = tostring(var.v1 or var[0] or var[1] or "")
    if v0 ~= "OnDialogRequest" then return false end
    local payload = tostring(var.v2 or var[1] or var[2] or "")
    local low = payload:lower()

    if BP.STATE.pending_drop_id > 0 and low:find("drop_item", 1, true) then
        local dName = payload:match("end_dialog|([^|\r\n]+)") or "drop_item"
        if sendPacket then
            pcall(sendPacket, 2, string.format("action|dialog_return\ndialog_name|%s\nitemID|%d|\ncount|%d\n",
                trimStr(dName), BP.STATE.pending_drop_id, BP.STATE.pending_drop_amt))
        end
        return true
    end
    return false
end

-- ============================================================================
-- 3. UI RENDERER (Buy & Drop | Cari Pack | Settings | Logs)
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

local function renderMainSub()
    local w = availX()
    ImGui.Text("Enable:"); ImGui.SameLine()
    if autoBtn(BP.STATE.enabled and "  ON  ##bp_en" or "  OFF  ##bp_en") then
        if BP.STATE.enabled then BP.stop() else BP.start() end
    end
    ImGui.SameLine()
    ImGui.Text(string.format(" | Gems: %d | Beli: %d | %s",
        getGemsSafe(), tonumber(BP.STATE.bought_count) or 0, tostring(BP.STATE.status_text)))

    if uiNotice ~= "" then ImGui.Text("Info: " .. uiNotice) end
    ImGui.Separator()

    if ImGui.BeginTable("BorenPackMainOpts", 2) then
        renderOptRow("Pack Aktif", function()
            ImGui.Text(tostring(BP.CFG.pack_name) .. " (" .. tostring(BP.CFG.pack_id) .. ")")
        end)
        renderOptRow("Harga Pack", function()
            ImGui.Text(tostring(BP.CFG.pack_price) .. " Gems")
        end)
        renderOptRow("Item IDs", function()
            ImGui.Text(tostring(BP.CFG.pack_items))
        end)
        renderOptRow("Target Beli (0=All)", function()
            renderNumInput("bp_qty", BP.CFG.target_qty, 0, 9999, 10, "", function(v)
                BP.CFG.target_qty = v; BP.saveData()
            end)
            ImGui.SameLine()
            if autoBtn(" All ##bpq0") then
                BP.CFG.target_qty = 0; numBufs["bp_qty"] = "0"; BP.saveData()
            end
        end)
        ImGui.EndTable()
    end

    ImGui.Text("Pack ID (Debug Name):")
    ImGui.PushItemWidth(math.max(160, w - 12))
    local chP, nP = safeInputText("##bp_pid", BP.CFG.pack_id, 128)
    ImGui.PopItemWidth()
    if chP then BP.CFG.pack_id = nP; BP.saveData() end

    ImGui.Text("World Save Drop:")
    local swRaw = tostring(BP.CFG.save_world or ""):gsub("|", ":")
    local swName, swDoor = swRaw:match("^([^:]+):(.*)$")
    if not swName then swName = swRaw; swDoor = "" end
    if ImGui.BeginTable("BorenPackSaveW", 2) then
        ImGui.TableSetupColumn("World Save")
        ImGui.TableSetupColumn("Door ID")
        ImGui.TableHeadersRow()
        ImGui.TableNextRow()
        ImGui.TableSetColumnIndex(0)
        ImGui.PushItemWidth(math.max(110, math.floor(w * 0.46)))
        local chWN, newWN = safeInputText("##bp_sw_n", swName, 128)
        ImGui.PopItemWidth()
        if chWN then
            swName = newWN
            BP.CFG.save_world = (swDoor ~= "") and (swName .. ":" .. swDoor) or swName
            BP.saveData()
        end

        ImGui.TableSetColumnIndex(1)
        ImGui.PushItemWidth(math.max(90, math.floor(w * 0.44)))
        local chWD, newWD = safeInputText("##bp_sw_d", swDoor, 128)
        ImGui.PopItemWidth()
        if chWD then
            swDoor = newWD
            BP.CFG.save_world = (swDoor ~= "") and (swName .. ":" .. swDoor) or swName
            BP.saveData()
        end
        ImGui.EndTable()
    end

    if autoBtn(" + World Ini ##bp") then
        local curW = getCurrentWorldSafe()
        if curW ~= "" and curW ~= "EXIT" then
            BP.CFG.save_world = (swDoor ~= "") and (curW .. ":" .. swDoor) or curW
            BP.saveData(); uiNotice = "Save World: " .. curW
        else uiNotice = "Masuk ke world dulu!" end
    end
    ImGui.SameLine()
    if autoBtn(" Cari Pack (" .. tostring(#BP.STATE.pack_db) .. ") ") then activeSub = "search" end
    ImGui.SameLine()
    if autoBtn(" Save Config ##bp") then BP.saveData(); uiNotice = "Konfigurasi Buy Pack tersimpan!" end
end

local function renderSearchSub()
    local w = availX()
    ImGui.Text("Cari Pack (Database GitHub: " .. tostring(#BP.STATE.pack_db) .. " pack):")
    ImGui.PushItemWidth(math.max(160, w - 12))
    local ch, nv = safeInputText("##bp_search", searchBuf, 128)
    ImGui.PopItemWidth()
    if ch then searchBuf = nv end

    local q = trimStr(searchBuf):lower()

    if ImGui.BeginTable("BorenPackSearchTable", 4) then
        ImGui.TableSetupColumn("Nama Pack")
        ImGui.TableSetupColumn("Pack ID")
        ImGui.TableSetupColumn("Gems")
        ImGui.TableSetupColumn("Aksi")
        ImGui.TableHeadersRow()

        local shown = 0
        for i, pk in ipairs(BP.STATE.pack_db) do
            if q == "" or pk.name:lower():find(q, 1, true) or pk.id:lower():find(q, 1, true) then
                shown = shown + 1
                if shown > 15 then break end
                ImGui.TableNextRow()
                ImGui.TableSetColumnIndex(0); ImGui.Text(pk.name)
                ImGui.TableSetColumnIndex(1); ImGui.Text(pk.id)
                ImGui.TableSetColumnIndex(2); ImGui.Text(tostring(pk.price))
                ImGui.TableSetColumnIndex(3)
                if autoBtn("Pilih##pk" .. tostring(i)) then
                    BP.CFG.pack_name  = pk.name
                    BP.CFG.pack_id    = pk.id
                    BP.CFG.pack_price = pk.price
                    BP.CFG.pack_items = pk.items
                    BP.saveData()
                    uiNotice = "Dipilih: " .. pk.name .. " (" .. pk.id .. ")"
                    activeSub = "main"
                end
            end
        end
        if shown == 0 then
            ImGui.TableNextRow()
            ImGui.TableSetColumnIndex(0); ImGui.Text("(Tidak ditemukan)")
            ImGui.TableSetColumnIndex(1); ImGui.Text("-")
            ImGui.TableSetColumnIndex(2); ImGui.Text("-")
            ImGui.TableSetColumnIndex(3); ImGui.Text("-")
        end
        ImGui.EndTable()
    end
    ImGui.Text("Menampilkan maks 15 hasil. Ketik kata kunci untuk menyaring.")
end

local function renderSettingsSub()
    ImGui.Text("Pengaturan Buy Pack")
    ImGui.Separator()

    if ImGui.BeginTable("BorenPackSetOpts", 2) then
        renderOptRow("Auto Drop Anti-Take", function()
            if autoBtn(BP.CFG.auto_drop and "  ON  ##bpad" or "  OFF  ##bpad") then
                BP.CFG.auto_drop = not BP.CFG.auto_drop; BP.saveData()
            end
        end)
        renderOptRow("Buy Delay", function()
            renderNumInput("bp_bd", BP.CFG.buy_delay, 300, 5000, 100, "ms", function(v)
                BP.CFG.buy_delay = v; BP.saveData()
            end)
        end)
        renderOptRow("Drop Delay", function()
            renderNumInput("bp_dd", BP.CFG.drop_delay, 200, 3000, 50, "ms", function(v)
                BP.CFG.drop_delay = v; BP.saveData()
            end)
        end)
        ImGui.EndTable()
    end
end

local function renderLogsSub()
    if autoBtn(" Clear Logs ##bp") then BP.STATE.logs = {} end
    ImGui.Separator()
    if #BP.STATE.logs == 0 then ImGui.Text("Belum ada log Buy Pack.")
    else
        for i = 1, math.min(20, #BP.STATE.logs) do ImGui.TextWrapped(tostring(BP.STATE.logs[i])) end
    end
end

function BP.render(hub)
    if autoBtn(activeSub == "main" and "[ Buy & Drop ]" or "Buy & Drop") then activeSub = "main" end
    ImGui.SameLine()
    if autoBtn(activeSub == "search" and "[ Cari Pack ]" or "Cari Pack") then activeSub = "search" end
    ImGui.SameLine()
    if autoBtn(activeSub == "settings" and "[ Settings ]" or "Settings") then activeSub = "settings" end
    ImGui.SameLine()
    if autoBtn(activeSub == "logs" and "[ Logs ]" or "Logs") then activeSub = "logs" end
    ImGui.Separator()

    if activeSub == "main" then renderMainSub()
    elseif activeSub == "search" then renderSearchSub()
    elseif activeSub == "settings" then renderSettingsSub()
    else renderLogsSub() end
end

function BP.init(hub)
    HUB_REF = hub
    BP.loadData()
    BP.loadPackDatabase()
end

return BP
