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
local activeFeature = "plant"      -- "plant" | "dirt_farm" | "build_soil"
local activePlantSub = "worlds"    -- "worlds" | "storage" | "settings" | "logs"
local windowOpen = true

local addWorldBuf = ""
local addStorageBuf = ""
local selectedStorageIdx = 0
local lastFrameCount = -1
local uiNotice = ""

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

    -- Form Penambahan & Save World langsung masuk ke List World
    ImGui.Text("Tambah World (Name:DoorID:SeedID:SpliceID):")
    ImGui.PushItemWidth(math.max(160, availW - 12))
    local chA, newA = ImGui.InputText("##plant_add_w", tostring(addWorldBuf or ""), 256)
    ImGui.PopItemWidth()
    if chA and type(newA) == "string" then
        addWorldBuf = newA
    end

    if autoBtn(" + Add World ") then
        local parsed = E.parseRowLine(addWorldBuf)
        if parsed then
            table.insert(E.STATE.rows, parsed)
            addWorldBuf = ""
            E.saveData()
            logUI(E, "[+] World ditambah: " .. E.formatRowLine(parsed))
            setNotice("Ditambahkan: " .. parsed.name .. " (Seed " .. tostring(parsed.seed_id) .. ")")
        else
            setNotice("Format: Name:DoorID:SeedID:SpliceID")
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
            addWorldBuf = curW .. "::4585:0"
            setNotice("Terisi " .. curW .. " (isi Door & Seed ID lalu klik + Add World)")
        else
            setNotice("Masuk ke world terlebih dahulu!")
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

    ImGui.Text("Tambah Storage (Format WORLD:DOORID):")
    ImGui.PushItemWidth(math.max(160, availW - 12))
    local chSt, newSt = ImGui.InputText("##plant_add_st", tostring(addStorageBuf or ""), 256)
    ImGui.PopItemWidth()
    if chSt and type(newSt) == "string" then
        addStorageBuf = newSt
    end

    if autoBtn(" + Add Storage ") then
        local parsed = E.parseStorageLine and E.parseStorageLine(addStorageBuf)
        if parsed then
            table.insert(storages, parsed)
            E.setStorageList(storages)
            addStorageBuf = ""
            logUI(E, "[Storage +] " .. parsed.name .. (parsed.door ~= "" and (":" .. parsed.door) or ""))
            setNotice("Storage ditambahkan: " .. parsed.name)
        else
            setNotice("Format: WORLD:DOORID")
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
            addStorageBuf = curW .. ":"
            setNotice("Terisi " .. curW .. ": (tambahkan Door ID lalu klik + Add Storage)")
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
local function renderPlantSettingsSub()
    local E = HUB.plant
    if not E then return end

    ImGui.Text("Pengaturan Auto Plant")
    ImGui.Separator()

    ImGui.Text("Mode Tanam:")
    ImGui.SameLine()
    local is3z = (E.CFG.plant_mode == "3zigzag")
    if autoBtn(is3z and " 3-Zigzag (Cepat) ##md" or " 1-by-1 (Presisi) ##md") then
        E.CFG.plant_mode = is3z and "1by1" or "3zigzag"
        E.saveData()
    end

    ImGui.Text("ModFly (Terbang):")
    ImGui.SameLine()
    if autoBtn(E.CFG.use_modfly and "  ON  ##mf" or "  OFF  ##mf") then
        E.CFG.use_modfly = not E.CFG.use_modfly
        E.saveData()
    end

    ImGui.Text("Abaikan Gems:")
    ImGui.SameLine()
    if autoBtn(E.CFG.ignore_gems and "  ON  ##ig" or "  OFF  ##ig") then
        E.CFG.ignore_gems = not E.CFG.ignore_gems
        E.saveData()
    end

    ImGui.Separator()

    ImGui.Text("Plant Delay: " .. tostring(E.CFG.plant_delay) .. " ms")
    ImGui.SameLine()
    if autoBtn(" -20 ##pd1") then
        E.CFG.plant_delay = math.max(80, (tonumber(E.CFG.plant_delay) or 180) - 20)
        E.saveData()
    end
    ImGui.SameLine()
    if autoBtn(" +20 ##pd2") then
        E.CFG.plant_delay = math.min(500, (tonumber(E.CFG.plant_delay) or 180) + 20)
        E.saveData()
    end

    ImGui.Text("Splice Delay: " .. tostring(E.CFG.splice_delay) .. " ms")
    ImGui.SameLine()
    if autoBtn(" -20 ##sd1") then
        E.CFG.splice_delay = math.max(80, (tonumber(E.CFG.splice_delay) or 180) - 20)
        E.saveData()
    end
    ImGui.SameLine()
    if autoBtn(" +20 ##sd2") then
        E.CFG.splice_delay = math.min(500, (tonumber(E.CFG.splice_delay) or 180) + 20)
        E.saveData()
    end

    ImGui.Text("Step Delay: " .. tostring(E.CFG.step_delay) .. " ms")
    ImGui.SameLine()
    if autoBtn(" -10 ##wd1") then
        E.CFG.step_delay = math.max(40, (tonumber(E.CFG.step_delay) or 110) - 10)
        E.saveData()
    end
    ImGui.SameLine()
    if autoBtn(" +10 ##wd2") then
        E.CFG.step_delay = math.min(350, (tonumber(E.CFG.step_delay) or 110) + 10)
        E.saveData()
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
-- SIDEBAR KIRI: KHUSUS NAMA KATEGORI FITUR SAJA (TANPA SEPARATOR!)
-- ============================================================================
local function renderLeftFeatureSidebar(colW)
    local btnW = math.max(90, colW - 18)
    ImGui.Text("FITUR")
    if fullBtn(activeFeature == "plant" and "[ Plant ]" or "Plant", btnW) then
        activeFeature = "plant"
    end
    if fullBtn(activeFeature == "dirt_farm" and "[ Dirt Farm ]" or "Dirt Farm", btnW) then
        activeFeature = "dirt_farm"
    end
    if fullBtn(activeFeature == "build_soil" and "[ Build Soil ]" or "Build Soil", btnW) then
        activeFeature = "build_soil"
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
    if activeFeature == "plant" then
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
        ImGui.Text("Kategori: Dirt Farm")
        ImGui.Separator()
        ImGui.TextWrapped("Slot kategori Dirt Farm sudah siap dihubungkan ke modul Dirt Farm via load (terpisah).")

    elseif activeFeature == "build_soil" then
        ImGui.Text("Kategori: Build Soil")
        ImGui.Separator()
        ImGui.TextWrapped("Slot kategori Build Soil sudah siap dihubungkan ke modul Build Soil via load (terpisah).")
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
            pcall(ImGui.SetNextWindowSize, ImVec2(195, 110), (ImGui.Cond and ImGui.Cond.Always) or 1)
        end
        if ImGui.Begin("Hub##boren_mini") then
            if fullBtn("Buka Hub", 175) then
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
            end
        end
    end
    return false
end

local function handleSendPacketRaw(pkt)
    if type(pkt) ~= "table" or not HUB or not HUB.plant then return false end
    if tonumber(pkt.type) == 11 and HUB.plant.CFG.ignore_gems then
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
    return false
end

function UI.init(hubCtx)
    HUB = hubCtx
    OnDrawImGui = renderFrame
    onDrawImGui = renderFrame

    if addHook then
        pcall(addHook, handleSendPacket, "onsendpacket")
        pcall(addHook, handleSendPacketRaw, "onsendpacketraw")
    end
    if applyHook then
        pcall(applyHook)
    end
end

return UI
