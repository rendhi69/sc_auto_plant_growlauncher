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

-- ============================================================================
-- TEMA RESMI BOREN STORE (Midnight Obsidian + Neon Cyan #00CDFC + Violet #8B3DFF)
-- ============================================================================
local vec4Ok = nil
local borenPal = nil

local function canUseImVec4()
    if vec4Ok ~= nil then return vec4Ok end
    if ImVec4 then
        local ok, v = pcall(ImVec4, 1.0, 1.0, 1.0, 1.0)
        vec4Ok = (ok and v ~= nil)
    else
        vec4Ok = false
    end
    return vec4Ok
end

local function v4(r, g, b, a)
    if canUseImVec4() then
        local ok, c = pcall(ImVec4, r, g, b, a or 1.0)
        if ok and c then return c end
    end
    return nil
end

local function getBorenPal()
    if borenPal then return borenPal end
    borenPal = {
        -- Base Midnight Obsidian (sampled dari logo BOREN #04050A & #04163A)
        windowBg        = v4(0.025, 0.032, 0.068, 0.89),
        childBg         = v4(0.032, 0.044, 0.095, 0.78),
        popupBg         = v4(0.035, 0.048, 0.110, 0.96),
        border          = v4(0.040, 0.680, 0.960, 0.52),
        borderShadow    = v4(0.350, 0.050, 0.970, 0.16),

        -- Title Bar (Deep Indigo -> Electric Violet)
        titleBg         = v4(0.035, 0.048, 0.125, 0.96),
        titleBgActive   = v4(0.115, 0.068, 0.300, 0.98),
        titleBgColl     = v4(0.035, 0.048, 0.125, 0.90),

        -- Inputs & Frames
        frameBg         = v4(0.055, 0.088, 0.185, 0.92),
        frameBgHover    = v4(0.065, 0.195, 0.355, 0.95),
        frameBgActive   = v4(0.215, 0.115, 0.480, 0.98),

        -- Buttons (Default Cyber Navy -> Hover Cyan -> Click Purple)
        btn             = v4(0.065, 0.105, 0.215, 0.92),
        btnHover        = v4(0.045, 0.420, 0.690, 0.96),
        btnActive       = v4(0.410, 0.140, 0.920, 1.00),

        -- Active Menu / Tab Accent (Vivid BOREN Violet-Cyan)
        accentBtn       = v4(0.350, 0.125, 0.860, 0.96),
        accentBtnHover  = v4(0.455, 0.205, 0.960, 1.00),
        accentBtnActive = v4(0.020, 0.660, 0.960, 1.00),
        accentBorder    = v4(0.000, 0.804, 0.988, 0.92),

        -- Muted Utility Button (Hide UI)
        mutedBtn        = v4(0.050, 0.065, 0.135, 0.85),
        mutedBtnHover   = v4(0.160, 0.095, 0.285, 0.92),

        -- Headers, Tables, Separators, Scrollbars
        header          = v4(0.110, 0.145, 0.340, 0.88),
        headerHover     = v4(0.055, 0.430, 0.720, 0.94),
        headerActive    = v4(0.380, 0.150, 0.890, 1.00),
        separator       = v4(0.020, 0.720, 0.980, 0.38),
        checkMark       = v4(0.000, 0.840, 1.000, 1.00),
        sliderGrab      = v4(0.000, 0.780, 0.980, 1.00),
        sliderGrabAct   = v4(0.560, 0.220, 1.000, 1.00),
        scrollBg        = v4(0.025, 0.035, 0.075, 0.75),
        scrollGrab      = v4(0.140, 0.260, 0.520, 0.85),
        scrollGrabHov   = v4(0.040, 0.640, 0.940, 0.95),
        scrollGrabAct   = v4(0.480, 0.180, 0.960, 1.00),
        tableHeader     = v4(0.095, 0.085, 0.255, 0.96),
        tableRow        = v4(0.035, 0.052, 0.115, 0.52),
        tableRowAlt     = v4(0.050, 0.072, 0.155, 0.65),
        tableBorderS    = v4(0.060, 0.520, 0.820, 0.50),
        tableBorderL    = v4(0.140, 0.200, 0.420, 0.42),

        -- Typography (Ice White #EDF7F8 + Neon Cyan #00CDFC + Violet + Emerald)
        text            = v4(0.929, 0.969, 0.973, 1.00),
        textMuted       = v4(0.565, 0.680, 0.825, 1.00),
        textCyan        = v4(0.000, 0.835, 1.000, 1.00),
        textPurple      = v4(0.745, 0.440, 1.000, 1.00),
        textActive      = v4(0.240, 0.950, 0.660, 1.00),
    }
    return borenPal
end

local function pushBorenTheme()
    local cCnt, vCnt = 0, 0
    if not ImGui then return 0, 0 end
    local C = ImGui.Col
    local V = ImGui.StyleVar
    local P = getBorenPal()

    if ImGui.PushStyleColor and C and canUseImVec4() then
        local function pc(idx, col)
            if idx ~= nil and col ~= nil then
                if pcall(ImGui.PushStyleColor, idx, col) then cCnt = cCnt + 1 end
            end
        end
        pc(C.WindowBg,             P.windowBg)
        pc(C.ChildBg,              P.childBg)
        pc(C.PopupBg,              P.popupBg)
        pc(C.Border,               P.border)
        pc(C.BorderShadow,         P.borderShadow)
        pc(C.TitleBg,              P.titleBg)
        pc(C.TitleBgActive,        P.titleBgActive)
        pc(C.TitleBgCollapsed,     P.titleBgColl)
        pc(C.FrameBg,              P.frameBg)
        pc(C.FrameBgHovered,       P.frameBgHover)
        pc(C.FrameBgActive,        P.frameBgActive)
        pc(C.Button,               P.btn)
        pc(C.ButtonHovered,        P.btnHover)
        pc(C.ButtonActive,         P.btnActive)
        pc(C.Header,               P.header)
        pc(C.HeaderHovered,        P.headerHover)
        pc(C.HeaderActive,         P.headerActive)
        pc(C.Separator,            P.separator)
        pc(C.CheckMark,            P.checkMark)
        pc(C.SliderGrab,           P.sliderGrab)
        pc(C.SliderGrabActive,     P.sliderGrabAct)
        pc(C.ScrollbarBg,          P.scrollBg)
        pc(C.ScrollbarGrab,        P.scrollGrab)
        pc(C.ScrollbarGrabHovered, P.scrollGrabHov)
        pc(C.ScrollbarGrabActive,  P.scrollGrabAct)
        pc(C.TableHeaderBg,        P.tableHeader)
        pc(C.TableRowBg,           P.tableRow)
        pc(C.TableRowBgAlt,        P.tableRowAlt)
        pc(C.TableBorderStrong,    P.tableBorderS)
        pc(C.TableBorderLight,     P.tableBorderL)
        pc(C.Text,                 P.text)
        pc(C.TextDisabled,         P.textMuted)
    end

    if ImGui.PushStyleVar and V then
        local function pv(idx, val)
            if idx ~= nil and val ~= nil then
                if pcall(ImGui.PushStyleVar, idx, val) then vCnt = vCnt + 1 end
            end
        end
        pv(V.WindowRounding,    8.0)
        pv(V.FrameRounding,     6.0)
        pv(V.ChildRounding,     6.0)
        pv(V.PopupRounding,     6.0)
        pv(V.GrabRounding,      5.0)
        pv(V.ScrollbarRounding, 6.0)
        pv(V.WindowBorderSize,  1.2)
        pv(V.FrameBorderSize,   1.0)
    end
    return cCnt, vCnt
end

local function popBorenTheme(cCnt, vCnt)
    if vCnt and vCnt > 0 and ImGui and ImGui.PopStyleVar then
        pcall(ImGui.PopStyleVar, vCnt)
    end
    if cCnt and cCnt > 0 and ImGui and ImGui.PopStyleColor then
        pcall(ImGui.PopStyleColor, cCnt)
    end
end

local function coloredText(col, txt)
    local s = tostring(txt or "")
    if col and ImGui and ImGui.TextColored then
        local ok = pcall(ImGui.TextColored, col, s)
        if ok then return end
    end
    ImGui.Text(s)
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

-- Button dengan warna aksen BOREN (aktif / highlight)
local function styledBtn(label, width, isAccent, isMuted)
    local pushed = 0
    if (isAccent or isMuted) and ImGui and ImGui.PushStyleColor and ImGui.Col and canUseImVec4() then
        local C = ImGui.Col
        local P = getBorenPal()
        local function pc(idx, col)
            if idx ~= nil and col ~= nil and pcall(ImGui.PushStyleColor, idx, col) then
                pushed = pushed + 1
            end
        end
        if isAccent then
            pc(C.Button,        P.accentBtn)
            pc(C.ButtonHovered, P.accentBtnHover)
            pc(C.ButtonActive,  P.accentBtnActive)
            pc(C.Border,        P.accentBorder)
        elseif isMuted then
            pc(C.Button,        P.mutedBtn)
            pc(C.ButtonHovered, P.mutedBtnHover)
        end
    end
    local clicked = width and fullBtn(label, width) or (function()
        local ok, res = pcall(ImGui.Button, label)
        return ok and (res == true)
    end)()
    if pushed > 0 and ImGui and ImGui.PopStyleColor then
        pcall(ImGui.PopStyleColor, pushed)
    end
    return clicked
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
            local tNowMs = nil
            if getTime then
                local okT, ms = pcall(getTime)
                if okT and tonumber(ms) then tNowMs = math.floor(tonumber(ms)) end
            end
            if not tNowMs and os and os.time then
                local okO, ot = pcall(os.time)
                if okO and tonumber(ot) then tNowMs = math.floor(tonumber(ot)) end
            end
            local freshTag = tostring(tNowMs or math.random(100000, 999999)) .. "_" .. tostring(math.random(100, 999))
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

local dcCopiedUntil = 0
local ghCopiedUntil = 0
local rasterLogoOk  = true

local function nowSec()
    if getTime then
        local ok, ms = pcall(getTime)
        if ok and tonumber(ms) then return tonumber(ms) / 1000 end
    end
    if os and os.clock then return os.clock() end
    return 0
end

local function colU32(r, g, b, a)
    return math.floor(r) + math.floor(g) * 256 + math.floor(b) * 65536 + math.floor(a or 255) * 16777216
end

-- 64x64 Full-Color Anti-Aliased Raster Image (diekstrak langsung pixel-per-pixel dari gambar referensi)
local RASTER_ALPHA = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!#$"
local RASTER_MAP = {}
for i = 1, #RASTER_ALPHA do
    RASTER_MAP[RASTER_ALPHA:sub(i, i)] = i - 1
end

local function decodeRaster(encoded, pal)
    local runs = {}
    local n = #encoded
    local i = 1
    while i + 3 <= n do
        local y  = RASTER_MAP[encoded:sub(i, i)] or 0
        local sx = RASTER_MAP[encoded:sub(i + 1, i + 1)] or 0
        local ex = RASTER_MAP[encoded:sub(i + 2, i + 2)] or 0
        local ci = tonumber(encoded:sub(i + 3, i + 3)) or 1
        local col = pal[ci + 1] or pal[#pal]
        runs[#runs + 1] = { y, sx, ex, col }
        i = i + 4
    end
    return runs
end

local DC_BG_COL = colU32(3, 24, 41, 255)
local DC_PAL = {
    colU32(3, 24, 41, 255),
    colU32(31, 51, 84, 255),
    colU32(58, 78, 126, 255),
    colU32(86, 105, 169, 255),
    colU32(113, 132, 211, 255),
    colU32(141, 159, 254, 255),
}
local DC_RASTER = decodeRaster(
    "DKM1DMO2DOP1Dcd1Ddg2Dgi1EIJ1EJK2EKN5ENO4EOP2Ecd2Ede3Eef4Efh5Ehi3Eij2Ejk1FFG1FGH2FHI3FIK5FKL4FLM3FMN2FRa2Fab1Fef1Ffg2Fgh3Fhj5Fjk4Fkl3Flm1GEF1GFG4GGI5GIJ4GJK2GKL1GMN1GNO2GOR3GRS4GSa5Gab4Gbe3Gef2Ghi2Gij3Gjl5Glm4Gmn3HCD1HDE3HEF4HFH5HHI3HJK1HKM3HMN4HNf5Hfg4Hgh3Hhi2Hjk1Hkl4Hln5Hno4Hop3IBC1ICD3IDF5IFG3IGH2IHJ3IJK4IKi5Iik3Ikl2Ilm3Imn4Inp5Ipq3JBC2JCE5JEF4JFG3JGH4JHk5Jkm4Jmn3Jno4Jop5Jpq4Jqr1KBC4KCE5KEG4KGq5Kqr3LAB1LBq5Lqr4Lrs1M9A1MAB4MBr5Mrs3N9A1NAr5Nrs4O9A3OAs5Ost2P891P9A4PAs5Pst3Q892Q9s5Qst4Qtu1R893R9t5Rtu3S781S894S9t5Stu3T782T8t5Ttu4Tuv1U783U8L5ULM4UMN3UNP1UPQ3UQb5Ubc4Ucd2Udf1Ufg4Ugu5Uuv2V783V8K5VKL4VLM1VQR3VRa5Vab4Vbc2Vfg1Vgh2Vhu5Vuv2W671W784W8K5WKL1WRS3WSa5Wab2Wgh1Whi4Wiu5Wuv2X672X7K5XKL1XRS1XST4XTZ5XZa3Xhi2Xiu5Xuv4Xvw1Y673Y7J5YJK4YKL1YST4YTZ5YZa3Yhi1Yiv5Yvw2Z673Z7J5ZJK4ZKL1ZST4ZTZ5ZZa3Zhi1Ziv5Zvw2a673a7J5aJK4aKL1aST4aTZ5aZa3ahi1aiv5avw2b562b6K5bKL1bRS2bSZ5bZa4bab1bhi3biv5bvw2c562c6K5cKL3cQR2cRS4cSa5cab3cgh1chv5cvw3cwx1d562d6L5dLM4dMN2dPQ2dQb5dbc4dcd1dfg3dgh4dhw5dwx1e562e6M5eMP4ePc5ecf4efw5ewx2f562f6w5fwx2g562g6D5gDE4gEw5gwx2h562h6C5hCD4hDE3hEF4hFm5hmo4how5hwx2i562i6D5iDE4iEG3iGH4iHl5ilm4imn3ino4iow5iwx2j561j674j7F5jFG3jGI2jIJ4jJj5jjk3jkm2jmn4jnv5jvw4jwx1k671k784k8G5kGH4kIJ1kJK2kKL3kLg5kgh4khj2kkl2klm4kmu5kuv4kvw1l781l894l9H5lHI4lIJ2lJK1lLO2lOP3lPc5lcd4ldg2lgh1lij1ljk4lkt5ltu3luv1m891m9A3mAB4mBJ5mJK4mKL3mOP1mPc2mcd1mgh1mhi3mij4mjr5mrs4mst2mtu1nAB1nBC3nCL5nLM4nMN3nfg3ngh4nhp5npq4nqr2nrs1oCD1oDE2oEL5oLM4oMN1ofg2ogn5ono4oop2opq1pEG1pGH3pHL4pLM1pfg1pgl4plm2pmn1qHK1qhi1",
    DC_PAL
)

local GH_BG_COL = colU32(4, 24, 40, 255)
local GH_PAL = {
    colU32(4, 24, 40, 255),
    colU32(11, 27, 41, 255),
    colU32(17, 31, 42, 255),
    colU32(24, 34, 44, 255),
    colU32(30, 38, 45, 255),
    colU32(37, 41, 46, 255),
}
local GH_RASTER = decodeRaster(
    "5RS15Sc26NO16OR36RS46Sb56bc46cf36fg27LM17MN37NO47Of57fg47gh37hi28JK28KL38LM48Mh58hi48ij38jk29GI19IJ29JK39Kj59jl49lm1AFG1AGI4AIm5Amn4Ano1BFG3BGn5Bno4Bop1CDE1CEF3CFH4CHo5Cop4Cpq1DDE3DEp5Dpq4Dqr1ECD2EDE4EEq5Eqr4Ers1FAB1FBC2FCD4FDr5Frs4Fst1G9A1GAB3GBC4GCs5Gst4Gtu1H9A2HAB4HBH5HHI3HIJ2HJK1HKM2HMN4HNh5Hhi3Hik2Hkl1Hlm2Hmn4Hnt5Htu4Huv1I891I9A3IAG5IGH4IHI2IMN1INO3IOf5Ifg4Igh2Imn4Inu5Iuv2J781J893J9A4JAG5JGH4JNP1JPQ3JQR5JRS2JSc1Jcd3Jde4Jef2Jfg1Jmn4Jnu5Juv4Jvw1K782K894K9G5KGH4KHI1KPR1Kde1Kmn4Knv5Kvw2L783L8H5LHI1Lmn4Lnv5Lvw4Lwx1M671M784M8H5MHI1Mmn4Mnw5Mwx2N561N672N7H5NHI1Nmn4Nnx5Nxy1O561O672O7G5OGH4OHI1Omn4Onx5Oxy1P561P673P784P8F5PFG4PGH3PHI1Pmn3Pnx5Pxy2Q563Q6F5QFG4QGH2Qmn1Qno4Qox5Qxy4Qyz1R563R6F5RFG3RGH1Rno2Rox5Rxy4Ryz1S563S6F5SFG3Sno1Sox5Sxy4Syz1T563T6F5TFG3Tno1Tox5Txy4Tyz1U451U563U6F5UFG3Uno1Uop4Upy5Uyz2V452V564V6F5VFG3Vop3Vpy5Vyz3W453W564W6F5WFG3Wop3Wpy5Wyz4X452X564X6F5XFG3Xop3Xpy5Xyz4Y452Y564Y6F5YFG3Yno1Yop4Ypy5Yyz4Z452Z564Z6F5ZFG3Zno1Zoy5Zyz3a451a563a6F5aFG3ano1aoy5ayz2b563b6F5bFG3bGH1bno1box5bxy4byz1c562c6F5cFG4cGH1cno3cox5cxy4cyz1d562d6F5dFG4dGH2dmn1dnx5dxy4dyz1e562e684e8G5eGH3eHI1emn3enx5exy4eyz1f562f684f8H5fHI3fIJ2fkl1flm2fmn4fnx5fxy2g561g673g7I5gIJ3gJK1gjk1gkl3glx5gxy1h672h7J5hJK4hKL2hij1hjk4hkw5hwx4hxy1i671i784i8A5iAE4iEH3iHI4iIL5iLM3iMN2iNO1ifg1igi2iij4ijw5iwx2j782j894j9A5jAC4jCD3jDE2jGH1jHI4jIN5jNO4jOP3jPR2jRS1jcf2jfg3jgv5jvw4jwx1k893k9C5kCE4kEF1kHI4kIQ5kQR4kRS1kcd2kdv5kvw2l892l9E5lEF3lFH1lHI2lIJ3lJQ5lQR2lde4leu5luv3lvw1m891m9A3mAB4mBF5mFG3mGH1mIJ1mJK4mKQ5mQR2mcd1mde4meu5muv2n9A1nAB3nBF5nFG4nGH1nJK1nKL3nLP5nPQ3nde3net5ntu3oAB2oBC4oCF5oFG4oGH2oKP1ode1oes5ost3pAB1pBC2pCD4pDF5pFG4pGH3pHI1pde1per5prs3qBC1qCD3qDG5qGI4qIJ3qJK1qde1qeq5qqr4qrs1rCD1rDF4rFI5rIJ4rJK3rKL2rLQ1rde1rep5rpq4rqr2sDE2sEF3sFH4sHP5sPQ4sQR1sde1seo5sop4spq1tFG1tGH3tHP5tPQ4tQR1tde1ten5tno3top1uFG1uGH2uHI4uIP5uPQ4uQR1ude1uem5umn3vGI1vIJ2vJK4vKP5vPQ4vQR1vde2vek5vkl3vlm1wJK1wKL3wLN4wNP5wPQ4wde1wef4wfi5wij3wjk1xLM1xMN2xNO3xOP4xPQ2xde1xef3xfg4xgh3xhi2xij1yNQ1yeh1",
    GH_PAL
)

local TILE_BORDER_DC     = colU32(0, 195, 248, 220)   -- Neon Cyan (#00C3F8)
local TILE_BORDER_GH     = colU32(139, 61, 255, 220)  -- Electric Violet (#8B3DFF)
local TILE_COPIED_BORDER = colU32(87, 242, 135, 255)  -- Neon Emerald (#57F287)

local NEON_CYAN_U32      = colU32(0, 205, 252, 255)
local NEON_PURPLE_U32    = colU32(168, 48, 255, 255)
local GLOW_CYAN_BG_U32   = colU32(0, 185, 252, 42)
local GLOW_PURPLE_BG_U32 = colU32(138, 36, 255, 46)
local GLOW_DEEP_BG_U32   = colU32(4, 5, 12, 18)

local function getFGDrawList()
    if not ImGui then return nil end
    if type(ImGui.FG) == "table" or type(ImGui.FG) == "userdata" then
        return ImGui.FG
    end
    if type(ImGui.GetWindowDrawList) == "function" then
        local ok, dl = pcall(ImGui.GetWindowDrawList)
        if ok and dl then return dl end
    end
    return nil
end

local function getBGDrawList()
    if not ImGui then return nil end
    if type(ImGui.BG) == "table" or type(ImGui.BG) == "userdata" then
        return ImGui.BG
    end
    return nil
end

-- Garis gradien neon Cyan -> Ungu (statis) di bagian atas window + ambient glow halus
local function drawWindowNeonChrome()
    if not (ImGui and ImVec2 and ImGui.GetWindowPos and ImGui.GetWindowSize) then return end
    local okP, wp = pcall(ImGui.GetWindowPos)
    local okS, ws = pcall(ImGui.GetWindowSize)
    if not (okP and okS and wp and ws) then return end
    local okC, wx, wy, ww, wh = pcall(function() return wp.x, wp.y, ws.x, ws.y end)
    if not (okC and type(wx) == "number" and type(ww) == "number" and ww > 40 and wh > 40) then return end

    local bg = getBGDrawList()
    if bg and bg.AddRectFilledMultiColor then
        pcall(function()
            bg:AddRectFilledMultiColor(
                ImVec2(wx - 2, wy - 2),
                ImVec2(wx + ww + 2, wy + wh + 2),
                GLOW_CYAN_BG_U32, GLOW_PURPLE_BG_U32, GLOW_DEEP_BG_U32, GLOW_DEEP_BG_U32
            )
        end)
    end

    local fg = getFGDrawList()
    if fg then
        local drawn = false
        if fg.AddRectFilledMultiColor then
            drawn = pcall(function()
                fg:AddRectFilledMultiColor(
                    ImVec2(wx + 2, wy),
                    ImVec2(wx + ww - 2, wy + 2.5),
                    NEON_CYAN_U32, NEON_PURPLE_U32, NEON_PURPLE_U32, NEON_CYAN_U32
                )
            end)
        end
        if not drawn and fg.AddRectFilled then
            pcall(function()
                fg:AddRectFilled(ImVec2(wx + 2, wy), ImVec2(wx + ww - 2, wy + 2.5), NEON_CYAN_U32)
            end)
        end
    end
end

local function getLastItemRect()
    if not (ImGui and ImGui.GetItemRectMin and ImGui.GetItemRectMax) then return nil end
    local ok1, p1 = pcall(ImGui.GetItemRectMin)
    local ok2, p2 = pcall(ImGui.GetItemRectMax)
    if not (ok1 and ok2 and p1 and p2) then return nil end
    local okC, x1, y1, x2, y2 = pcall(function() return p1.x, p1.y, p2.x, p2.y end)
    if not (okC and type(x1) == "number" and type(x2) == "number" and x2 > x1 and y2 > y1) then return nil end
    return x1, y1, x2, y2
end

local function drawRasterTileOnLastItem(rasterRuns, bgCol, borderCol)
    local dl = getFGDrawList()
    if not dl or not ImVec2 then return false, "DrawList FG tidak tersedia" end
    local x1, y1, x2, y2 = getLastItemRect()
    if not x1 then return false, "GetItemRect gagal" end

    local cardW = x2 - x1
    local cardH = y2 - y1
    local topH  = cardH * 0.74
    local boxSz = math.max(52, math.min(cardW * 0.56, topH * 0.88))
    local px    = boxSz / 64.0
    local ox    = (x1 + x2 - boxSz) * 0.5
    local oy    = y1 + (topH - boxSz) * 0.5

    local function drawAll(withRound)
        if withRound then
            dl:AddRectFilled(ImVec2(ox - 1, oy - 1), ImVec2(ox + boxSz + 1, oy + boxSz + 1), borderCol, 0)
            dl:AddRectFilled(ImVec2(ox, oy), ImVec2(ox + boxSz, oy + boxSz), bgCol, 0)
            for i = 1, #rasterRuns do
                local r = rasterRuns[i]
                local ay = oy + r[1] * px
                local by = oy + (r[1] + 1) * px + 0.55
                dl:AddRectFilled(ImVec2(ox + r[2] * px, ay), ImVec2(ox + r[3] * px, by), r[4], 0)
            end
        else
            dl:AddRectFilled(ImVec2(ox - 1, oy - 1), ImVec2(ox + boxSz + 1, oy + boxSz + 1), borderCol)
            dl:AddRectFilled(ImVec2(ox, oy), ImVec2(ox + boxSz, oy + boxSz), bgCol)
            for i = 1, #rasterRuns do
                local r = rasterRuns[i]
                local ay = oy + r[1] * px
                local by = oy + (r[1] + 1) * px + 0.55
                dl:AddRectFilled(ImVec2(ox + r[2] * px, ay), ImVec2(ox + r[3] * px, by), r[4])
            end
        end
    end

    local ok, err = pcall(drawAll, false)
    if not ok then
        ok, err = pcall(drawAll, true)
    end
    return ok, err
end

local function isAnyBotActive()
    if not HUB then return false end
    for _, k in ipairs({ "plant", "dirt_farm", "build_soil", "buy_pack" }) do
        local m = HUB[k]
        if m and m.STATE and (m.STATE.enabled or m.STATE.running) then return true end
    end
    return false
end

local function safeSpacing()
    if ImGui and ImGui.Spacing then pcall(ImGui.Spacing) end
end

local function centeredText(txt, areaW, col)
    local s = tostring(txt or "")
    if ImGui and ImGui.GetCursorPosX and ImGui.SetCursorPosX then
        local okX, curX = pcall(ImGui.GetCursorPosX)
        local tw = #s * 7.5
        if ImGui.CalcTextSize then
            local okS, sz = pcall(ImGui.CalcTextSize, s)
            if okS and sz then
                local okW, w = pcall(function() return sz.x end)
                if okW and type(w) == "number" and w > 0 then tw = w end
            end
        end
        if okX and type(curX) == "number" and type(areaW) == "number" and areaW > tw then
            pcall(ImGui.SetCursorPosX, curX + (areaW - tw) * 0.5)
        end
    end
    coloredText(col, s)
end

local function centeredBtn(lbl, btnW, areaW, isAccent)
    if ImGui and ImGui.GetCursorPosX and ImGui.SetCursorPosX then
        local okX, curX = pcall(ImGui.GetCursorPosX)
        if okX and type(curX) == "number" and type(areaW) == "number" and areaW > btnW then
            pcall(ImGui.SetCursorPosX, curX + (areaW - btnW) * 0.5)
        end
    end
    return styledBtn(lbl, btnW, isAccent, false)
end

local function renderDashboardPanel()
    local availW = safeAvailX()
    local tNow   = nowSec()
    local P      = getBorenPal()

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

    -- 1. HEADER PROFESIONAL & STATIS (BOREN STORE — Cyan & Ice White)
    safeSpacing()
    centeredText("BOREN STORE", availW, P.textCyan)
    centeredText(
        string.format("Status: %s   |   World: %s   |   Gems: %d", anyRun and "AKTIF" or "STANDBY", curWorld, curGems),
        availW,
        anyRun and P.textActive or P.textMuted
    )
    if uiNotice ~= "" then
        centeredText(uiNotice, availW, P.textPurple)
    end
    safeSpacing()
    ImGui.Separator()
    safeSpacing()

    -- 2. KARTU LOGO DISCORD & GITHUB (64x64 Full-Color Anti-Aliased, Border Cyan & Violet)
    local cardW = math.max(150, math.floor(availW * 0.47))
    local dcCopied = (tNow < dcCopiedUntil)
    local ghCopied = (tNow < ghCopiedUntil)
    local dcLabel  = dcCopied and "Link Tersalin!" or "Discord Boren"
    local ghLabel  = ghCopied and "Link Tersalin!" or "GitHub Boren"

    if ImGui.BeginTable("BorenDashCards", 2) then
        ImGui.TableNextRow()
        ImGui.TableSetColumnIndex(0)
        local dcBtnText = rasterLogoOk
            and ("\n\n\n\n\n\n" .. dcLabel .. "\n##card_dc")
            or  ("\n\n  " .. dcLabel .. "  \n\n##card_dc")
        if fullBtn(dcBtnText, cardW) then
            copyLinkToClipboard("Link Discord Boren", getHubLink("discord"))
            dcCopiedUntil = tNow + 2.0
        end
        if rasterLogoOk then
            local okV = drawRasterTileOnLastItem(DC_RASTER, DC_BG_COL, dcCopied and TILE_COPIED_BORDER or TILE_BORDER_DC)
            if not okV then rasterLogoOk = false end
        end

        ImGui.TableSetColumnIndex(1)
        local ghBtnText = rasterLogoOk
            and ("\n\n\n\n\n\n" .. ghLabel .. "\n##card_gh")
            or  ("\n\n  " .. ghLabel .. "  \n\n##card_gh")
        if fullBtn(ghBtnText, cardW) then
            copyLinkToClipboard("Link GitHub Boren", getHubLink("github_repo"))
            ghCopiedUntil = tNow + 2.0
        end
        if rasterLogoOk then
            local okV = drawRasterTileOnLastItem(GH_RASTER, GH_BG_COL, ghCopied and TILE_COPIED_BORDER or TILE_BORDER_GH)
            if not okV then rasterLogoOk = false end
        end
        ImGui.EndTable()
    end

    safeSpacing()
    centeredText("Klik kartu logo di atas untuk menyalin link", availW, P.textMuted)
    safeSpacing()
    ImGui.Separator()
    safeSpacing()

    -- 3. TOMBOL REFRESH / UPDATE SCRIPT (Rapi, Aksen BOREN & Terpusat)
    local rlBtnW = math.min(240, math.max(170, math.floor(availW * 0.48)))
    if centeredBtn(isReloading and "Updating...##dash_rl" or "Refresh / Update Script##dash_rl", rlBtnW, availW, true) then
        if not isReloading then
            triggerHotReloadAll()
        end
    end
    centeredText(updStatus, availW, P.textMuted)
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
    local P = getBorenPal()
    centeredText("MENU", btnW, P.textCyan)
    safeSpacing()
    if styledBtn("Dashboard", btnW, activeFeature == "dashboard", false) then
        activeFeature = "dashboard"
    end
    if styledBtn("Plant", btnW, activeFeature == "plant", false) then
        activeFeature = "plant"
    end
    if styledBtn("Dirt Farm", btnW, activeFeature == "dirt_farm", false) then
        activeFeature = "dirt_farm"
    end
    if styledBtn("Build Soil", btnW, activeFeature == "build_soil", false) then
        activeFeature = "build_soil"
    end
    if styledBtn("Buy Pack", btnW, activeFeature == "buy_pack", false) then
        activeFeature = "buy_pack"
    end

    ImGui.Text("")
    if styledBtn("Hide UI", btnW, false, true) then
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
        if styledBtn(" List World ", nil, activePlantSub == "worlds", false) then
            activePlantSub = "worlds"
        end
        ImGui.SameLine()
        if styledBtn(" List Storage ", nil, activePlantSub == "storage", false) then
            activePlantSub = "storage"
        end
        ImGui.SameLine()
        if styledBtn(" Settings ", nil, activePlantSub == "settings", false) then
            activePlantSub = "settings"
        end
        ImGui.SameLine()
        if styledBtn(" Logs ", nil, activePlantSub == "logs", false) then
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

    local cCnt, vCnt = pushBorenTheme()

    if not windowOpen then
        if ImGui.SetNextWindowPos and ImVec2 then
            pcall(ImGui.SetNextWindowPos, ImVec2(24, 150), (ImGui.Cond and ImGui.Cond.Once) or 2)
        end
        if ImGui.SetNextWindowSize and ImVec2 then
            pcall(ImGui.SetNextWindowSize, ImVec2(300, 155), (ImGui.Cond and ImGui.Cond.Always) or 1)
        end
        if ImGui.Begin("BOREN STORE##boren_mini") then
            drawWindowNeonChrome()
            if styledBtn("  Buka BOREN STORE  ", nil, true, false) then
                windowOpen = true
            end
        end
        ImGui.End()
        popBorenTheme(cCnt, vCnt)
        return
    end

    if ImGui.SetNextWindowSize and ImVec2 then
        pcall(ImGui.SetNextWindowSize, ImVec2(780, 470), (ImGui.Cond and ImGui.Cond.Once) or 2)
    end

    if ImGui.Begin("BOREN STORE##boren_main") then
        drawWindowNeonChrome()
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
    popBorenTheme(cCnt, vCnt)
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
                    pcall(LogToConsole, "`e[BOREN STORE] `wUI " .. (windowOpen and "`2DITAMPILKAN" or "`4DISEMBUNYIKAN"))
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
