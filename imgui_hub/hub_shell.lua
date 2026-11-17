-- ============================================================================
-- BOREN HUB IMGUI - STACK-SAFE MAIN SHELL, SIDEBAR & HOOK MANAGER
-- File: imgui_hub/hub_shell.lua
-- ============================================================================

local Shell = {}

local HUB = nil
local activeTabId = "plant"
local windowOpen = true
local lastFrameCount = -1
local lastRenderErr = ""

local function logRenderErrorOnce(err)
    local s = tostring(err or "")
    if s ~= "" and s ~= lastRenderErr then
        lastRenderErr = s
        if LogToConsole then
            pcall(LogToConsole, "`4[Boren Hub UI Error] `w" .. s)
        end
    end
end

-- Tab bawaan: Settings
local function renderSettingsTab()
    local W = HUB.widgets
    local E = HUB.plant
    if not W or not E then return end
    local pal = W.getColors()

    W.textColored(pal.statusActive, "Pengaturan Engine Auto Plant")
    if ImGui.Separator then ImGui.Separator() end

    ImGui.Text("Mode Tanam: ")
    ImGui.SameLine()
    local is3z = (E.CFG.plant_mode == "3zigzag")
    if W.button(is3z and "3-Zigzag (Cepat)##mode" or "1-by-1 (Presisi)##mode", 160, 0) then
        E.CFG.plant_mode = is3z and "1by1" or "3zigzag"
        E.saveData()
    end

    ImGui.Text("ModFly:     ")
    ImGui.SameLine()
    local chMf, newMf = W.toggleSwitch("cfg_modfly", E.CFG.use_modfly)
    if chMf then E.CFG.use_modfly = newMf; E.saveData() end

    ImGui.Text("Abaikan Gems:")
    ImGui.SameLine()
    local chIg, newIg = W.toggleSwitch("cfg_ignore_gems", E.CFG.ignore_gems)
    if chIg then E.CFG.ignore_gems = newIg; E.saveData() end

    if ImGui.Separator then ImGui.Separator() end

    if ImGui.SliderInt then
        local ok1, chP, valP = pcall(ImGui.SliderInt, "Plant Delay (ms)", math.floor(tonumber(E.CFG.plant_delay) or 180), 80, 500)
        if ok1 and chP and tonumber(valP) then E.CFG.plant_delay = tonumber(valP); E.saveData() end

        local ok2, chS, valS = pcall(ImGui.SliderInt, "Splice Delay (ms)", math.floor(tonumber(E.CFG.splice_delay) or 180), 80, 500)
        if ok2 and chS and tonumber(valS) then E.CFG.splice_delay = tonumber(valS); E.saveData() end

        local ok3, chW, valW = pcall(ImGui.SliderInt, "Step Delay (ms)", math.floor(tonumber(E.CFG.step_delay) or 110), 40, 350)
        if ok3 and chW and tonumber(valW) then E.CFG.step_delay = tonumber(valW); E.saveData() end
    end

    if ImGui.SliderFloat then
        local ok4, chF, valF = pcall(ImGui.SliderFloat, "Skala Font UI", tonumber(E.CFG.font_scale) or 1.0, 0.75, 1.50, "%.2f")
        if ok4 and chF and tonumber(valF) then E.CFG.font_scale = tonumber(valF); E.saveData() end
    end

    if ImGui.Separator then ImGui.Separator() end
    W.textColored(pal.textMuted, "Tip: Ketik /hub di chat game untuk buka / tutup jendela ini.")
end

-- Tab bawaan: Logs (stack-safe BeginChild / EndChild)
local function renderLogsTab()
    local W = HUB.widgets
    local pal = W.getColors()
    local logs = HUB.logs or {}

    if W.button("Clear Logs", 90, 0) then
        HUB.logs = {}
        if HUB.plant then HUB.plant.STATE.logs = {} end
    end
    ImGui.SameLine()
    if W.button("Copy Logs", 90, 0) then
        if ImGui.SetClipboardText then
            pcall(ImGui.SetClipboardText, table.concat(logs, "\n"))
            if sendNotification then pcall(sendNotification, "Logs disalin ke clipboard!") end
        end
    end
    if ImGui.Separator then ImGui.Separator() end

    if ImGui.BeginChild then
        local sz = W.vec2(0, 0)
        local okC, openC = false, false
        if sz then okC, openC = pcall(ImGui.BeginChild, "##hub_logs_scroll", sz, true)
        else okC, openC = pcall(ImGui.BeginChild, "##hub_logs_scroll") end
        if okC then
            if openC then
                if #logs == 0 then
                    W.textColored(pal.textMuted, "Belum ada aktivitas tercatat.")
                else
                    for i = 1, math.min(50, #logs) do
                        ImGui.TextWrapped(tostring(logs[i]))
                    end
                end
            end
            -- WAJIB selalu dipanggil!
            ImGui.EndChild()
        end
    end
end

-- Fungsi render utama ImGui (100% stack-balanced — TIDAK PERNAH melewati End/EndChild/Pop!)
local function renderImGuiFrame()
    if not ImGui or not HUB or not HUB.widgets then return end

    -- Anti double-render di frame yang sama
    if ImGui.GetFrameCount then
        local okFc, fc = pcall(ImGui.GetFrameCount)
        if okFc and type(fc) == "number" then
            if fc == lastFrameCount then return end
            lastFrameCount = fc
        end
    end

    local W = HUB.widgets
    local colCount, varCount = W.pushTheme()

    -- JIKA DISEMBUNYIKAN: tampilkan tombol mini (1-arg ImGui.Begin agar 100% aman)
    if not windowOpen then
        if ImGui.SetNextWindowSize then
            local szMini = W.vec2(120, 62)
            if szMini then
                pcall(ImGui.SetNextWindowSize, szMini, (ImGui.Cond and ImGui.Cond.FirstUseEver) or 4)
            end
        end
        local okB, openB = pcall(ImGui.Begin, "Boren Hub##mini")
        if okB then
            if openB then
                if W.button("Buka Hub", 100, 26) then
                    windowOpen = true
                    if editToggle then pcall(editToggle, "bh_show_imgui", true) end
                end
            end
            ImGui.End()
        end
        W.popTheme(colCount, varCount)
        return
    end

    -- JENDELA UTAMA BOREN HUB
    if ImGui.SetNextWindowSize then
        local szMain = W.vec2(640, 400)
        if szMain then
            pcall(ImGui.SetNextWindowSize, szMain, (ImGui.Cond and ImGui.Cond.FirstUseEver) or 4)
        end
    end

    local title = "Boren Hub | " .. tostring(HUB.plant and HUB.plant.STATE.status_text or "Ready") .. "###BorenHubMain"
    local okMain, mainOpen = pcall(ImGui.Begin, title)
    if okMain then
        if mainOpen then
            if ImGui.SetWindowFontScale and HUB.plant and HUB.plant.CFG.font_scale then
                local sc = tonumber(HUB.plant.CFG.font_scale) or 1.0
                if sc ~= 1.0 then pcall(ImGui.SetWindowFontScale, sc) end
            end

            -- ================================================================
            -- 1. SIDEBAR KIRI (BeginChild + EndChild UNCONDITIONAL)
            -- ================================================================
            local sidebarSz = W.vec2(110, 0)
            local okSide, sideOpen = false, false
            if ImGui.BeginChild then
                if sidebarSz then
                    okSide, sideOpen = pcall(ImGui.BeginChild, "##hub_sidebar", sidebarSz, true)
                else
                    okSide, sideOpen = pcall(ImGui.BeginChild, "##hub_sidebar")
                end
            end

            if okSide then
                if sideOpen then
                    local okInner, errInner = pcall(function()
                        local C = ImGui.Col or {}
                        local pal = W.getColors()
                        for _, tab in ipairs(HUB.tabs) do
                            local isAct = (activeTabId == tab.id)
                            local pushed = 0
                            if C.Button and ImGui.PushStyleColor then
                                local cBtn = isAct and pal.sidebarActive or pal.sidebarInactive
                                if cBtn and pcall(ImGui.PushStyleColor, C.Button, cBtn) then
                                    pushed = pushed + 1
                                end
                            end
                            if W.button(tab.label .. "##tab_" .. tab.id, 94, 30) then
                                activeTabId = tab.id
                            end
                            if pushed > 0 and ImGui.PopStyleColor then
                                pcall(ImGui.PopStyleColor, pushed)
                            end
                        end

                        if ImGui.Separator then ImGui.Separator() end
                        if W.button("Hide UI", 94, 26) then
                            windowOpen = false
                            if editToggle then pcall(editToggle, "bh_show_imgui", false) end
                        end
                    end)
                    if not okInner then logRenderErrorOnce(errInner) end
                end
                -- WAJIB dipanggil selalu!
                ImGui.EndChild()
            end

            ImGui.SameLine()

            -- ================================================================
            -- 2. PANEL KANAN (BeginChild + EndChild UNCONDITIONAL)
            -- ================================================================
            local contentSz = W.vec2(0, 0)
            local okCont, contOpen = false, false
            if ImGui.BeginChild then
                if contentSz then
                    okCont, contOpen = pcall(ImGui.BeginChild, "##hub_content", contentSz, true)
                else
                    okCont, contOpen = pcall(ImGui.BeginChild, "##hub_content")
                end
            end

            if okCont then
                if contOpen then
                    local okTab, errTab = pcall(function()
                        for _, tab in ipairs(HUB.tabs) do
                            if tab.id == activeTabId and type(tab.render) == "function" then
                                tab.render(HUB)
                                break
                            end
                        end
                    end)
                    if not okTab then logRenderErrorOnce(errTab) end
                end
                -- WAJIB dipanggil selalu!
                ImGui.EndChild()
            end
        end

        -- WAJIB dipanggil selalu!
        ImGui.End()
    end

    -- WAJIB pop style selalu!
    W.popTheme(colCount, varCount)
end

-- Registrasi Native UI secara aman di background coroutine (seperti world_saver.lua & calculator.lua)
local function registerNativeToggleDeferred()
    if not UserInterface or not addCategory or not addIntoModule then return end
    local function doReg()
        if sleep then pcall(sleep, 1500) elseif CSleep then pcall(CSleep, 1500) end
        pcall(function()
            addCategory("Boren Hub", "Storefront")
            local ui = UserInterface.new("ImGui Hub", "Storefront")
            ui:addLabelApp("Boren Hub (Modular ImGui)", "Storefront")
            ui:addTooltip("Info", "Aktifkan untuk menampilkan jendela Boren Hub ImGui. Bisa juga ketik /hub di chat.", "Info", false)
            ui:addToggle("Tampilkan Jendela ImGui", windowOpen, "bh_show_imgui", false)
            addIntoModule(ui:generateJSON(), "Boren Hub")
        end)
    end
    if runCoroutine then
        pcall(runCoroutine, doReg)
    end
end

-- Chat command /hub untuk toggle cepat
local function handleSendPacket(pktType, pktStr)
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

-- Hook Anti-Gems
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

function Shell.init(hubContext)
    HUB = hubContext
    HUB.logs = HUB.logs or {}
    HUB.tabs = HUB.tabs or {}

    table.insert(HUB.tabs, { id = "settings", label = "Settings", render = renderSettingsTab })
    table.insert(HUB.tabs, { id = "logs",     label = "Logs",     render = renderLogsTab })

    if #HUB.tabs > 0 then
        activeTabId = HUB.tabs[1].id
    end

    -- Gunakan pola resmi Growlauncher (seperti world_saver.lua & calculator.lua):
    -- JANGAN double-register OnDrawImGui + addHook("ondrawimgui") sekaligus!
    OnDrawImGui = renderImGuiFrame
    onDrawImGui = renderImGuiFrame

    if addHook then
        pcall(addHook, handleSendPacket, "onsendpacket")
        pcall(addHook, handleSendPacketRaw, "onsendpacketraw")
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

    if applyHook then
        pcall(applyHook)
    end

    registerNativeToggleDeferred()
end

return Shell
