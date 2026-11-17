-- ============================================================================
-- BOREN HUB IMGUI - MAIN SHELL, SIDEBAR & HOOK MANAGER
-- File: imgui_hub/hub_shell.lua
-- ============================================================================

local Shell = {}

local HUB = nil
local activeTabId = "plant"
local windowOpen = true

-- Tab bawaan: Settings & Logs (agar tab Plant tetap bersih 100% seperti referensi)
local function renderSettingsTab()
    local W = HUB.widgets
    local E = HUB.plant
    if not W or not E then return end

    W.textColored(W.COLORS.statusActive, "Pengaturan Engine Auto Plant")
    if ImGui.Separator then ImGui.Separator() end
    if ImGui.Spacing then ImGui.Spacing() end

    -- Mode Tanam
    ImGui.Text("Mode Tanam:")
    ImGui.SameLine(150)
    local is3z = (E.CFG.plant_mode == "3zigzag")
    if ImGui.Button(is3z and "3-Zigzag (Cepat)##mode" or "1-by-1 (Presisi)##mode", W.vec2(160, 0)) then
        E.CFG.plant_mode = is3z and "1by1" or "3zigzag"
        E.saveData()
    end

    -- ModFly Toggle
    ImGui.Text("ModFly (Terbang):")
    ImGui.SameLine(150)
    local chMf, newMf = W.toggleSwitch("cfg_modfly", E.CFG.use_modfly)
    if chMf then
        E.CFG.use_modfly = newMf
        E.saveData()
    end

    -- Ignore Gems Toggle
    ImGui.Text("Abaikan Gems:")
    ImGui.SameLine(150)
    local chIg, newIg = W.toggleSwitch("cfg_ignore_gems", E.CFG.ignore_gems)
    if chIg then
        E.CFG.ignore_gems = newIg
        E.saveData()
    end

    if ImGui.Spacing then ImGui.Spacing() end

    -- Sliders Delay
    if ImGui.SliderInt then
        local chP, valP = ImGui.SliderInt("Plant Delay (ms)", math.floor(tonumber(E.CFG.plant_delay) or 180), 80, 500)
        if chP and tonumber(valP) then E.CFG.plant_delay = tonumber(valP); E.saveData() end

        local chS, valS = ImGui.SliderInt("Splice Delay (ms)", math.floor(tonumber(E.CFG.splice_delay) or 180), 80, 500)
        if chS and tonumber(valS) then E.CFG.splice_delay = tonumber(valS); E.saveData() end

        local chW, valW = ImGui.SliderInt("Step Delay (ms)", math.floor(tonumber(E.CFG.step_delay) or 110), 40, 350)
        if chW and tonumber(valW) then E.CFG.step_delay = tonumber(valW); E.saveData() end
    end

    if ImGui.SliderFloat then
        local chF, valF = ImGui.SliderFloat("Skala Font UI", tonumber(E.CFG.font_scale) or 1.0, 0.75, 1.50, "%.2f")
        if chF and tonumber(valF) then E.CFG.font_scale = tonumber(valF); E.saveData() end
    end

    if ImGui.Spacing then ImGui.Spacing() end
    if ImGui.Separator then ImGui.Separator() end
    W.textColored(W.COLORS.textMuted, "Tip: Ketik /hub di chat game untuk sembunyikan / tampilkan jendela ini.")
end

local function renderLogsTab()
    local W = HUB.widgets
    local logs = HUB.logs or {}

    if ImGui.Button("Clear Logs", W.vec2(90, 0)) then
        HUB.logs = {}
        if HUB.plant then HUB.plant.STATE.logs = {} end
    end
    ImGui.SameLine()
    if ImGui.Button("Copy Logs", W.vec2(90, 0)) then
        if ImGui.SetClipboardText then
            pcall(ImGui.SetClipboardText, table.concat(logs, "\n"))
            if sendNotification then pcall(sendNotification, "Logs disalin ke clipboard!") end
        end
    end
    if ImGui.Separator then ImGui.Separator() end

    if ImGui.BeginChild("##hub_logs_scroll", W.vec2(0, 0), true) then
        if #logs == 0 then
            W.textColored(W.COLORS.textMuted, "Belum ada aktivitas tercatat.")
        else
            for i = 1, math.min(60, #logs) do
                ImGui.TextWrapped(tostring(logs[i]))
            end
        end
        ImGui.EndChild()
    end
end

-- Fungsi render utama ImGui setiap frame
local function renderImGuiFrame()
    if not ImGui or not HUB or not HUB.widgets then return end
    local W = HUB.widgets

    pcall(function()
        local colCount, varCount = W.pushTheme()

        -- Jika jendela disembunyikan, tampilkan tombol mini melayang untuk membuka kembali
        if not windowOpen then
            local wf = ImGui.WindowFlags or {}
            local miniFlags = (wf.NoTitleBar or 1) + (wf.AlwaysAutoResize or 64) + (wf.NoCollapse or 32)
            if ImGui.SetNextWindowPos then
                ImGui.SetNextWindowPos(W.vec2(16, 120), (ImGui.Cond and ImGui.Cond.FirstUseEver) or 4)
            end
            if ImGui.Begin("##boren_hub_mini", nil, miniFlags) then
                if ImGui.Button("Boren Hub", W.vec2(92, 28)) then
                    windowOpen = true
                    if editToggle then pcall(editToggle, "bh_show_imgui", true) end
                end
            end
            ImGui.End()
            W.popTheme(colCount, varCount)
            return
        end

        if ImGui.SetNextWindowSize then
            ImGui.SetNextWindowSize(W.vec2(650, 410), (ImGui.Cond and ImGui.Cond.FirstUseEver) or 4)
        end

        local title = "Boren Hub  |  " .. tostring(HUB.plant and HUB.plant.STATE.status_text or "Ready") .. "###BorenHubMain"
        local winOpen = ImGui.Begin(title)
        if winOpen then
            if ImGui.SetWindowFontScale and HUB.plant and HUB.plant.CFG.font_scale then
                pcall(ImGui.SetWindowFontScale, tonumber(HUB.plant.CFG.font_scale) or 1.0)
            end

            -- ================================================================
            -- SIDEBAR KIRI (Navigasi Vertikal Modular)
            -- ================================================================
            local sidebarW = 112
            if ImGui.BeginChild("##hub_sidebar", W.vec2(sidebarW, 0), true) then
                local C = ImGui.Col or {}
                for _, tab in ipairs(HUB.tabs) do
                    local isAct = (activeTabId == tab.id)
                    local pushed = 0
                    if C.Button and ImGui.PushStyleColor then
                        ImGui.PushStyleColor(C.Button, isAct and W.COLORS.sidebarActive or W.COLORS.sidebarInactive)
                        pushed = pushed + 1
                    end
                    if ImGui.Button(tab.label .. "##tab_" .. tab.id, W.vec2(-1, 30)) then
                        activeTabId = tab.id
                    end
                    if pushed > 0 and ImGui.PopStyleColor then
                        ImGui.PopStyleColor(pushed)
                    end
                end

                -- Tombol Hide di bagian bawah sidebar
                if ImGui.Separator then ImGui.Separator() end
                if ImGui.Button("Hide UI", W.vec2(-1, 26)) then
                    windowOpen = false
                    if editToggle then pcall(editToggle, "bh_show_imgui", false) end
                end
                ImGui.EndChild()
            end

            ImGui.SameLine()

            -- ================================================================
            -- PANEL KANAN (Konten Tab Aktif)
            -- ================================================================
            if ImGui.BeginChild("##hub_content", W.vec2(0, 0), true) then
                for _, tab in ipairs(HUB.tabs) do
                    if tab.id == activeTabId and type(tab.render) == "function" then
                        tab.render(HUB)
                        break
                    end
                end
                ImGui.EndChild()
            end
        end
        ImGui.End()

        W.popTheme(colCount, varCount)
    end)
end

-- Registrasi 1 toggle kecil di Native UI GL agar mudah buka/tutup di Android
local function registerNativeToggle()
    if not UserInterface or not addCategory or not addIntoModule then return end
    pcall(function()
        addCategory("Boren Hub", "Wysiwyg")
        local ui = UserInterface.new("ImGui Hub", "Wysiwyg")
        ui:addLabelApp("Boren Hub (Modular ImGui)", "Wysiwyg")
        ui:addTooltip("Info", "Aktifkan untuk menampilkan jendela Boren Hub ImGui. Bisa juga ketik /hub di chat.", "Info", false)
        ui:addToggle("Tampilkan Jendela ImGui", windowOpen, "bh_show_imgui", false)
        addIntoModule(ui:generateJSON(), "Boren Hub")
    end)
end

-- Chat command /hub untuk toggle cepat
local function onSendPacketHook(pktType, pktStr)
    if type(pktStr) == "string" then
        local txt = pktStr:match("text|([^\n\r]+)")
        if txt then
            local cmd = txt:lower():gsub("^%s+", ""):gsub("%s+$", "")
            if cmd == "/hub" then
                windowOpen = not windowOpen
                if editToggle then pcall(editToggle, "bh_show_imgui", windowOpen) end
                if LogToConsole then
                    pcall(LogToConsole, "`e[Boren Hub] `wJendela ImGui " .. (windowOpen and "`2DITAMPILKAN" or "`4DISEMBUNYIKAN"))
                end
                return true
            end
        end
    end
    return false
end

-- Hook Anti-Gems (jika opsi Ignore Gems aktif)
local function onSendPacketRawHook(pkt)
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
                        if oid == 112 then return true end -- Blokir gems
                        break
                    end
                end
            end
        end
    end
    return false
end

function Shell.init(hubContext)
    HUB = hubContext
    HUB.logs = HUB.logs or {}
    HUB.tabs = HUB.tabs or {}

    -- Pastikan tab bawaan (Settings & Logs) ditambahkan setelah tab fitur
    table.insert(HUB.tabs, { id = "settings", label = "Settings", render = renderSettingsTab })
    table.insert(HUB.tabs, { id = "logs",     label = "Logs",     render = renderLogsTab })

    if #HUB.tabs > 0 then
        activeTabId = HUB.tabs[1].id
    end

    -- Pasang global callback & hook lintas versi Growlauncher
    onDrawImGui = renderImGuiFrame
    OnDrawImGui = renderImGuiFrame

    if addHook then
        pcall(addHook, renderImGuiFrame, "ondrawimgui")
        pcall(addHook, onSendPacketHook, "onsendpacket")
        pcall(addHook, onSendPacketRawHook, "onsendpacketraw")
    end

    if setOnValue then
        pcall(setOnValue, "bh_show_imgui", function(val)
            windowOpen = (val == true or val == 1)
        end)
    else
        local prevOnVal = OnValue
        OnValue = function(t, name, val)
            if name == "bh_show_imgui" then
                windowOpen = (val == true or val == 1)
                return
            end
            if prevOnVal then pcall(prevOnVal, t, name, val) end
        end
        onValue = OnValue
    end

    registerNativeToggle()

    if applyHook then
        pcall(applyHook)
    end
end

return Shell
