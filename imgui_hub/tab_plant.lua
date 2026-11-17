-- ============================================================================
-- BOREN HUB IMGUI - MODULAR CATEGORY SIDEBAR + TOP SUB-MENU BAR
-- File: imgui_hub/tab_plant.lua
-- Struktur Layout:
--   - KIRI  : Daftar Kategori Fitur SAJA (Plant, Dirt Farm, Build Soil, dll.)
--             Tanpa Separator di kolom kiri agar panel kanan mulai rapi di atas!
--   - KANAN ATAS : Sub-menu kategori terpilih:
--                  [ List World ] [ List Storage ] [ Settings ] [ Logs ] [ Hide ]
--   - KANAN ISI  : Konten sub-menu (Automation + List & Add World, List Storage,
--                  Settings, atau Logs).
-- ============================================================================

local UI = {}

local HUB = nil
local activeFeature = "dashboard"  -- "dashboard" | "plant" | "dirt_farm" | "build_soil" | "buy_pack"
local activePlantSub = "worlds"    -- "worlds" | "storage" | "settings" | "logs"
local windowOpen = true

local addWorldBuf = ""
local addSeedBuf = "4585"
local addSpliceBuf = "0"
local addStorageBuf = ""
local addStorageDoorBuf = ""
local selectedStorageIdx = 0
local lastFrameCount = -1
local uiNotice = ""

-- Kompatibel semua versi binding ImGui.InputText Android (boolean,string / string,boolean / Android IME)
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

-- JANGAN panggil sendNotification / LogToConsole dari thread OpenGL OnDrawImGui!
-- Cukup tampilkan notifikasi instan di dalam panel ImGui agar 100% bebas crash JNI Android.
local function setNotice(msg)
    uiNotice = tostring(msg or "")
end

local function logUI(E, msg)
    if E and E.addLogUI then
        E.addLogUI(msg)
    elseif HUB and HUB.addLog then
        HUB.addLog(msg)
    end
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

local function safeWinW()
    if ImGui and ImGui.GetWindowWidth then
        local ok, w = pcall(ImGui.GetWindowWidth)
        if ok and type(w) == "number" and w > 100 then return w end
    end
    return 760
end

-- Button lebar kustom + tinggi AUTO-FIT (y = 0) agar teks tidak terpotong di Android
local function fullBtn(label, width)
    if width and width > 10 and ImVec2 then
        local ok, res = pcall(ImGui.Button, label, ImVec2(width, 0))
        if ok then return res == true end
    end
    local ok, res = pcall(ImGui.Button, label)
    return ok and (res == true)
end

-- Button ukuran otomatis mengikuti panjang & tinggi teks
local function autoBtn(label)
    local ok, res = pcall(ImGui.Button, label)
    return ok and (res == true)
end

-- ============================================================================
-- PLANT SUB-TAB 1: LIST WORLD (AUTOMATION + TABEL LIST WORLD + TAMBAH/SAVE)
-- ============================================================================
local function renderPlantWorldsSub()
    local E = HUB.plant
    if not E then
        ImGui.Text("Engine Plant belum termuat.")
        return
    end

    local availW = safeAvailX()

    -- Automation Bar: Enable | Loop | Remove Inaccessible | Status
    ImGui.Text("Enable:")
    ImGui.SameLine()
    if autoBtn(E.STATE.enabled and "  ON  ##en" or "  OFF  ##en") then
        if E.STATE.enabled then E.stop() else E.start() end
    end

    ImGui.SameLine()
    ImGui.Text(" | Loop:")
    ImGui.SameLine()
    if autoBtn(E.CFG.loop_enabled and "  ON  ##lp" or "  OFF  ##lp") then
        E.CFG.loop_enabled = not E.CFG.loop_enabled
        E.saveData()
    end

    ImGui.SameLine()
    if autoBtn("Remove Inaccessible") then
        local removed = E.removeInaccessible()
        setNotice("Dihapus " .. tostring(removed) .. " world inaccessible.")
    end

    local storages = E.getStorageList and E.getStorageList() or {}
    ImGui.Text(string.format("Status: %s | Storage: %d | World: %d",
        tostring(E.STATE.status_text or "Idle"), #storages, #E.STATE.rows))
    if uiNotice ~= "" then
        ImGui.Text("Info: " .. uiNotice)
    end

    ImGui.Separator()

    -- Tabel List World (5 Kolom)
    if ImGui.BeginTable("BorenPlantTable", 5) then
        ImGui.TableSetupColumn("Name")
        ImGui.TableSetupColumn("Door ID")
        ImGui.TableSetupColumn("Seed ID")
        ImGui.TableSetupColumn("Splice ID")
        ImGui.TableSetupColumn("Status")
        ImGui.TableHeadersRow()

        if #E.STATE.rows == 0 then
            ImGui.TableNextRow()
            ImGui.TableSetColumnIndex(0); ImGui.Text("(Kosong)")
            ImGui.TableSetColumnIndex(1); ImGui.Text("-")
            ImGui.TableSetColumnIndex(2); ImGui.Text("-")
            ImGui.TableSetColumnIndex(3); ImGui.Text("-")
            ImGui.TableSetColumnIndex(4); ImGui.Text("Tambah di bawah")
        else
            for i, row in ipairs(E.STATE.rows) do
                ImGui.TableNextRow()

                ImGui.TableSetColumnIndex(0)
                local isSel = (E.STATE.selected_idx == i)
                local prefix = isSel and "> " or ""
                if autoBtn(prefix .. tostring(row.name or "") .. "##rw" .. tostring(i)) then
                    E.STATE.selected_idx = isSel and 0 or i
                end

                ImGui.TableSetColumnIndex(1)
                ImGui.Text(row.door ~= "" and tostring(row.door) or "-")

                ImGui.TableSetColumnIndex(2)
                ImGui.Text(tostring(tonumber(row.seed_id) or 0))

                ImGui.TableSetColumnIndex(3)
                local sp = tonumber(row.splice_id) or 0
                ImGui.Text(sp > 0 and tostring(sp) or "-")

                ImGui.TableSetColumnIndex(4)
                ImGui.Text(tostring(row.status or "Ready"))
            end
        end

        ImGui.EndTable()
    end

    ImGui.Separator()

    -- Form Penambahan & Save World: dipisah jadi [World:DoorID] [Seed ID] [Splice ID] agar gampang ketik!
    ImGui.Text("Tambah World:")
    if ImGui.BeginTable("BorenPlantAddRow", 3) then
        ImGui.TableSetupColumn("World:DoorID")
        ImGui.TableSetupColumn("Seed ID")
        ImGui.TableSetupColumn("Splice ID")
        ImGui.TableHeadersRow()
        ImGui.TableNextRow()

        ImGui.TableSetColumnIndex(0)
        ImGui.PushItemWidth(math.max(110, math.floor(availW * 0.44)))
        local chA, newA = safeInputText("##plant_add_w", addWorldBuf, 256)
        ImGui.PopItemWidth()
        if chA then addWorldBuf = newA end

        ImGui.TableSetColumnIndex(1)
        ImGui.PushItemWidth(math.max(70, math.floor(availW * 0.24)))
        local chSd, newSd = safeInputText("##plant_add_sd", addSeedBuf, 64)
        ImGui.PopItemWidth()
        if chSd then addSeedBuf = newSd:gsub("[^0-9]", "") end

        ImGui.TableSetColumnIndex(2)
        ImGui.PushItemWidth(math.max(70, math.floor(availW * 0.24)))
        local chSp, newSp = safeInputText("##plant_add_sp", addSpliceBuf, 64)
        ImGui.PopItemWidth()
        if chSp then addSpliceBuf = newSp:gsub("[^0-9]", "") end

        ImGui.EndTable()
    end

    if autoBtn(" + Add World ") then
        local rawW = tostring(addWorldBuf or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local parsed = nil
        if rawW ~= "" then
            -- Jika user ketik/paste lengkap world:door:seed:splice tetap didukung; jika world:door saja gabung dgn kotak Seed & Splice
            local norm = rawW:gsub("|", ":")
            local colons = 0
            for _ in norm:gmatch(":") do colons = colons + 1 end
            if colons >= 2 then
                parsed = E.parseRowLine(norm)
            else
                local wPart, dPart = norm:match("^([^:]+):(.*)$")
                local wName = (wPart or norm):gsub("^%s+", ""):gsub("%s+$", ""):upper()
                local dId   = (dPart or ""):gsub("^%s+", ""):gsub("%s+$", ""):upper()
                local sdNum = math.floor(tonumber(addSeedBuf) or 4585)
                local spNum = math.floor(tonumber(addSpliceBuf) or 0)
                if sdNum <= 0 then sdNum = 4585 end
                if spNum < 0 then spNum = 0 end
                if wName ~= "" then
                    parsed = { name = wName, door = dId, seed_id = sdNum, splice_id = spNum, status = "Ready" }
                end
            end
        end
        if parsed then
            table.insert(E.STATE.rows, parsed)
            addWorldBuf = ""
            E.saveData()
            logUI(E, "[+] World ditambah: " .. E.formatRowLine(parsed))
            setNotice("Ditambahkan: " .. parsed.name .. " (Seed " .. tostring(parsed.seed_id) .. ", Splice " .. tostring(parsed.splice_id) .. ")")
        else
            setNotice("Isi World:DoorID dulu!")
        end
    end

    ImGui.SameLine()
    if autoBtn(" + World Ini ") then
        local curW = ""
        if getCurrentWorldName then
            local okW, wn = pcall(getCurrentWorldName)
            if okW and type(wn) == "string" then curW = wn:upper() end
        end
        if curW ~= "" and curW ~= "EXIT" then
            addWorldBuf = curW .. ":"
            setNotice("Terisi " .. curW .. ": (tambahkan Door ID lalu klik + Add World)")
        else
            setNotice("Masuk ke world terlebih dahulu!")
        end
    end

    ImGui.SameLine()
    if autoBtn(" Paste ##pl_pw") then
        if ImGui.GetClipboardText then
            local okC, resC = pcall(ImGui.GetClipboardText)
            if okC and type(resC) == "string" and resC ~= "" then
                addWorldBuf = resC:match("^[^\r\n]+") or resC
                setNotice("Paste ke World:DoorID")
            else setNotice("Clipboard kosong!") end
        end
    end

    ImGui.SameLine()
    if autoBtn(" - Hapus ") then
        local idx = E.STATE.selected_idx
        if idx < 1 or idx > #E.STATE.rows then idx = #E.STATE.rows end
        if idx >= 1 and idx <= #E.STATE.rows then
            local rem = table.remove(E.STATE.rows, idx)
            E.STATE.selected_idx = 0
            E.saveData()
            logUI(E, "[-] World dihapus: " .. tostring(rem and rem.name or ""))
            setNotice("Dihapus: " .. tostring(rem and rem.name or ""))
        end
    end

    ImGui.SameLine()
    if autoBtn(" Save ") then
        E.saveData()
        setNotice("Tersimpan " .. tostring(#E.STATE.rows) .. " world!")
    end

    if autoBtn(" Import ") then
        local clip = ""
        if ImGui.GetClipboardText then
            local okC, resC = pcall(ImGui.GetClipboardText)
            if okC and type(resC) == "string" then clip = resC end
        end
        if clip == "" then
            setNotice("Clipboard kosong!")
        else
            local added = 0
            for line in clip:gmatch("[^\r\n]+") do
                local parsed = E.parseRowLine(line)
                if parsed then
                    table.insert(E.STATE.rows, parsed)
                    added = added + 1
                end
            end
            if added > 0 then
                E.saveData()
                logUI(E, "[Import] " .. tostring(added) .. " world ditambahkan.")
                setNotice("Import " .. tostring(added) .. " world!")
            else
                setNotice("Tidak ada baris valid di clipboard.")
            end
        end
    end

    ImGui.SameLine()
    if autoBtn(" Export ") then
        local out = {}
        for _, row in ipairs(E.STATE.rows) do
            table.insert(out, E.formatRowLine(row))
        end
        if ImGui.SetClipboardText then
            pcall(ImGui.SetClipboardText, table.concat(out, "\n"))
            setNotice("Export " .. tostring(#out) .. " world ke clipboard!")
        end
    end

    ImGui.SameLine()
    if autoBtn(" Reset Status ") then
        E.resetAllStatus()
        setNotice("Semua status di-reset ke Ready.")
    end
end

-- ============================================================================
-- PLANT SUB-TAB 2: LIST STORAGE (MANAJEMEN WORLD STORAGE SEED)
-- ============================================================================
local function renderPlantStorageSub()
    local E = HUB.plant
    if not E then return end

    local availW = safeAvailX()
    local storages = E.getStorageList and E.getStorageList() or {}

    ImGui.Text("Daftar World Storage Seed (" .. tostring(#storages) .. "):")
    if uiNotice ~= "" then
        ImGui.Text("Info: " .. uiNotice)
    end

    if ImGui.BeginTable("BorenStorageTable", 2) then
        ImGui.TableSetupColumn("Storage World")
        ImGui.TableSetupColumn("Door ID")
        ImGui.TableHeadersRow()

        if #storages == 0 then
            ImGui.TableNextRow()
            ImGui.TableSetColumnIndex(0); ImGui.Text("(Belum ada storage)")
            ImGui.TableSetColumnIndex(1); ImGui.Text("-")
        else
            for i, st in ipairs(storages) do
                ImGui.TableNextRow()
                ImGui.TableSetColumnIndex(0)
                local isSel = (selectedStorageIdx == i)
                local prefix = isSel and "> " or ""
                if autoBtn(prefix .. tostring(st.name or "") .. "##st" .. tostring(i)) then
                    selectedStorageIdx = isSel and 0 or i
                end
                ImGui.TableSetColumnIndex(1)
                ImGui.Text(st.door ~= "" and tostring(st.door) or "-")
            end
        end

        ImGui.EndTable()
    end

    ImGui.Separator()

    ImGui.Text("Tambah Storage:")
    if ImGui.BeginTable("BorenPlantAddSt", 2) then
        ImGui.TableSetupColumn("World Storage")
        ImGui.TableSetupColumn("Door ID")
        ImGui.TableHeadersRow()
        ImGui.TableNextRow()
        ImGui.TableSetColumnIndex(0)
        ImGui.PushItemWidth(math.max(110, math.floor(availW * 0.46)))
        local chSt, newSt = safeInputText("##plant_add_st", addStorageBuf, 256)
        ImGui.PopItemWidth()
        if chSt then addStorageBuf = newSt end

        ImGui.TableSetColumnIndex(1)
        ImGui.PushItemWidth(math.max(90, math.floor(availW * 0.44)))
        local chStD, newStD = safeInputText("##plant_add_std", addStorageDoorBuf, 128)
        ImGui.PopItemWidth()
        if chStD then addStorageDoorBuf = newStD end
        ImGui.EndTable()
    end

    if autoBtn(" + Add Storage ") then
        local wStr = tostring(addStorageBuf or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local dStr = tostring(addStorageDoorBuf or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local combined = (wStr:find(":", 1, true) or wStr:find("|", 1, true) or dStr == "") and wStr or (wStr .. ":" .. dStr)
        local parsed = E.parseStorageLine and E.parseStorageLine(combined)
        if parsed then
            table.insert(storages, parsed)
            E.setStorageList(storages)
            addStorageBuf = ""; addStorageDoorBuf = ""
            logUI(E, "[Storage +] " .. parsed.name .. (parsed.door ~= "" and (":" .. parsed.door) or ""))
            setNotice("Storage ditambahkan: " .. parsed.name)
        else
            setNotice("Isi World Storage dulu!")
        end
    end

    ImGui.SameLine()
    if autoBtn(" + World Ini ") then
        local curW = ""
        if getCurrentWorldName then
            local okW, wn = pcall(getCurrentWorldName)
            if okW and type(wn) == "string" then curW = wn:upper() end
        end
        if curW ~= "" and curW ~= "EXIT" then
            addStorageBuf = curW
            setNotice("Terisi " .. curW .. " (isi Door ID di kanan jika ada)")
        else
            setNotice("Masuk ke world terlebih dahulu!")
        end
    end

    ImGui.SameLine()
    if autoBtn(" - Hapus ") then
        local idx = selectedStorageIdx
        if idx < 1 or idx > #storages then idx = #storages end
        if idx >= 1 and idx <= #storages then
            local rem = table.remove(storages, idx)
            selectedStorageIdx = 0
            E.setStorageList(storages)
            logUI(E, "[Storage -] " .. tostring(rem and rem.name or ""))
            setNotice("Storage dihapus: " .. tostring(rem and rem.name or ""))
        end
    end

    if autoBtn(" Import ") then
        local clip = ""
        if ImGui.GetClipboardText then
            local okC, resC = pcall(ImGui.GetClipboardText)
            if okC and type(resC) == "string" then clip = resC end
        end
        if clip ~= "" then
            local added = 0
            for line in clip:gmatch("[^\r\n,]+") do
                local parsed = E.parseStorageLine and E.parseStorageLine(line)
                if parsed then
                    table.insert(storages, parsed)
                    added = added + 1
                end
            end
            if added > 0 then
                E.setStorageList(storages)
                setNotice("Import " .. tostring(added) .. " storage!")
            end
        else
            setNotice("Clipboard kosong!")
        end
    end

    ImGui.SameLine()
    if autoBtn(" Export ") then
        local out = {}
        for _, st in ipairs(storages) do
            table.insert(out, st.door ~= "" and (st.name .. ":" .. st.door) or st.name)
        end
        if ImGui.SetClipboardText then
            pcall(ImGui.SetClipboardText, table.concat(out, "\n"))
            setNotice("Export " .. tostring(#out) .. " storage ke clipboard!")
        end
    end

    ImGui.SameLine()
    if autoBtn(" Save ") then
        E.setStorageList(storages)
        setNotice("Daftar storage tersimpan!")
    end
end

-- ============================================================================
-- PLANT SUB-TAB 3: SETTINGS
-- ============================================================================
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

local function renderPlantSettingsSub()
    local E = HUB.plant
    if not E then return end

    ImGui.Text("Pengaturan Auto Plant")
    ImGui.Separator()

    if ImGui.BeginTable("BorenPlantSetOpts", 2) then
        renderOptRow("Mode Tanam", function()
            local is3z = (E.CFG.plant_mode == "3zigzag")
            if autoBtn(is3z and " 3-Zigzag (Cepat) ##md" or " 1-by-1 (Presisi) ##md") then
                E.CFG.plant_mode = is3z and "1by1" or "3zigzag"
                E.saveData()
            end
        end)
        renderOptRow("ModFly (Terbang)", function()
            if autoBtn(E.CFG.use_modfly and "  ON  ##mf" or "  OFF  ##mf") then
                E.CFG.use_modfly = not E.CFG.use_modfly
                E.saveData()
            end
        end)
        renderOptRow("Abaikan Gems", function()
            if autoBtn(E.CFG.ignore_gems and "  ON  ##ig" or "  OFF  ##ig") then
                E.CFG.ignore_gems = not E.CFG.ignore_gems
                E.saveData()
            end
        end)
        renderOptRow("Plant Delay", function()
            renderNumInput("pl_pd", E.CFG.plant_delay, 60, 500, 20, "ms", function(v)
                E.CFG.plant_delay = v; E.saveData()
            end)
        end)
        renderOptRow("Splice Delay", function()
            renderNumInput("pl_sd", E.CFG.splice_delay, 60, 500, 20, "ms", function(v)
                E.CFG.splice_delay = v; E.saveData()
            end)
        end)
        renderOptRow("Step Delay", function()
            renderNumInput("pl_wd", E.CFG.step_delay, 40, 400, 10, "ms", function(v)
                E.CFG.step_delay = v; E.saveData()
            end)
        end)
        ImGui.EndTable()
    end

    ImGui.Separator()
    ImGui.TextWrapped("Tip: Ketik /hub di chat game untuk sembunyikan / tampilkan jendela ini kapan saja.")
end

-- ============================================================================
-- PLANT SUB-TAB 4: LOGS
-- ============================================================================
local function renderPlantLogsSub()
    local logs = HUB.logs or {}
    if autoBtn(" Clear Logs ") then
        HUB.logs = {}
        if HUB.plant then HUB.plant.STATE.logs = {} end
    end
    ImGui.SameLine()
    if autoBtn(" Copy Logs ") then
        if ImGui.SetClipboardText then
            pcall(ImGui.SetClipboardText, table.concat(logs, "\n"))
            setNotice("Logs disalin ke clipboard!")
        end
    end
    ImGui.Separator()
    if #logs == 0 then
        ImGui.Text("Belum ada log aktivitas.")
    else
        for i = 1, math.min(20, #logs) do
            ImGui.TextWrapped(tostring(logs[i]))
        end
    end
end

-- ============================================================================
-- DASHBOARD UTAMA (INFO MODUL + HOT-RELOAD UPDATE + LINK DISCORD & GITHUB RAW)
-- ============================================================================
local DEFAULT_LINKS = {
    discord       = "https://discord.gg/borenstore",
    github_repo   = "https://github.com/rendhi69/sc_auto_plant_growlauncher",
    raw_loader    = "https://raw.githubusercontent.com/rendhi69/sc_auto_plant_growlauncher/main/loader_hub_imgui.lua",
    raw_debugpack = "https://raw.githubusercontent.com/rendhi69/data-_id_item/main/debugpack.txt",
}

local fallbackReloading = false
local packDbReloading = false

local function getHubLink(key)
    if HUB and HUB.LINKS and HUB.LINKS[key] and HUB.LINKS[key] ~= "" then
        return tostring(HUB.LINKS[key])
    end
    return tostring(DEFAULT_LINKS[key] or "")
end

local function copyLinkToClipboard(label, url)
    if ImGui and ImGui.SetClipboardText then
        pcall(ImGui.SetClipboardText, tostring(url or ""))
        setNotice(label .. " disalin ke clipboard!")
    else
        setNotice("Clipboard tidak tersedia; salin manual dari kotak.")
    end
end

-- Fallback Hot-Reload bila user masih memakai loader lama sebelum loader_hub_imgui.lua di-update
local function triggerHotReloadAll()
    if HUB and type(HUB.reloadAll) == "function" then
        setNotice("Mengambil update terbaru dari GitHub...")
        HUB.reloadAll(function(st)
            setNotice(tostring(st or "Update selesai!"))
        end)
        return
    end
    if fallbackReloading or not HUB then return end
    fallbackReloading = true
    HUB.reload_status = "Mengambil update dari GitHub..."
    setNotice("Mengambil update terbaru dari GitHub...")

    local function runner()
        local ok, err = xpcall(function()
            local base = (HUB.BASE_RAW_URL and HUB.BASE_RAW_URL ~= "")
                and HUB.BASE_RAW_URL
                or "https://raw.githubusercontent.com/rendhi69/sc_auto_plant_growlauncher/main/"
            local freshTag = tostring(math.floor((os and os.time and os.time()) or math.random(100000, 999999))) .. "_" .. tostring(math.random(100, 999))
            for _, k in ipairs({ "plant", "dirt_farm", "build_soil", "buy_pack" }) do
                if HUB[k] and type(HUB[k].stop) == "function" then pcall(HUB[k].stop) end
            end
            local mods = {
                { key = "plant",      path = "imgui_hub/plant_engine.lua" },
                { key = "dirt_farm",  path = "imgui_hub/mod_dirt_farm.lua" },
                { key = "build_soil", path = "imgui_hub/mod_soil_builder.lua" },
                { key = "buy_pack",   path = "imgui_hub/mod_buy_pack.lua" },
                { key = "ui",         path = "imgui_hub/tab_plant.lua" },
            }
            local okCnt = 0
            local loaderFn = loadstring or load
            for _, m in ipairs(mods) do
                if fetch then
                    local okF, code = pcall(fetch, base .. m.path .. "?v=" .. freshTag)
                    if okF and type(code) == "string" and code ~= "" and not code:match("^404") then
                        local chunk = loaderFn(code)
                        if chunk then
                            local okR, modObj = pcall(chunk)
                            if okR and modObj then
                                HUB[m.key] = modObj
                                if type(modObj.init) == "function" then pcall(modObj.init, HUB) end
                                okCnt = okCnt + 1
                            end
                        end
                    end
                end
            end
            HUB.reload_status = string.format("Update OK (%d/5 modul)", okCnt)
            setNotice(HUB.reload_status)
        end, function(e) return tostring(e) end)
        if not ok then
            HUB.reload_status = "Update gagal: " .. tostring(err)
            setNotice(HUB.reload_status)
        end
        fallbackReloading = false
    end

    if runCoroutine then pcall(runCoroutine, runner)
    else coroutine.resume(coroutine.create(runner)) end
end

local function triggerReloadPackDb()
    if packDbReloading or not HUB or not HUB.buy_pack or type(HUB.buy_pack.loadPackDatabase) ~= "function" then
        setNotice("Modul Buy Pack belum aktif.")
        return
    end
    packDbReloading = true
    setNotice("Memuat ulang database DebugPack...")
    local function runner()
        if HUB.refreshCacheTag then pcall(HUB.refreshCacheTag) end
        pcall(HUB.buy_pack.loadPackDatabase)
        local cnt = (HUB.buy_pack.STATE and HUB.buy_pack.STATE.pack_db) and #HUB.buy_pack.STATE.pack_db or 0
        setNotice("Database DebugPack diperbarui (" .. tostring(cnt) .. " pack)!")
        packDbReloading = false
    end
    if runCoroutine then pcall(runCoroutine, runner)
    else coroutine.resume(coroutine.create(runner)) end
end

local animTick = 0
local dcCopiedUntil = 0
local ghCopiedUntil = 0

local SPIN_FRAMES = { "|", "/", "-", "\\" }
local CHEV_L = { "  >", " >>", ">>>", ">> " }
local CHEV_R = { "<  ", "<< ", "<<<", " <<" }
local MARQUEE_TXT = "   BOREN STORE HUB  *  AUTO PLANT  *  DIRT FARM  *  BUILD SOIL  *  BUY PACK  *  /reload UPDATE  *  /hub HIDE   "

local function getMarqueeSlice(step, width)
    local full = MARQUEE_TXT .. MARQUEE_TXT
    local len = #MARQUEE_TXT
    local startIdx = (step % len) + 1
    return full:sub(startIdx, startIdx + width - 1)
end

local function getSlidingBar(step, slots)
    local pos = (step % slots) + 1
    local chars = {}
    for i = 1, slots do
        if i == pos or i == ((pos % slots) + 1) then
            chars[i] = "="
        elseif i == (((pos + 1) % slots) + 1) then
            chars[i] = ">"
        else
            chars[i] = "."
        end
    end
    return "[" .. table.concat(chars) .. "]"
end

local function isAnyBotActive()
    if not HUB then return false end
    for _, k in ipairs({ "plant", "dirt_farm", "build_soil", "buy_pack" }) do
        local m = HUB[k]
        if m and m.STATE and (m.STATE.enabled or m.STATE.running) then return true end
    end
    return false
end

local function renderDashboardPanel()
    animTick = animTick + 1
    local slowStep = math.floor(animTick / 12)
    local medStep  = math.floor(animTick / 6)
    local availW   = safeAvailX()

    local curWorld = "-"
    if getCurrentWorldName then
        local okW, wn = pcall(getCurrentWorldName)
        if okW and type(wn) == "string" and wn ~= "" then curWorld = wn:upper() end
    end
    local curGems = 0
    if getGems then
        local okG, g = pcall(getGems)
        if okG and tonumber(g) then curGems = math.floor(tonumber(g)) end
    end

    local isReloading = (HUB and HUB.reloading == true) or fallbackReloading
    local updStatus   = tostring((HUB and HUB.reload_status) or "Siap")
    local anyRun      = isAnyBotActive()

    -- 1. HEADER & LIVE ANIMATED BANNER
    local chevIdx = (slowStep % #CHEV_L) + 1
    local pulseDot = ((slowStep % 2) == 0) and "[*]" or "[o]"
    local runBadge = anyRun and (pulseDot .. " BOT AKTIF") or (pulseDot .. " STANDBY")
    ImGui.Text(string.format("%s  BOREN HUB  %s   |   %s", CHEV_L[chevIdx], CHEV_R[chevIdx], runBadge))
    ImGui.Text(getMarqueeSlice(medStep, 46))
    ImGui.Text(string.format("World: %s  |  Gems: %d  |  %s", curWorld, curGems, updStatus))
    if uiNotice ~= "" then
        ImGui.Text("Info: " .. uiNotice)
    end
    ImGui.Separator()

    -- 2. KARTU LOGO ANIMASI KLIK-UNTUK-COPY (Tanpa menampilkan link raw)
    local cardW = math.max(150, math.floor(availW * 0.47))

    -- Animasi mata berkedip Discord Clyde & efek senang saat baru diklik
    local dcCopied = (animTick < dcCopiedUntil)
    local dcBlink  = ((slowStep % 14) == 13)
    local dcFace   = dcCopied and "  ( ^ _ ^ )  " or (dcBlink and "  ( - _ - )  " or "  ( o _ o )  ")
    local dcTop    = dcCopied and "  * COPIED * " or "   .-----.   "
    local dcLabel  = dcCopied and " Link Tersalin! " or " Discord Boren "

    -- Animasi Octocat / Code GitHub berkedip & efek senang saat baru diklik
    local ghCopied = (animTick < ghCopiedUntil)
    local ghBlink  = ((slowStep % 16) == 7)
    local ghTop    = ghCopied and "  * COPIED * " or "   /\\___/\\   "
    local ghFace   = ghCopied and "  ( ^ . ^ )  " or (ghBlink and "  ( - . - )  " or "  ( o . o )  ")
    local ghLabel  = ghCopied and " Link Tersalin! " or "  GitHub Boren  "

    if ImGui.BeginTable("BorenDashCards", 2) then
        ImGui.TableNextRow()
        ImGui.TableSetColumnIndex(0)
        if fullBtn("\n" .. dcTop .. "\n" .. dcFace .. "\n\n" .. dcLabel .. "\n##card_dc", cardW) then
            copyLinkToClipboard("Link Discord Boren", getHubLink("discord"))
            dcCopiedUntil = animTick + 90
        end

        ImGui.TableSetColumnIndex(1)
        if fullBtn("\n" .. ghTop .. "\n" .. ghFace .. "\n\n" .. ghLabel .. "\n##card_gh", cardW) then
            copyLinkToClipboard("Link GitHub Boren", getHubLink("github_repo"))
            ghCopiedUntil = animTick + 90
        end
        ImGui.EndTable()
    end

    ImGui.Text("Klik kartu logo di atas untuk salin link ke clipboard.")
    ImGui.Separator()

    -- 3. TOMBOL REFRESH / HOT-RELOAD + ANIMASI LOADING SPINNER & PROGRESS BAR
    local spinChar = SPIN_FRAMES[(medStep % #SPIN_FRAMES) + 1]
    if isReloading or packDbReloading then
        ImGui.Text(string.format("[%s] Memuat update %s", spinChar, getSlidingBar(medStep, 14)))
    end

    if autoBtn(isReloading and ("  [" .. spinChar .. "] Updating...  ##dash_rl") or "  Refresh / Update Script  ##dash_rl") then
        if not isReloading then
            triggerHotReloadAll()
        end
    end
    ImGui.SameLine()
    if autoBtn(packDbReloading and (" [" .. spinChar .. "] Loading DB... ##dash_db") or " Reload DB Pack ##dash_db") then
        if not packDbReloading then
            triggerReloadPackDb()
        end
    end
end

-- ============================================================================
-- SIDEBAR KIRI: KHUSUS NAMA KATEGORI FITUR SAJA (TANPA SEPARATOR!)
-- ============================================================================
local loadingModFlag = {}

local function triggerLazyLoad(modKey, relPath)
    if loadingModFlag[modKey] or not HUB or not HUB.loadModule then return end
    loadingModFlag[modKey] = true
    local function doLoad()
        local mod = HUB.loadModule(relPath)
        if mod then
            if type(mod.init) == "function" then pcall(mod.init, HUB) end
            HUB[modKey] = mod
        end
        loadingModFlag[modKey] = false
    end
    if runCoroutine then pcall(runCoroutine, doLoad)
    else doLoad() end
end

local function renderLeftFeatureSidebar(colW)
    local btnW = math.max(90, colW - 18)
    ImGui.Text("MENU")
    if fullBtn(activeFeature == "dashboard" and "[ Dashboard ]" or "Dashboard", btnW) then
        activeFeature = "dashboard"
    end
    if fullBtn(activeFeature == "plant" and "[ Plant ]" or "Plant", btnW) then
        activeFeature = "plant"
    end
    if fullBtn(activeFeature == "dirt_farm" and "[ Dirt Farm ]" or "Dirt Farm", btnW) then
        activeFeature = "dirt_farm"
    end
    if fullBtn(activeFeature == "build_soil" and "[ Build Soil ]" or "Build Soil", btnW) then
        activeFeature = "build_soil"
    end
    if fullBtn(activeFeature == "buy_pack" and "[ Buy Pack ]" or "Buy Pack", btnW) then
        activeFeature = "buy_pack"
    end

    ImGui.Text("")
    if fullBtn("Hide UI", btnW) then
        windowOpen = false
    end
end

-- ============================================================================
-- PANEL KANAN: SUB-MENU ATAS + KONTEN KATEGORI AKTIF
-- ============================================================================
local function renderRightPanel()
    if activeFeature == "dashboard" then
        renderDashboardPanel()

    elseif activeFeature == "plant" then
        -- BARIS ATAS (mengisi bagian atas kanan): sub-menu khusus kategori Plant
        if autoBtn(activePlantSub == "worlds" and "[ List World ]" or "List World") then
            activePlantSub = "worlds"
        end
        ImGui.SameLine()
        if autoBtn(activePlantSub == "storage" and "[ List Storage ]" or "List Storage") then
            activePlantSub = "storage"
        end
        ImGui.SameLine()
        if autoBtn(activePlantSub == "settings" and "[ Settings ]" or "Settings") then
            activePlantSub = "settings"
        end
        ImGui.SameLine()
        if autoBtn(activePlantSub == "logs" and "[ Logs ]" or "Logs") then
            activePlantSub = "logs"
        end

        ImGui.Separator()

        if activePlantSub == "worlds" then
            renderPlantWorldsSub()
        elseif activePlantSub == "storage" then
            renderPlantStorageSub()
        elseif activePlantSub == "settings" then
            renderPlantSettingsSub()
        else
            renderPlantLogsSub()
        end

    elseif activeFeature == "dirt_farm" then
        if HUB.dirt_farm and type(HUB.dirt_farm.render) == "function" then
            HUB.dirt_farm.render(HUB)
        else
            ImGui.Text("Modul Dirt Farm belum dimuat.")
            if autoBtn(loadingModFlag.dirt_farm and "Memuat..." or " Muat Modul Dirt Farm ") then
                triggerLazyLoad("dirt_farm", "imgui_hub/mod_dirt_farm.lua")
            end
        end

    elseif activeFeature == "build_soil" then
        if HUB.build_soil and type(HUB.build_soil.render) == "function" then
            HUB.build_soil.render(HUB)
        else
            ImGui.Text("Modul Build Soil belum dimuat.")
            if autoBtn(loadingModFlag.build_soil and "Memuat..." or " Muat Modul Build Soil ") then
                triggerLazyLoad("build_soil", "imgui_hub/mod_soil_builder.lua")
            end
        end

    elseif activeFeature == "buy_pack" then
        if HUB.buy_pack and type(HUB.buy_pack.render) == "function" then
            HUB.buy_pack.render(HUB)
        else
            ImGui.Text("Modul Buy Pack belum dimuat.")
            if autoBtn(loadingModFlag.buy_pack and "Memuat..." or " Muat Modul Buy Pack ") then
                triggerLazyLoad("buy_pack", "imgui_hub/mod_buy_pack.lua")
            end
        end
    end
end

-- ============================================================================
-- MAIN IMGUI RENDER LOOP
-- ============================================================================
local function renderFrame()
    if not ImGui or not HUB then return end

    if ImGui.GetFrameCount then
        local okFc, fc = pcall(ImGui.GetFrameCount)
        if okFc and type(fc) == "number" then
            if fc == lastFrameCount then return end
            lastFrameCount = fc
        end
    end

    if not windowOpen then
        if ImGui.SetNextWindowPos and ImVec2 then
            pcall(ImGui.SetNextWindowPos, ImVec2(24, 150), (ImGui.Cond and ImGui.Cond.Once) or 2)
        end
        if ImGui.SetNextWindowSize and ImVec2 then
            pcall(ImGui.SetNextWindowSize, ImVec2(300, 155), (ImGui.Cond and ImGui.Cond.Always) or 1)
        end
        if ImGui.Begin("Boren Hub##boren_mini") then
            if autoBtn("  Buka Boren Hub  ") then
                windowOpen = true
            end
        end
        ImGui.End()
        return
    end

    if ImGui.SetNextWindowSize and ImVec2 then
        pcall(ImGui.SetNextWindowSize, ImVec2(780, 470), (ImGui.Cond and ImGui.Cond.Once) or 2)
    end

    if ImGui.Begin("Boren Hub##boren_main") then
        local winW = safeWinW()
        local sideW = math.max(130, math.floor(winW * 0.20))

        local usedCols = false
        if ImGui.Columns and ImGui.NextColumn then
            local okCol = pcall(ImGui.Columns, 2)
            if okCol then
                usedCols = true
                if ImGui.SetColumnWidth then
                    pcall(ImGui.SetColumnWidth, 0, sideW)
                end

                -- KOLOM KIRI: Kategori Fitur SAJA (tanpa Separator agar kanan rata atas!)
                renderLeftFeatureSidebar(sideW)

                -- KOLOM KANAN: Sub-menu atas (List World, List Storage, Settings, Logs) + Konten
                ImGui.NextColumn()
            end
        end

        local okRight, errRight = pcall(renderRightPanel)
        if not okRight then
            setNotice("UI Err: " .. tostring(errRight))
        end

        if usedCols then
            pcall(ImGui.Columns, 1)
        end
    end
    ImGui.End()
end

-- ============================================================================
-- HOOKS (/hub COMMAND + ANTI GEMS + ONDRAWIMGUI)
-- ============================================================================
local function handleSendPacket(pktType, pktStr)
    if type(pktStr) == "string" then
        local txt = pktStr:match("text|([^\n\r]+)")
        if txt then
            local cmd = txt:lower():gsub("^%s+", ""):gsub("%s+$", "")
            if cmd == "/hub" then
                windowOpen = not windowOpen
                if LogToConsole then
                    pcall(LogToConsole, "`e[Boren Hub] `wUI " .. (windowOpen and "`2DITAMPILKAN" or "`4DISEMBUNYIKAN"))
                end
                return true
            elseif cmd == "/reload" then
                triggerHotReloadAll()
                return true
            end
        end
    end
    return false
end

local function handleSendPacketRaw(pkt)
    if type(pkt) ~= "table" or not HUB then return false end
    if tonumber(pkt.type) == 11 then
        -- Anti-Take untuk Auto Buy Pack saat sedang drop item
        if HUB.buy_pack and HUB.buy_pack.STATE and HUB.buy_pack.STATE.anti_take_active then
            return true
        end
        -- Ignore Gems untuk Auto Plant
        if HUB.plant and HUB.plant.CFG and HUB.plant.CFG.ignore_gems then
            local objUID = tonumber(pkt.value) or 0
            local getObjsFn = getObjects or getObjectList
            if getObjsFn then
                local ok, objs = pcall(getObjsFn)
                if ok and type(objs) == "table" then
                    for _, o in pairs(objs) do
                        if o and tonumber(o.id) == objUID then
                            local oid = tonumber(o.itemid or o.itemId or o.item_id or 0) or 0
                            if oid == 112 then return true end
                            break
                        end
                    end
                end
            end
        end
    end
    return false
end

local function handleVariant(var)
    if HUB and HUB.buy_pack and type(HUB.buy_pack.handleVariant) == "function" then
        local ok, blocked = pcall(HUB.buy_pack.handleVariant, var)
        if ok and blocked == true then return true end
    end
    return false
end

UI.onSendPacket    = handleSendPacket
UI.onSendPacketRaw = handleSendPacketRaw
UI.onVariant       = handleVariant

function UI.init(hubCtx)
    HUB = hubCtx
    _G.__BOREN_HUB_UI = UI
    OnDrawImGui = renderFrame
    onDrawImGui = renderFrame

    -- Pasang proxy hook 1x saja agar Hot-Reload tidak pernah menduplikasi hook!
    if not _G.__BOREN_HUB_HOOKS_INSTALLED then
        _G.__BOREN_HUB_HOOKS_INSTALLED = true
        if addHook then
            pcall(addHook, function(t, s)
                local u = _G.__BOREN_HUB_UI
                return (u and u.onSendPacket) and u.onSendPacket(t, s) or false
            end, "onsendpacket")
            pcall(addHook, function(pkt)
                local u = _G.__BOREN_HUB_UI
                return (u and u.onSendPacketRaw) and u.onSendPacketRaw(pkt) or false
            end, "onsendpacketraw")
            pcall(addHook, function(var)
                local u = _G.__BOREN_HUB_UI
                return (u and u.onVariant) and u.onVariant(var) or false
            end, "onvariant")
        end
        if applyHook then
            pcall(applyHook)
        end
    end
end

return UI
