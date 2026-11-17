-- ============================================================================
-- BOREN HUB IMGUI - MODULAR UI (PLANT / SETTINGS / LOGS)
-- File: imgui_hub/tab_plant.lua
-- Menggunakan HANYA fungsi ImGui yang 100% terverifikasi aman di Growlauncher
-- Android & PC (mengikuti pola resmi world_saver.lua & calculator.lua):
--   Begin(1 arg), End, SetNextWindowSize, Text, TextWrapped, Button, SameLine,
--   Separator, PushItemWidth, PopItemWidth, InputText, BeginTable(2 arg),
--   TableSetupColumn, TableHeadersRow, TableNextRow, TableSetColumnIndex, EndTable.
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
            if type(av) == "number" then return av end
            local okX, x = pcall(function() return av.x end)
            if okX and type(x) == "number" and x > 50 then return x end
        end
    end
    return 520
end

local function safeButton(label, w, h)
    if w and h and ImVec2 then
        local ok, res = pcall(ImGui.Button, label, ImVec2(w, h))
        if ok then return res == true end
    end
    local ok, res = pcall(ImGui.Button, label)
    return ok and (res == true)
end

-- ============================================================================
-- TAB 1: PLANT (Enable | Loop, Seed Storage, Tabel 5 Kolom, Add/Import/Export)
-- ============================================================================
local function renderPlantTab()
    local E = HUB.plant
    if not E then
        ImGui.Text("Engine Plant belum termuat.")
        return
    end

    local availW = safeAvailX()

    -- BARIS 1: Enable [ON/OFF]  |  Loop [ON/OFF]  |  Status
    ImGui.Text("Enable:")
    ImGui.SameLine()
    if safeButton((E.STATE.enabled and "[ ON ]##en" or "[ OFF ]##en"), 68, 24) then
        if E.STATE.enabled then E.stop() else E.start() end
    end

    ImGui.SameLine()
    ImGui.Text("  |  Loop:")
    ImGui.SameLine()
    if safeButton((E.CFG.loop_enabled and "[ ON ]##lp" or "[ OFF ]##lp"), 68, 24) then
        E.CFG.loop_enabled = not E.CFG.loop_enabled
        E.saveData()
    end

    ImGui.SameLine()
    ImGui.Text("  |  " .. tostring(E.STATE.status_text or "Idle"))

    -- BARIS 2: Seed Storage [Required] + Remove Inaccessible
    ImGui.Text("Seed Storage:")
    ImGui.SameLine()
    local storW = math.max(120, availW - 260)
    ImGui.PushItemWidth(storW)
    local chS, newS = ImGui.InputText("##plant_storage", tostring(E.CFG.storage_raw or ""), 256)
    ImGui.PopItemWidth()
    if chS and type(newS) == "string" then
        E.CFG.storage_raw = newS
        E.saveData()
    end

    ImGui.SameLine()
    if safeButton("Remove Inaccessible", 150, 24) then
        local removed = E.removeInaccessible()
        notify("Dihapus " .. tostring(removed) .. " world inaccessible.")
    end

    ImGui.Separator()

    -- BAGIAN TENGAH: TABEL 5 KOLOM (2-arg BeginTable seperti world_saver.lua)
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
                if ImGui.Button(prefix .. tostring(row.name or "") .. "##r" .. tostring(i)) then
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

    -- BARIS BAWAH: Format Name:ID:SeedID:SpliceID + [+] [-] [Import] [Export] [Reset Status]
    ImGui.Text("Format: Name:DoorID:SeedID:SpliceID")
    local inputW = math.max(120, availW - 310)
    ImGui.PushItemWidth(inputW)
    local chA, newA = ImGui.InputText("##plant_add", tostring(addInputBuf or ""), 256)
    ImGui.PopItemWidth()
    if chA and type(newA) == "string" then
        addInputBuf = newA
    end

    ImGui.SameLine()
    if safeButton("+##add", 28, 24) then
        local parsed = E.parseRowLine(addInputBuf)
        if parsed then
            table.insert(E.STATE.rows, parsed)
            addInputBuf = ""
            E.saveData()
            E.addLog("[+] Ditambahkan: " .. E.formatRowLine(parsed))
        else
            notify("Format: Name:DoorID:SeedID:SpliceID")
        end
    end

    ImGui.SameLine()
    if safeButton("-##del", 28, 24) then
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
    if safeButton("Import", 58, 24) then
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
                E.addLog("[Import] " .. tostring(added) .. " world ditambahkan.")
                notify("Import " .. tostring(added) .. " world!")
            else
                notify("Tidak ada baris valid di clipboard.")
            end
        end
    end

    ImGui.SameLine()
    if safeButton("Export", 58, 24) then
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
    if safeButton("Reset Status", 96, 24) then
        E.resetAllStatus()
        notify("Status di-reset ke Ready.")
    end
end

-- ============================================================================
-- TAB 2: SETTINGS
-- ============================================================================
local function renderSettingsTab()
    local E = HUB.plant
    if not E then return end

    ImGui.Text("Mode Tanam:")
    ImGui.SameLine()
    local is3z = (E.CFG.plant_mode == "3zigzag")
    if safeButton(is3z and "3-Zigzag (Cepat)##md" or "1-by-1 (Presisi)##md", 150, 24) then
        E.CFG.plant_mode = is3z and "1by1" or "3zigzag"
        E.saveData()
    end

    ImGui.Text("ModFly (Terbang):")
    ImGui.SameLine()
    if safeButton(E.CFG.use_modfly and "[ ON ]##mf" or "[ OFF ]##mf", 72, 24) then
        E.CFG.use_modfly = not E.CFG.use_modfly
        E.saveData()
    end

    ImGui.Text("Abaikan Gems:")
    ImGui.SameLine()
    if safeButton(E.CFG.ignore_gems and "[ ON ]##ig" or "[ OFF ]##ig", 72, 24) then
        E.CFG.ignore_gems = not E.CFG.ignore_gems
        E.saveData()
    end

    ImGui.Separator()

    -- Delay controls dengan tombol - / + (100% aman di semua versi GL)
    ImGui.Text("Plant Delay: " .. tostring(E.CFG.plant_delay) .. " ms")
    ImGui.SameLine()
    if safeButton("-20##pd1", 44, 22) then
        E.CFG.plant_delay = math.max(80, (tonumber(E.CFG.plant_delay) or 180) - 20)
        E.saveData()
    end
    ImGui.SameLine()
    if safeButton("+20##pd2", 44, 22) then
        E.CFG.plant_delay = math.min(500, (tonumber(E.CFG.plant_delay) or 180) + 20)
        E.saveData()
    end

    ImGui.Text("Splice Delay: " .. tostring(E.CFG.splice_delay) .. " ms")
    ImGui.SameLine()
    if safeButton("-20##sd1", 44, 22) then
        E.CFG.splice_delay = math.max(80, (tonumber(E.CFG.splice_delay) or 180) - 20)
        E.saveData()
    end
    ImGui.SameLine()
    if safeButton("+20##sd2", 44, 22) then
        E.CFG.splice_delay = math.min(500, (tonumber(E.CFG.splice_delay) or 180) + 20)
        E.saveData()
    end

    ImGui.Text("Step Delay: " .. tostring(E.CFG.step_delay) .. " ms")
    ImGui.SameLine()
    if safeButton("-10##wd1", 44, 22) then
        E.CFG.step_delay = math.max(40, (tonumber(E.CFG.step_delay) or 110) - 10)
        E.saveData()
    end
    ImGui.SameLine()
    if safeButton("+10##wd2", 44, 22) then
        E.CFG.step_delay = math.min(350, (tonumber(E.CFG.step_delay) or 110) + 10)
        E.saveData()
    end

    ImGui.Separator()
    ImGui.TextWrapped("Tip: Ketik /hub di chat game untuk sembunyikan / tampilkan jendela ini kapan saja.")
end

-- ============================================================================
-- TAB 3: LOGS
-- ============================================================================
local function renderLogsTab()
    local logs = HUB.logs or {}
    if safeButton("Clear Logs", 90, 24) then
        HUB.logs = {}
        if HUB.plant then HUB.plant.STATE.logs = {} end
    end
    ImGui.SameLine()
    if safeButton("Copy Logs", 90, 24) then
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
-- MAIN IMGUI RENDER LOOP (100% STACK-SAFE, ZERO RISKY BINDINGS)
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
        if ImGui.SetNextWindowSize and ImVec2 then
            pcall(ImGui.SetNextWindowSize, ImVec2(125, 60), (ImGui.Cond and ImGui.Cond.Once) or 2)
        end
        if ImGui.Begin("Boren Hub") then
            if safeButton("Buka Hub", 105, 26) then
                windowOpen = true
            end
        end
        ImGui.End()
        return
    end

    if ImGui.SetNextWindowSize and ImVec2 then
        pcall(ImGui.SetNextWindowSize, ImVec2(580, 380), (ImGui.Cond and ImGui.Cond.Once) or 2)
    end

    if ImGui.Begin("Boren Hub - Auto Plant") then
        -- Navigasi Tab Modular (mudah ditambah fitur baru nanti)
        if safeButton(activeTab == "plant" and "> Plant <" or "Plant", 90, 26) then activeTab = "plant" end
        ImGui.SameLine()
        if safeButton(activeTab == "settings" and "> Settings <" or "Settings", 95, 26) then activeTab = "settings" end
        ImGui.SameLine()
        if safeButton(activeTab == "logs" and "> Logs <" or "Logs", 80, 26) then activeTab = "logs" end
        ImGui.SameLine()
        if safeButton("Hide", 60, 26) then windowOpen = false end

        ImGui.Separator()

        if activeTab == "plant" then
            renderPlantTab()
        elseif activeTab == "settings" then
            renderSettingsTab()
        else
            renderLogsTab()
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
