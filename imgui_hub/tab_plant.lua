-- ============================================================================
-- BOREN HUB IMGUI - MODULAR UI (SIDEBAR KIRI + PANEL AUTOMATION KANAN)
-- File: imgui_hub/tab_plant.lua
-- Layout:
--   - KIRI  : Kotak Sidebar dengan daftar kotak nama fitur (Plant, Settings, Logs, Hide)
--   - KANAN : Automation (Enable, Loop, Seed Storage), List World (Tabel 5 kolom),
--             dan Save World (Input, + Add, + World Ini, - Hapus, Import, Export, Reset, Save)
-- Semua tombol memakai ukuran auto-fit (h = 0 / 1-arg Button) agar 100% terbaca
-- tajam di layar HP Android DPI tinggi maupun PC!
-- ============================================================================

local UI = {}

local HUB = nil
local activeTab = "plant"
local windowOpen = true
local addInputBuf = ""
local lastFrameCount = -1

local function notify(msg)
    if sendNotification then pcall(sendNotification, tostring(msg)) end
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
    return 720
end

-- Button lebar kustom namun tinggi AUTO-FIT (y = 0) agar teks tidak pernah terpotong di Android!
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
-- PANEL KANAN - TAB 1: PLANT (AUTOMATION, LIST WORLD & SAVE WORLD)
-- ============================================================================
local function renderPlantTab()
    local E = HUB.plant
    if not E then
        ImGui.Text("Engine Plant belum termuat.")
        return
    end

    local availW = safeAvailX()

    -- ------------------------------------------------------------------------
    -- 1. AUTOMATION BAR: Enable [ON/OFF] | Loop [ON/OFF] | Status
    -- ------------------------------------------------------------------------
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
    ImGui.Text(" | " .. tostring(E.STATE.status_text or "Idle"))

    -- ------------------------------------------------------------------------
    -- 2. SEED STORAGE & REMOVE INACCESSIBLE
    -- ------------------------------------------------------------------------
    ImGui.Text("Seed Storage (WORLD:DOOR):")
    local storW = math.max(150, math.floor(availW * 0.62))
    ImGui.PushItemWidth(storW)
    local chS, newS = ImGui.InputText("##plant_storage", tostring(E.CFG.storage_raw or ""), 256)
    ImGui.PopItemWidth()
    if chS and type(newS) == "string" then
        E.CFG.storage_raw = newS
        E.saveData()
    end

    ImGui.SameLine()
    if autoBtn("Remove Inaccessible") then
        local removed = E.removeInaccessible()
        notify("Dihapus " .. tostring(removed) .. " world inaccessible.")
    end

    ImGui.Separator()

    -- ------------------------------------------------------------------------
    -- 3. LIST WORLD (TABEL 5 KOLOM: Name | Door ID | Seed ID | Splice ID | Status)
    -- ------------------------------------------------------------------------
    ImGui.Text("List World (" .. tostring(#E.STATE.rows) .. "):")
    if ImGui.BeginTable("BorenPlantTable", 5) then
        ImGui.TableSetupColumn("Name")
        ImGui.TableSetupColumn("Door ID")
        ImGui.TableSetupColumn("Seed ID")
        ImGui.TableSetupColumn("Splice ID")
        ImGui.TableSetupColumn("Status")
        ImGui.TableHeadersRow()

        if #E.STATE.rows == 0 then
            ImGui.TableNextRow()
            ImGui.TableSetColumnIndex(0)
            ImGui.Text("(Kosong)")
            ImGui.TableSetColumnIndex(1)
            ImGui.Text("-")
            ImGui.TableSetColumnIndex(2)
            ImGui.Text("-")
            ImGui.TableSetColumnIndex(3)
            ImGui.Text("-")
            ImGui.TableSetColumnIndex(4)
            ImGui.Text("Tambah di bawah")
        else
            for i, row in ipairs(E.STATE.rows) do
                ImGui.TableNextRow()

                ImGui.TableSetColumnIndex(0)
                local isSel = (E.STATE.selected_idx == i)
                local prefix = isSel and "> " or ""
                if autoBtn(prefix .. tostring(row.name or "") .. "##r" .. tostring(i)) then
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

    -- ------------------------------------------------------------------------
    -- 4. TAMBAH & SAVE WORLD (Name:DoorID:SeedID:SpliceID)
    -- ------------------------------------------------------------------------
    ImGui.Text("Tambah / Save World (Name:DoorID:SeedID:SpliceID):")
    ImGui.PushItemWidth(math.max(160, availW - 12))
    local chA, newA = ImGui.InputText("##plant_add", tostring(addInputBuf or ""), 256)
    ImGui.PopItemWidth()
    if chA and type(newA) == "string" then
        addInputBuf = newA
    end

    -- Baris tombol aksi 1: + Add | + World Ini | - Hapus | Save World
    if autoBtn(" + Add ") then
        local parsed = E.parseRowLine(addInputBuf)
        if parsed then
            table.insert(E.STATE.rows, parsed)
            addInputBuf = ""
            E.saveData()
            E.addLog("[+] Ditambahkan & tersimpan: " .. E.formatRowLine(parsed))
            notify("World ditambahkan & tersimpan!")
        else
            notify("Format: Name:DoorID:SeedID:SpliceID")
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
            addInputBuf = curW .. "::4585:0"
            notify("Terisi " .. curW .. " (sesuaikan Door & Seed ID lalu klik + Add)")
        else
            notify("Masuk ke world terlebih dahulu!")
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
            E.addLog("[-] Dihapus: " .. tostring(rem and rem.name or ""))
        end
    end

    ImGui.SameLine()
    if autoBtn(" Save World ") then
        E.saveData()
        E.addLog("[Save] " .. tostring(#E.STATE.rows) .. " world berhasil disimpan.")
        notify("Tersimpan " .. tostring(#E.STATE.rows) .. " world!")
    end

    -- Baris tombol aksi 2: Import | Export | Reset Status
    if autoBtn(" Import ") then
        local clip = ""
        if ImGui.GetClipboardText then
            local okC, resC = pcall(ImGui.GetClipboardText)
            if okC and type(resC) == "string" then clip = resC end
        end
        if clip == "" then
            notify("Clipboard kosong!")
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
                E.addLog("[Import] " .. tostring(added) .. " world diimpor & tersimpan.")
                notify("Import " .. tostring(added) .. " world!")
            else
                notify("Tidak ada baris valid di clipboard.")
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
            notify("Export " .. tostring(#out) .. " world ke clipboard!")
        end
    end

    ImGui.SameLine()
    if autoBtn(" Reset Status ") then
        E.resetAllStatus()
        notify("Semua status di-reset ke Ready.")
    end
end

-- ============================================================================
-- PANEL KANAN - TAB 2: SETTINGS
-- ============================================================================
local function renderSettingsTab()
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
-- PANEL KANAN - TAB 3: LOGS
-- ============================================================================
local function renderLogsTab()
    local logs = HUB.logs or {}
    if autoBtn(" Clear Logs ") then
        HUB.logs = {}
        if HUB.plant then HUB.plant.STATE.logs = {} end
    end
    ImGui.SameLine()
    if autoBtn(" Copy Logs ") then
        if ImGui.SetClipboardText then
            pcall(ImGui.SetClipboardText, table.concat(logs, "\n"))
            notify("Logs disalin ke clipboard!")
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
-- SIDEBAR KIRI: KOTAK-KOTAK NAMA FITUR
-- ============================================================================
local function renderLeftSidebar(colW)
    local btnW = math.max(80, colW - 18)
    ImGui.Text("FITUR")
    ImGui.Separator()

    if fullBtn(activeTab == "plant" and "[ Plant ]" or "Plant", btnW) then
        activeTab = "plant"
    end
    if fullBtn(activeTab == "settings" and "[ Settings ]" or "Settings", btnW) then
        activeTab = "settings"
    end
    if fullBtn(activeTab == "logs" and "[ Logs ]" or "Logs", btnW) then
        activeTab = "logs"
    end

    ImGui.Separator()
    if fullBtn("Hide UI", btnW) then
        windowOpen = false
    end
end

-- ============================================================================
-- MAIN IMGUI RENDER LOOP (2-KOLOM: SIDEBAR KIRI | PANEL AUTOMATION KANAN)
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
        if ImGui.Begin("Boren Hub") then
            if autoBtn(" Buka Boren Hub ") then
                windowOpen = true
            end
        end
        ImGui.End()
        return
    end

    if ImGui.SetNextWindowSize and ImVec2 then
        pcall(ImGui.SetNextWindowSize, ImVec2(760, 460), (ImGui.Cond and ImGui.Cond.Once) or 2)
    end

    if ImGui.Begin("Boren Hub - Auto Plant") then
        local winW = safeWinW()
        local sideW = math.max(120, math.floor(winW * 0.22))

        -- Pisahkan Kiri (Sidebar Fitur) dan Kanan (Automation + List & Save World)
        local usedCols = false
        if ImGui.Columns and ImGui.NextColumn then
            local okCol = pcall(ImGui.Columns, 2)
            if okCol then
                usedCols = true
                if ImGui.SetColumnWidth then
                    pcall(ImGui.SetColumnWidth, 0, sideW)
                end

                -- KOLOM KIRI: Kotak Fitur
                renderLeftSidebar(sideW)

                -- PINDAH KE KOLOM KANAN: Automation, List World & Save World
                ImGui.NextColumn()
            end
        end

        if not usedCols then
            -- Fallback horizontal jika Columns tidak tersedia
            if autoBtn(activeTab == "plant" and "[ Plant ]" or "Plant") then activeTab = "plant" end
            ImGui.SameLine()
            if autoBtn(activeTab == "settings" and "[ Settings ]" or "Settings") then activeTab = "settings" end
            ImGui.SameLine()
            if autoBtn(activeTab == "logs" and "[ Logs ]" or "Logs") then activeTab = "logs" end
            ImGui.SameLine()
            if autoBtn("Hide UI") then windowOpen = false end
            ImGui.Separator()
        end

        if activeTab == "plant" then
            renderPlantTab()
        elseif activeTab == "settings" then
            renderSettingsTab()
        else
            renderLogsTab()
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
