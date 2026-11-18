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

-- Kompatibel semua versi binding ImGui.InputText Android (3-arg / 2-arg / null-byte strip / Android IME)
local function cleanInputStr(v)
    return tostring(v or ""):gsub("%z.*", "")
end

local function safeInputText(id, curVal, maxLen)
    local s = cleanInputStr(curVal)
    local ok, r1, r2 = pcall(ImGui.InputText, id, s, maxLen or 256)
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
-- TEMA RESMI BOREN STORE (Solid Hitam Pekat + Neon Tebal Cyan #00D8FF & Ungu #B026FF)
-- ============================================================================
local vec4Ok = nil
local pushColMode = nil -- auto-deteksi sekali di frame pertama: "u32" | "rgba4" | "vec4" | "none"
local borenPal = nil

local function packU32(r, g, b, a)
    return math.floor(r) + math.floor(g) * 256 + math.floor(b) * 65536 + math.floor(a or 255) * 16777216
end

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

-- Buat entry warna lengkap { r, g, b, a, u32, v4 } (0..255 + 0..1)
local function mkCol(r, g, b, a)
    a = a or 255
    return {
        r = r / 255.0, g = g / 255.0, b = b / 255.0, a = a / 255.0,
        u32 = packU32(r, g, b, a),
        v4  = v4(r / 255.0, g / 255.0, b / 255.0, a / 255.0),
    }
end

local function detectPushColorMode()
    if pushColMode ~= nil then return pushColMode end
    if not (ImGui and ImGui.PushStyleColor and ImGui.PopStyleColor and ImGui.Col) then
        pushColMode = "none"
        return pushColMode
    end
    local slot = ImGui.Col.PlotLines or ImGui.Col.NavWindowingHighlight or 38
    if type(ImGui.GetStyleColorVec4) ~= "function" then
        pushColMode = "none"
        return pushColMode
    end

    local function matchesTestColor()
        local okG, cv = pcall(ImGui.GetStyleColorVec4, slot)
        if not (okG and cv) then return false end
        local okR, x, y, z, w = pcall(function() return cv.x, cv.y, cv.z, cv.w end)
        if not (okR and type(x) == "number" and type(w) == "number") then return false end
        return (x > 0.80 and y < 0.25 and z > 0.70 and w > 0.85)
    end

    -- 1. Coba format packed ImU32 (paling umum di binding Android)
    local ok1 = pcall(ImGui.PushStyleColor, slot, packU32(250, 20, 220, 255))
    if ok1 then
        local hit = matchesTestColor()
        pcall(ImGui.PopStyleColor, 1)
        if hit then pushColMode = "u32"; return pushColMode end
    end

    -- 2. Coba format 4 float (r, g, b, a)
    local ok2 = pcall(ImGui.PushStyleColor, slot, 0.98, 0.08, 0.86, 1.0)
    if ok2 then
        local hit = matchesTestColor()
        pcall(ImGui.PopStyleColor, 1)
        if hit then pushColMode = "rgba4"; return pushColMode end
    end

    -- 3. Coba format ImVec4(r, g, b, a)
    local tv4 = v4(0.98, 0.08, 0.86, 1.0)
    if tv4 then
        local ok3 = pcall(ImGui.PushStyleColor, slot, tv4)
        if ok3 then
            local hit = matchesTestColor()
            pcall(ImGui.PopStyleColor, 1)
            if hit then pushColMode = "vec4"; return pushColMode end
        end
    end

    pushColMode = "none"
    return pushColMode
end

local function pushOneColor(idx, c)
    if idx == nil or c == nil then return false end
    local mode = detectPushColorMode()
    if mode == "u32" then
        return pcall(ImGui.PushStyleColor, idx, c.u32)
    elseif mode == "rgba4" then
        return pcall(ImGui.PushStyleColor, idx, c.r, c.g, c.b, c.a)
    elseif mode == "vec4" and c.v4 then
        return pcall(ImGui.PushStyleColor, idx, c.v4)
    end
    return false
end

local function getBorenPal()
    if borenPal then return borenPal end
    borenPal = {
        -- Solid Hitam Pekat (100% TEBAL, Alpha 255 = BUKAN Transparan)
        windowBg        = mkCol(7,   9,  16, 255),
        childBg         = mkCol(10, 13,  24, 255),
        popupBg         = mkCol(10, 13,  24, 255),
        border          = mkCol(0, 212, 255, 255), -- Neon Cyan Tebal
        borderShadow    = mkCol(140, 38, 255, 180),

        -- Title Bar Hitam-Indigo Pekat
        titleBg         = mkCol(11, 14,  30, 255),
        titleBgActive   = mkCol(24, 16,  68, 255),
        titleBgColl     = mkCol(11, 14,  30, 255),

        -- Input & Frame Solid Gelap
        frameBg         = mkCol(16, 22,  42, 255),
        frameBgHover    = mkCol(22, 52,  92, 255),
        frameBgActive   = mkCol(54, 26, 126, 255),

        -- Tombol Solid Hitam-Navy -> Hover Cyan -> Klik Ungu Neon
        btn             = mkCol(18, 24,  44, 255),
        btnHover        = mkCol(10, 118, 192, 255),
        btnActive       = mkCol(115, 36, 245, 255),

        -- Tombol Aktif / Highlight (Ungu Neon Tebal + Border Cyan)
        accentBtn       = mkCol(98,  30, 232, 255),
        accentBtnHover  = mkCol(128, 52, 255, 255),
        accentBtnActive = mkCol(0,  176, 248, 255),
        accentBorder    = mkCol(0,  218, 255, 255),

        -- Tombol Hide UI Solid Gelap
        mutedBtn        = mkCol(14, 18,  34, 255),
        mutedBtnHover   = mkCol(46, 24,  78, 255),

        -- Tombol Toggle ON/OFF Wajib Hitam + Neon (ON = Hitam + Neon Cyan, OFF = Hitam + Neon Ungu)
        onBtn           = mkCol(8,   22,  34, 255),
        onBtnHover      = mkCol(14,  42,  64, 255),
        onBtnActive     = mkCol(6,   54,  84, 255),
        onBorder        = mkCol(0,  228, 255, 255),
        onText          = mkCol(0,  238, 255, 255),

        offBtn          = mkCol(9,   11,  20, 255),
        offBtnHover     = mkCol(24,  18,  48, 255),
        offBtnActive    = mkCol(38,  22,  76, 255),
        offBorder       = mkCol(162, 56, 255, 255),
        offText         = mkCol(214, 196, 255, 255),

        -- Header, Tabel, Separator, Scrollbar (Solid & Neon)
        header          = mkCol(28, 36,  86, 255),
        headerHover     = mkCol(14, 112, 188, 255),
        headerActive    = mkCol(104, 38, 238, 255),
        separator       = mkCol(0,  204, 255, 220),
        checkMark       = mkCol(0,  220, 255, 255),
        sliderGrab      = mkCol(0,  205, 252, 255),
        sliderGrabAct   = mkCol(168, 52, 255, 255),
        scrollBg        = mkCol(8,  10,  20, 255),
        scrollGrab      = mkCol(36, 68, 138, 255),
        scrollGrabHov   = mkCol(0, 175, 245, 255),
        scrollGrabAct   = mkCol(138, 44, 255, 255),
        tableHeader     = mkCol(24, 22,  66, 255),
        tableRow        = mkCol(11, 14,  28, 255),
        tableRowAlt     = mkCol(16, 20,  38, 255),
        tableBorderS    = mkCol(0,  185, 245, 220),
        tableBorderL    = mkCol(48, 58, 122, 200),

        -- Typography (ImVec4 untuk TextColored + mkCol untuk Col.Text)
        textCol         = mkCol(240, 248, 255, 255),
        textMutedCol    = mkCol(150, 178, 214, 255),
        textCyan        = v4(0.000, 0.855, 1.000, 1.00),
        textPurple      = v4(0.765, 0.450, 1.000, 1.00),
        textActive      = v4(0.240, 0.960, 0.660, 1.00),
        textMuted       = v4(0.620, 0.735, 0.875, 1.00),
    }
    return borenPal
end

local function pushBorenTheme()
    local cCnt, vCnt = 0, 0
    if not ImGui then return 0, 0 end
    local C = ImGui.Col
    local V = ImGui.StyleVar
    local P = getBorenPal()

    if detectPushColorMode() ~= "none" and C then
        local function pc(idx, col)
            if pushOneColor(idx, col) then cCnt = cCnt + 1 end
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
        pc(C.Text,                 P.textCol)
        pc(C.TextDisabled,         P.textMutedCol)
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
        pv(V.WindowBorderSize,  2.0)
        pv(V.FrameBorderSize,   1.5)
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
    if (isAccent or isMuted) and detectPushColorMode() ~= "none" and ImGui and ImGui.Col then
        local C = ImGui.Col
        local P = getBorenPal()
        local function pc(idx, col)
            if pushOneColor(idx, col) then pushed = pushed + 1 end
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
    local clicked = false
    if width and width > 10 then
        clicked = fullBtn(label, width)
    else
        local ok, res = pcall(ImGui.Button, label)
        clicked = ok and (res == true)
    end
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

-- Spasi vertikal konsisten antar form/bagian agar tidak dempet
local function uiGap(px)
    local h = tonumber(px) or 6
    if ImGui and ImGui.Dummy and ImVec2 then
        if pcall(ImGui.Dummy, ImVec2(0, h)) then return end
    end
    if ImGui and ImGui.Spacing then pcall(ImGui.Spacing) end
end

-- Judul bagian berwarna Cyan + jarak rapi
local function uiSection(title, skipTopSep)
    if not skipTopSep then
        uiGap(6)
        if ImGui and ImGui.Separator then pcall(ImGui.Separator) end
    end
    uiGap(4)
    if title and title ~= "" then
        coloredText(getBorenPal().textCyan, title)
        uiGap(3)
    end
end

-- Kotak Toggle ON/OFF: Wajib Hitam + Neon, lebar seragam 95px (sama dengan kotak input teks/angka)
local function toggleBtn(isOn, id, onLabel, offLabel)
    local pushed = 0
    if detectPushColorMode() ~= "none" and ImGui and ImGui.Col then
        local C = ImGui.Col
        local P = getBorenPal()
        local function pc(idx, col)
            if pushOneColor(idx, col) then pushed = pushed + 1 end
        end
        if isOn then
            pc(C.Button,        P.onBtn)
            pc(C.ButtonHovered, P.onBtnHover)
            pc(C.ButtonActive,  P.onBtnActive)
            pc(C.Border,        P.onBorder)
            pc(C.Text,          P.onText)
        else
            pc(C.Button,        P.offBtn)
            pc(C.ButtonHovered, P.offBtnHover)
            pc(C.ButtonActive,  P.offBtnActive)
            pc(C.Border,        P.offBorder)
            pc(C.Text,          P.offText)
        end
    end
    local txt = isOn and (onLabel or "ON") or (offLabel or "OFF")
    local btnW = 95
    if #txt > 4 then
        local tw = #txt * 9
        if ImGui and ImGui.CalcTextSize then
            local okS, sz = pcall(ImGui.CalcTextSize, txt)
            if okS and sz then
                local okW, w = pcall(function() return sz.x end)
                if okW and type(w) == "number" and w > 0 then tw = w end
            end
        end
        btnW = math.max(95, math.floor(tw + 26))
    end
    local lbl = txt .. "##" .. tostring(id or "tg")
    local clicked = fullBtn(lbl, btnW)
    if pushed > 0 and ImGui and ImGui.PopStyleColor then
        pcall(ImGui.PopStyleColor, pushed)
    end
    return clicked
end

-- Kotak Status Bot ON/OFF (seragam 95px Hitam + Neon, klik untuk ganti ON / OFF)
local function enableBtn(isOn, id, onLabel, offLabel)
    return toggleBtn(isOn, id, onLabel or "ON", offLabel or "OFF")
end

-- Tombol Sub-Tab Aktif (Aksen Ungu Neon + Border Cyan)
local function tabBtn(label, isActive)
    return styledBtn(" " .. tostring(label) .. " ", nil, isActive == true, false)
end

-- Baca clipboard HP menjadi daftar baris bersih (non-empty) untuk Smart Paste
local function readClipboardLines()
    local clip = ""
    if ImGui and ImGui.GetClipboardText then
        local okC, resC = pcall(ImGui.GetClipboardText)
        if okC and type(resC) == "string" then clip = resC end
    end
    local lines = {}
    for line in clip:gmatch("[^\r\n]+") do
        local s = line:gsub("^%s+", ""):gsub("%s+$", "")
        if s ~= "" then lines[#lines + 1] = s end
    end
    return lines
end

-- Grid 1 baris tombol aksi simetris sejajar (misal 4 kolom: + Tambah | World Ini | Paste | Hapus)
local function renderActionBar(tableId, availW, buttons)
    local cols = #buttons
    if cols < 1 then return nil end
    local btnW = math.max(76, math.floor((availW - (cols * 8)) / cols))
    local clickedIdx = nil
    if ImGui.BeginTable(tableId, cols) then
        ImGui.TableNextRow()
        for i = 1, cols do
            ImGui.TableSetColumnIndex(i - 1)
            local b = buttons[i]
            local clicked = false
            if b.style == "accent" then
                clicked = styledBtn(b.label, btnW, true, false)
            elseif b.style == "muted" then
                clicked = styledBtn(b.label, btnW, false, true)
            else
                clicked = fullBtn(b.label, btnW)
            end
            if clicked then clickedIdx = i end
        end
        ImGui.EndTable()
    end
    return clickedIdx
end

-- ============================================================================
-- NATIVE ANDROID DIALOG INPUT (100% BEBAS BUG KEYBOARD / CONSOLE IMGUI HP!)
-- ============================================================================
local activeNativeDialogs = {} -- [dialogId] = callback(fieldsTable)

local function sanitizeDialogVal(s)
    return tostring(s or ""):gsub("[\r\n|]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function openNativeInputDialog(dialogId, title, fields, submitLabel, onSubmit)
    activeNativeDialogs[dialogId] = onSubmit
    local lines = {
        "set_default_color|`o",
        "add_label_with_icon|big|`cBOREN STORE - " .. sanitizeDialogVal(title) .. "|left|3802|",
        "add_spacer|small|",
    }
    for _, f in ipairs(fields or {}) do
        local fid = tostring(f.id or "f")
        local flb = sanitizeDialogVal(f.label or fid)
        local fdv = sanitizeDialogVal(f.default or "")
        local fln = tonumber(f.maxLen) or 48
        lines[#lines + 1] = string.format("add_text_input|%s|%s:|%s|%d|", fid, flb, fdv, fln)
    end
    lines[#lines + 1] = "add_spacer|small|"
    lines[#lines + 1] = "add_smalltext|`7Tips: Ketik langsung di keyboard HP lalu tekan tombol simpan di bawah.|"
    lines[#lines + 1] = "end_dialog|" .. dialogId .. "|Batal|" .. sanitizeDialogVal(submitLabel or "Simpan") .. "|"
    local dText = table.concat(lines, "\n")

    -- Sembunyikan ImGui sebentar agar dialog native HP tidak ketutupan, nanti otomatis buka lagi saat submit/batal
    windowOpen = false

    local function sendNow()
        if growtopia and growtopia.sendDialog then
            pcall(growtopia.sendDialog, dText)
        elseif sendVariant then
            pcall(sendVariant, { v1 = "OnDialogRequest", v2 = dText })
        end
    end
    if runCoroutine then
        pcall(runCoroutine, sendNow)
    else
        sendNow()
    end
end

local showKetikBtn = false -- Sembunyikan tombol "Ketik (Keyboard HP)" di UI (fungsi tetap aktif; ketik /ketik di chat jika ingin munculkan)

local function uiSectionWithKetik(title, btnId, onKetikClick, skipTopSep)
    if not skipTopSep then
        uiGap(6)
        if ImGui and ImGui.Separator then pcall(ImGui.Separator) end
    end
    uiGap(4)
    coloredText(getBorenPal().textCyan, title)
    if showKetikBtn and onKetikClick then
        ImGui.SameLine()
        ImGui.Text("  ")
        ImGui.SameLine()
        if styledBtn(" Ketik (Keyboard HP) ##" .. tostring(btnId or "ktk"), nil, true, false) then
            onKetikClick()
        end
    end
    uiGap(3)
end

local UI_KIT = {
    gap                = uiGap,
    section            = uiSection,
    sectionWithKetik   = uiSectionWithKetik,
    toggleBtn          = toggleBtn,
    enableBtn          = enableBtn,
    tabBtn             = tabBtn,
    coloredText        = coloredText,
    getPal             = getBorenPal,
    readClipboardLines = readClipboardLines,
    renderActionBar    = renderActionBar,
    openInputDialog    = openNativeInputDialog,
}

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
    local P = getBorenPal()

    -- 1. KONTROL UTAMA BOT
    uiSection("Kontrol Auto Plant", true)
    ImGui.Text("Status Bot  :")
    ImGui.SameLine()
    if enableBtn(E.STATE.enabled, "en") then
        if E.STATE.enabled then E.stop() else E.start() end
    end

    ImGui.SameLine()
    ImGui.Text("    Loop  :")
    ImGui.SameLine()
    if toggleBtn(E.CFG.loop_enabled, "lp") then
        E.CFG.loop_enabled = not E.CFG.loop_enabled
        E.saveData()
    end

    ImGui.SameLine()
    if autoBtn(" Remove Inaccessible ") then
        local removed = E.removeInaccessible()
        setNotice("Dihapus " .. tostring(removed) .. " world inaccessible.")
    end
    ImGui.SameLine()
    if autoBtn(" Reset ") then
        E.resetAllStatus()
        setNotice("Semua status di-reset ke Ready.")
    end

    uiGap(4)
    local storages = E.getStorageList and E.getStorageList() or {}
    coloredText(E.STATE.enabled and P.textActive or P.textMuted,
        string.format("Status: %s   |   Storage: %d   |   World: %d",
            tostring(E.STATE.status_text or "Idle"), #storages, #E.STATE.rows))
    if uiNotice ~= "" then
        coloredText(P.textPurple, "Info: " .. uiNotice)
    end

    -- 2. DAFTAR WORLD
    uiSection("Daftar World (" .. tostring(#E.STATE.rows) .. ")")

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

    -- 3. FORM TAMBAH WORLD
    uiSectionWithKetik("Tambah World Baru", "pl_ktk_w", function()
        local wPre, dPre = tostring(addWorldBuf or ""):gsub("|", ":"):match("^([^:]+):(.*)$")
        if not wPre then wPre = tostring(addWorldBuf or ""); dPre = "" end
        openNativeInputDialog("boren_in_plant_w", "Tambah World Plant", {
            { id = "f_world",  label = "Nama World", default = wPre,         maxLen = 32 },
            { id = "f_door",   label = "Door ID",    default = dPre,         maxLen = 32 },
            { id = "f_seed",   label = "Seed ID",    default = addSeedBuf,   maxLen = 12 },
            { id = "f_splice", label = "Splice ID",  default = addSpliceBuf, maxLen = 12 },
        }, "Tambah & Simpan", function(vals)
            local wn = tostring(vals.f_world or ""):gsub("^%s+", ""):gsub("%s+$", ""):upper()
            local dn = tostring(vals.f_door or ""):gsub("^%s+", ""):gsub("%s+$", ""):upper()
            local sd = math.floor(tonumber(vals.f_seed) or 4585)
            local sp = math.floor(tonumber(vals.f_splice) or 0)
            if sd <= 0 then sd = 4585 end
            if sp < 0 then sp = 0 end
            addSeedBuf = tostring(sd)
            addSpliceBuf = tostring(sp)
            if wn ~= "" then
                local parsed = { name = wn, door = dn, seed_id = sd, splice_id = sp, status = "Ready" }
                table.insert(E.STATE.rows, parsed)
                addWorldBuf = ""
                E.saveData()
                logUI(E, "[+] World ditambah: " .. E.formatRowLine(parsed))
                setNotice("Tersimpan: " .. parsed.name .. " (Seed " .. tostring(sd) .. ", Splice " .. tostring(sp) .. ")")
            end
        end)
    end)
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
    uiGap(4)

    local act = renderActionBar("BorenPlantActs", availW, {
        { label = "+ Tambah##pl_add", style = "accent" },
        { label = "World Ini##pl_cur" },
        { label = "Paste##pl_pst" },
        { label = "Hapus##pl_del",    style = "muted" },
    })

    if act == 1 then
        local rawW = tostring(addWorldBuf or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local parsed = nil
        if rawW ~= "" then
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
            setNotice("Tersimpan: " .. parsed.name .. " (Seed " .. tostring(parsed.seed_id) .. ", Splice " .. tostring(parsed.splice_id) .. ")")
        else
            setNotice("Isi World:DoorID dulu!")
        end

    elseif act == 2 then
        local curW = ""
        if getCurrentWorldName then
            local okW, wn = pcall(getCurrentWorldName)
            if okW and type(wn) == "string" then curW = wn:upper() end
        end
        if curW ~= "" and curW ~= "EXIT" then
            addWorldBuf = curW .. ":"
            setNotice("Terisi " .. curW .. ": (tambahkan Door ID lalu klik + Tambah)")
        else
            setNotice("Masuk ke world terlebih dahulu!")
        end

    elseif act == 3 then
        -- Smart Paste: 1 baris -> isi form (+ pisah Seed/Splice); banyak baris -> langsung tambah & Auto-Save!
        local lines = readClipboardLines()
        if #lines == 0 then
            setNotice("Clipboard kosong!")
        elseif #lines == 1 then
            local norm = lines[1]:gsub("|", ":")
            local colons = 0
            for _ in norm:gmatch(":") do colons = colons + 1 end
            if colons >= 2 then
                local p = E.parseRowLine(norm)
                if p then
                    addWorldBuf  = p.door ~= "" and (p.name .. ":" .. p.door) or p.name
                    addSeedBuf   = tostring(p.seed_id)
                    addSpliceBuf = tostring(p.splice_id)
                    setNotice("Paste ke form (" .. p.name .. "). Klik + Tambah.")
                else
                    addWorldBuf = lines[1]
                    setNotice("Paste ke kotak World:DoorID.")
                end
            else
                addWorldBuf = lines[1]
                setNotice("Paste ke form (" .. lines[1] .. "). Klik + Tambah.")
            end
        else
            local added = 0
            local defSd = math.floor(tonumber(addSeedBuf) or 4585)
            local defSp = math.floor(tonumber(addSpliceBuf) or 0)
            if defSd <= 0 then defSd = 4585 end
            for _, ln in ipairs(lines) do
                local norm = ln:gsub("|", ":")
                local colons = 0
                for _ in norm:gmatch(":") do colons = colons + 1 end
                local p = nil
                if colons >= 2 then
                    p = E.parseRowLine(norm)
                else
                    local wPart, dPart = norm:match("^([^:]+):(.*)$")
                    local wn = (wPart or norm):gsub("^%s+", ""):gsub("%s+$", ""):upper()
                    local di = (dPart or ""):gsub("^%s+", ""):gsub("%s+$", ""):upper()
                    if wn ~= "" then
                        p = { name = wn, door = di, seed_id = defSd, splice_id = defSp, status = "Ready" }
                    end
                end
                if p then
                    table.insert(E.STATE.rows, p)
                    added = added + 1
                end
            end
            if added > 0 then
                E.saveData()
                logUI(E, "[Smart Paste] +" .. tostring(added) .. " world ditambahkan.")
                setNotice("Smart Paste: +" .. tostring(added) .. " world (otomatis tersimpan)!")
            else
                setNotice("Format clipboard tidak valid.")
            end
        end

    elseif act == 4 then
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
end

-- ============================================================================
-- PLANT SUB-TAB 2: LIST STORAGE (MANAJEMEN WORLD STORAGE SEED)
-- ============================================================================
local function renderPlantStorageSub()
    local E = HUB.plant
    if not E then return end

    local availW = safeAvailX()
    local storages = E.getStorageList and E.getStorageList() or {}

    uiSection("Daftar World Storage Seed (" .. tostring(#storages) .. ")", true)
    if uiNotice ~= "" then
        coloredText(getBorenPal().textPurple, "Info: " .. uiNotice)
        uiGap(3)
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

    uiSectionWithKetik("Tambah Storage Baru", "pl_ktk_st", function()
        openNativeInputDialog("boren_in_plant_st", "Tambah Storage Seed", {
            { id = "f_world", label = "World Storage", default = addStorageBuf,     maxLen = 32 },
            { id = "f_door",  label = "Door ID",       default = addStorageDoorBuf, maxLen = 32 },
        }, "Tambah & Simpan", function(vals)
            local wn = tostring(vals.f_world or ""):gsub("^%s+", ""):gsub("%s+$", ""):upper()
            local dn = tostring(vals.f_door or ""):gsub("^%s+", ""):gsub("%s+$", ""):upper()
            if wn ~= "" then
                local stList = E.getStorageList and E.getStorageList() or {}
                table.insert(stList, { name = wn, door = dn })
                E.setStorageList(stList)
                addStorageBuf = ""; addStorageDoorBuf = ""
                logUI(E, "[Storage +] " .. wn .. (dn ~= "" and (":" .. dn) or ""))
                setNotice("Tersimpan storage: " .. wn)
            end
        end)
    end)
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
    uiGap(4)

    local actSt = renderActionBar("BorenPlantStActs", availW, {
        { label = "+ Tambah##plst_add", style = "accent" },
        { label = "World Ini##plst_cur" },
        { label = "Paste##plst_pst" },
        { label = "Hapus##plst_del",    style = "muted" },
    })

    if actSt == 1 then
        local wStr = tostring(addStorageBuf or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local dStr = tostring(addStorageDoorBuf or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local combined = (wStr:find(":", 1, true) or wStr:find("|", 1, true) or dStr == "") and wStr or (wStr .. ":" .. dStr)
        local parsed = E.parseStorageLine and E.parseStorageLine(combined)
        if parsed then
            table.insert(storages, parsed)
            E.setStorageList(storages)
            addStorageBuf = ""; addStorageDoorBuf = ""
            logUI(E, "[Storage +] " .. parsed.name .. (parsed.door ~= "" and (":" .. parsed.door) or ""))
            setNotice("Tersimpan storage: " .. parsed.name)
        else
            setNotice("Isi World Storage dulu!")
        end

    elseif actSt == 2 then
        local curW = ""
        if getCurrentWorldName then
            local okW, wn = pcall(getCurrentWorldName)
            if okW and type(wn) == "string" then curW = wn:upper() end
        end
        if curW ~= "" and curW ~= "EXIT" then
            addStorageBuf = curW
            setNotice("Terisi " .. curW .. " (isi Door ID jika ada lalu klik + Tambah)")
        else
            setNotice("Masuk ke world terlebih dahulu!")
        end

    elseif actSt == 3 then
        local lines = readClipboardLines()
        if #lines == 0 then
            setNotice("Clipboard kosong!")
        elseif #lines == 1 then
            local norm = lines[1]:gsub("|", ":")
            local wP, dP = norm:match("^([^:]+):(.*)$")
            if wP then
                addStorageBuf     = wP:gsub("^%s+", ""):gsub("%s+$", "")
                addStorageDoorBuf = (dP or ""):gsub("^%s+", ""):gsub("%s+$", "")
            else
                addStorageBuf = lines[1]
            end
            setNotice("Paste ke form storage. Klik + Tambah.")
        else
            local added = 0
            for _, ln in ipairs(lines) do
                local parsed = E.parseStorageLine and E.parseStorageLine(ln)
                if parsed then
                    table.insert(storages, parsed)
                    added = added + 1
                end
            end
            if added > 0 then
                E.setStorageList(storages)
                setNotice("Smart Paste: +" .. tostring(added) .. " storage (tersimpan)!")
            else
                setNotice("Format clipboard tidak valid.")
            end
        end

    elseif actSt == 4 then
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

    uiSection("Pengaturan Auto Plant", true)

    if ImGui.BeginTable("BorenPlantSetOpts", 2) then
        renderOptRow("Mode Tanam", function()
            local is3z = (E.CFG.plant_mode == "3zigzag")
            if autoBtn(is3z and " 3-Zigzag (Cepat) ##md" or " 1-by-1 (Presisi) ##md") then
                E.CFG.plant_mode = is3z and "1by1" or "3zigzag"
                E.saveData()
            end
        end)
        renderOptRow("ModFly (Terbang)", function()
            if toggleBtn(E.CFG.use_modfly, "mf") then
                E.CFG.use_modfly = not E.CFG.use_modfly
                E.saveData()
            end
        end)
        renderOptRow("Abaikan Gems", function()
            if toggleBtn(E.CFG.ignore_gems, "ig") then
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

    uiGap(6)
    ImGui.Separator()
    uiGap(4)
    coloredText(getBorenPal().textMuted, "Tip: Ketik /hub di chat game untuk sembunyikan / tampilkan jendela ini kapan saja.")
end

-- ============================================================================
-- PLANT SUB-TAB 4: LOGS
-- ============================================================================
local function renderPlantLogsSub()
    local logs = HUB.logs or {}
    uiGap(3)
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
    uiGap(4)
    ImGui.Separator()
    uiGap(4)
    if #logs == 0 then
        coloredText(getBorenPal().textMuted, "Belum ada log aktivitas.")
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
    raw_item_db   = "https://raw.githubusercontent.com/rendhi69/data-_id_item/main/item_database.txt",
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

local TILE_BORDER_DC     = colU32(0, 208, 255, 255)   -- Neon Cyan (#00D0FF)
local TILE_BORDER_GH     = colU32(158, 56, 255, 255)  -- Electric Violet (#9E38FF)
local TILE_COPIED_BORDER = colU32(87, 242, 135, 255)  -- Neon Emerald (#57F287)

local NEON_CYAN_U32      = colU32(0, 216, 255, 255)
local NEON_PURPLE_U32    = colU32(176, 38, 255, 255)
local SOLID_BLACK_BG_U32 = colU32(7, 9, 16, 255)      -- 100% Solid Hitam Pekat (Alpha 255)

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

-- Frame neon TEBAL (3px Cyan -> Ungu sekeliling 4 sisi) + latar HITAM PEKAT 100% solid (bukan transparan!)
local function drawWindowNeonChrome()
    if not (ImGui and ImVec2 and ImGui.GetWindowPos and ImGui.GetWindowSize) then return end
    local okP, wp = pcall(ImGui.GetWindowPos)
    local okS, ws = pcall(ImGui.GetWindowSize)
    if not (okP and okS and wp and ws) then return end
    local okC, wx, wy, ww, wh = pcall(function() return wp.x, wp.y, ws.x, ws.y end)
    if not (okC and type(wx) == "number" and type(ww) == "number" and ww > 40 and wh > 40) then return end

    local bg = getBGDrawList()
    if bg then
        local drewBorder = false
        if bg.AddRectFilledMultiColor then
            drewBorder = pcall(function()
                bg:AddRectFilledMultiColor(
                    ImVec2(wx - 3, wy - 3),
                    ImVec2(wx + ww + 3, wy + wh + 3),
                    NEON_CYAN_U32, NEON_PURPLE_U32, NEON_PURPLE_U32, NEON_CYAN_U32
                )
            end)
        end
        if bg.AddRectFilled then
            if not drewBorder then
                pcall(function()
                    bg:AddRectFilled(ImVec2(wx - 3, wy - 3), ImVec2(wx + ww + 3, wy + wh + 3), NEON_CYAN_U32)
                end)
            end
            -- Latar hitam pekat solid di dalam frame neon
            local okSolid = pcall(function()
                bg:AddRectFilled(ImVec2(wx, wy), ImVec2(wx + ww, wy + wh), SOLID_BLACK_BG_U32)
            end)
            if not okSolid then
                pcall(function()
                    bg:AddRectFilled(ImVec2(wx, wy), ImVec2(wx + ww, wy + wh), SOLID_BLACK_BG_U32, 0)
                end)
            end
        end
    end

    local fg = getFGDrawList()
    if fg then
        local drawn = false
        if fg.AddRectFilledMultiColor then
            drawn = pcall(function()
                fg:AddRectFilledMultiColor(
                    ImVec2(wx, wy),
                    ImVec2(wx + ww, wy + 3.5),
                    NEON_CYAN_U32, NEON_PURPLE_U32, NEON_PURPLE_U32, NEON_CYAN_U32
                )
            end)
        end
        if not drawn and fg.AddRectFilled then
            pcall(function()
                fg:AddRectFilled(ImVec2(wx, wy), ImVec2(wx + ww, wy + 3.5), NEON_CYAN_U32)
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

local FALLBACK_FEATURES = {
    { id = "dirt_farm",   label = "Dirt Farm",   order = 20, path = "imgui_hub/mod_dirt_farm.lua" },
    { id = "build_soil",  label = "Build Soil",  order = 30, path = "imgui_hub/mod_soil_builder.lua" },
    { id = "buy_pack",    label = "Buy Pack",    order = 40, path = "imgui_hub/mod_buy_pack.lua" },
    { id = "database_id", label = "Database ID", order = 50, path = "imgui_hub/mod_database_id.lua" },
}

local function getDynamicFeatures()
    if HUB and type(HUB.features) == "table" and #HUB.features > 0 then
        return HUB.features
    end
    return FALLBACK_FEATURES
end

local function isAnyBotActive()
    if not HUB then return false end
    if HUB.plant and HUB.plant.STATE and (HUB.plant.STATE.enabled or HUB.plant.STATE.running) then
        return true
    end
    for _, feat in ipairs(getDynamicFeatures()) do
        local m = feat.mod or HUB[feat.id]
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
    if uiNotice ~= "" and uiNotice ~= updStatus then
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

    -- 3. TOMBOL REFRESH / UPDATE SCRIPT (Rapi, Auto-Fit, Aksen BOREN & Terpusat)
    local rlDisplay = isReloading and "Updating..." or "Refresh / Update Script"
    local rlTextW = #rlDisplay * 10
    if ImGui and ImGui.CalcTextSize then
        local okS, sz = pcall(ImGui.CalcTextSize, rlDisplay)
        if okS and sz then
            local okW, w = pcall(function() return sz.x end)
            if okW and type(w) == "number" and w > 0 then rlTextW = w end
        end
    end
    local rlBtnW = math.min(math.max(220, availW - 24), math.max(280, math.floor(rlTextW + 56)))
    if centeredBtn(rlDisplay .. "##dash_rl", rlBtnW, availW, true) then
        if not isReloading then
            triggerHotReloadAll()
        end
    end
    safeSpacing()
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

local isPinned        = true    -- Default ON: kunci posisi jendela agar tidak bergeser saat disentuh
local pinnedX         = nil
local pinnedY         = nil
local lastWinX        = nil
local lastWinY        = nil
local needCenterPos   = true    -- Posisikan tepat di tengah layar saat pertama kali dimuat
local switchAnimStart = 0
local SWITCH_ANIM_DUR = 0.26

local function getCenteredWindowPos(winW, winH)
    local dispW, dispH = 1280, 540
    if ImGui and ImGui.GetMainViewport then
        local okV, vp = pcall(ImGui.GetMainViewport)
        if okV and vp then
            local okS, sw, sh = pcall(function() return vp.Size.x, vp.Size.y end)
            if okS and type(sw) == "number" and sw >= 400 and type(sh) == "number" and sh >= 300 then
                dispW, dispH = sw, sh
            end
        end
    elseif ImGui and ImGui.GetIO then
        local okI, ioObj = pcall(ImGui.GetIO)
        if okI and ioObj then
            local okS, sw, sh = pcall(function() return ioObj.DisplaySize.x, ioObj.DisplaySize.y end)
            if okS and type(sw) == "number" and sw >= 400 and type(sh) == "number" and sh >= 300 then
                dispW, dispH = sw, sh
            end
        end
    end
    local cx = math.max(12, math.floor((dispW - winW) * 0.5))
    local cy = math.max(12, math.floor((dispH - winH) * 0.5))
    return cx, cy
end

local function selectFeature(name)
    if activeFeature ~= name then
        activeFeature = name
        switchAnimStart = nowSec()
    end
end

local function getSwitchProgress()
    local elapsed = nowSec() - (switchAnimStart or 0)
    if elapsed < 0 or elapsed >= SWITCH_ANIM_DUR then return 1.0 end
    return elapsed / SWITCH_ANIM_DUR
end

-- Efek transisi halus saat perpindahan fitur (sapuan neon Cyan -> Ungu + kilau lembut 0.26 detik)
local function drawSwitchEffect(sideW)
    local p = getSwitchProgress()
    if p >= 1.0 then return end
    if not (ImGui and ImVec2 and ImGui.GetWindowPos and ImGui.GetWindowSize) then return end
    local fg = getFGDrawList()
    if not fg then return end

    local okP, wp = pcall(ImGui.GetWindowPos)
    local okS, ws = pcall(ImGui.GetWindowSize)
    if not (okP and okS and wp and ws) then return end
    local okC, wx, wy, ww, wh = pcall(function() return wp.x, wp.y, ws.x, ws.y end)
    if not (okC and type(wx) == "number" and ww > sideW + 40 and wh > 60) then return end

    local ease = 1.0 - (1.0 - p) * (1.0 - p) * (1.0 - p)
    local lineAlpha = math.max(0, math.min(255, math.floor((1.0 - p) * 245)))
    local glowAlpha = math.max(0, math.min(255, math.floor((1.0 - p) * 44)))

    local rx1 = wx + sideW + 4
    local rx2 = wx + ww - 4
    local ry1 = wy + 28
    local sweepX2 = rx1 + (rx2 - rx1) * ease

    local cCyan   = colU32(0, 224, 255, lineAlpha)
    local cPurple = colU32(176, 48, 255, lineAlpha)
    local gCyan   = colU32(0, 208, 255, glowAlpha)
    local gPurple = colU32(160, 44, 255, glowAlpha)
    local gZero   = colU32(7, 9, 16, 0)

    if fg.AddRectFilledMultiColor then
        pcall(function()
            -- Garis sapuan neon bergerak cepat melintasi bagian atas panel kanan
            fg:AddRectFilledMultiColor(
                ImVec2(rx1, ry1), ImVec2(sweepX2, ry1 + 3.0),
                cCyan, cPurple, cPurple, cCyan
            )
            -- Kilau vertikal lembut yang langsung memudar
            fg:AddRectFilledMultiColor(
                ImVec2(rx1, ry1 + 3.0), ImVec2(rx2, math.min(wy + wh - 4, ry1 + 42)),
                gCyan, gPurple, gZero, gZero
            )
        end)
    elseif fg.AddRectFilled then
        pcall(function()
            fg:AddRectFilled(ImVec2(rx1, ry1), ImVec2(sweepX2, ry1 + 3.0), cCyan)
        end)
    end
end

local function drawSidebarDivider(width)
    local w = math.max(60, math.floor(tonumber(width) or 110))
    if ImGui and ImGui.Dummy and ImVec2 then
        pcall(ImGui.Dummy, ImVec2(w, 2))
        local x1, y1, x2, y2 = getLastItemRect()
        local fg = getFGDrawList()
        if x1 and fg then
            local cy = (y1 + y2) * 0.5
            local drew = false
            if fg.AddRectFilledMultiColor then
                drew = pcall(function()
                    fg:AddRectFilledMultiColor(
                        ImVec2(x1, cy - 1), ImVec2(x2, cy + 1),
                        NEON_CYAN_U32, NEON_PURPLE_U32, NEON_PURPLE_U32, NEON_CYAN_U32
                    )
                end)
            end
            if not drew and fg.AddRectFilled then
                pcall(function()
                    fg:AddRectFilled(ImVec2(x1, cy - 1), ImVec2(x2, cy + 1), NEON_CYAN_U32)
                end)
            end
        end
    else
        uiGap(6)
    end
end

local function renderLeftFeatureSidebar(colW)
    local btnW = math.max(90, colW - 18)
    local P = getBorenPal()
    centeredText("MENU", btnW, P.textCyan)
    safeSpacing()
    if styledBtn("Dashboard", btnW, activeFeature == "dashboard", false) then
        selectFeature("dashboard")
    end
    if styledBtn("Plant", btnW, activeFeature == "plant", false) then
        selectFeature("plant")
    end
    for _, feat in ipairs(getDynamicFeatures()) do
        if styledBtn(tostring(feat.label or feat.id), btnW, activeFeature == feat.id, false) then
            selectFeature(feat.id)
        end
    end

    -- Dorong kontrol jendela (Pin & Hide UI) ke bagian paling bawah sidebar, terpisah dari fitur
    local rowH = 38
    local _, ly1, _, ly2 = getLastItemRect()
    if ly1 and ly2 and (ly2 - ly1) >= 18 then
        rowH = math.ceil((ly2 - ly1) + 8)
    elseif ImGui and ImGui.GetFrameHeightWithSpacing then
        local okFH, fh = pcall(ImGui.GetFrameHeightWithSpacing)
        if okFH and type(fh) == "number" and fh >= 18 then
            rowH = math.ceil(fh)
        end
    end

    local availY = nil
    if ImGui and ImGui.GetContentRegionAvail then
        local okA, av, av2 = pcall(ImGui.GetContentRegionAvail)
        if okA and av then
            if type(av) == "number" and type(av2) == "number" then
                availY = av2
            else
                local okY, y = pcall(function() return av.y end)
                if okY and type(y) == "number" then availY = y end
            end
        end
    end
    if not availY and ImGui and ImGui.GetWindowSize and ImGui.GetCursorPosY then
        local okS, ws, wsH = pcall(ImGui.GetWindowSize)
        local okC, cy = pcall(ImGui.GetCursorPosY)
        local wh = nil
        if okS and ws then
            if type(ws) == "number" and type(wsH) == "number" then
                wh = wsH
            else
                local okH, h = pcall(function() return ws.y end)
                if okH and type(h) == "number" then wh = h end
            end
        end
        if wh and okC and type(cy) == "number" then
            availY = wh - cy - 12
        end
    end

    local bottomBlockH = (rowH * 2) + 22
    local pushDown = 20
    if availY and availY > bottomBlockH then
        pushDown = math.max(20, math.min(320, math.floor(availY - bottomBlockH)))
    end
    uiGap(pushDown)
    drawSidebarDivider(btnW)
    uiGap(6)

    -- Tombol Pin (Hitam + Neon: ON = terkunci tidak bergeser, OFF = bebas digeser)
    local pinPushed = 0
    if detectPushColorMode() ~= "none" and ImGui and ImGui.Col then
        local C = ImGui.Col
        local function pc(idx, col)
            if pushOneColor(idx, col) then pinPushed = pinPushed + 1 end
        end
        if isPinned then
            pc(C.Button,        P.onBtn)
            pc(C.ButtonHovered, P.onBtnHover)
            pc(C.ButtonActive,  P.onBtnActive)
            pc(C.Border,        P.onBorder)
            pc(C.Text,          P.onText)
        else
            pc(C.Button,        P.offBtn)
            pc(C.ButtonHovered, P.offBtnHover)
            pc(C.ButtonActive,  P.offBtnActive)
            pc(C.Border,        P.offBorder)
            pc(C.Text,          P.offText)
        end
    end
    if fullBtn(isPinned and "Pin: ON##sb_pin" or "Pin: OFF##sb_pin", btnW) then
        isPinned = not isPinned
        if isPinned and lastWinX and lastWinY then
            pinnedX, pinnedY = lastWinX, lastWinY
        end
        setNotice(isPinned and "Jendela dikunci (Pin ON)." or "Jendela bebas digeser (Pin OFF).")
    end
    if pinPushed > 0 and ImGui and ImGui.PopStyleColor then
        pcall(ImGui.PopStyleColor, pinPushed)
    end

    if styledBtn("Hide UI", btnW, false, true) then
        windowOpen = false
    end
end

-- ============================================================================
-- PANEL KANAN: SUB-MENU ATAS + KONTEN KATEGORI AKTIF (DINAMIS)
-- ============================================================================
local function renderRightPanel()
    -- Micro slide-in halus saat baru pindah fitur (6px -> 0px dalam 0.26 detik)
    local sp = getSwitchProgress()
    if sp < 1.0 then
        local ease = 1.0 - (1.0 - sp) * (1.0 - sp) * (1.0 - sp)
        local slideY = math.floor((1.0 - ease) * 7)
        if slideY >= 1 then uiGap(slideY) end
    end

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

    else
        -- Render otomatis untuk semua fitur dinamis dari manifest (Dirt Farm, Build Soil, Buy Pack, + fitur baru!)
        local foundFeat = nil
        for _, feat in ipairs(getDynamicFeatures()) do
            if feat.id == activeFeature then foundFeat = feat; break end
        end
        if foundFeat then
            local mod = foundFeat.mod or (HUB and HUB[foundFeat.id])
            if mod and type(mod.render) == "function" then
                mod.render(HUB)
            else
                ImGui.Text("Modul " .. tostring(foundFeat.label or foundFeat.id) .. " belum dimuat.")
                if foundFeat.path and autoBtn(loadingModFlag[foundFeat.id] and "Memuat..." or (" Muat Modul " .. tostring(foundFeat.label) .. " ")) then
                    triggerLazyLoad(foundFeat.id, foundFeat.path)
                end
            end
        else
            renderDashboardPanel()
        end
    end
end

-- ============================================================================
-- MAIN IMGUI RENDER LOOP
-- ============================================================================
local wasItemActive = false
local miniWinW, miniWinH = 280, 172

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
    local condAlways = (ImGui.Cond and ImGui.Cond.Always) or 1
    local condOnce   = (ImGui.Cond and ImGui.Cond.Once) or 2

    if not windowOpen then
        wasItemActive = false
        if ImGui.SetNextWindowBgAlpha then pcall(ImGui.SetNextWindowBgAlpha, 1.0) end
        if ImGui.SetNextWindowPos and ImVec2 then
            local mcx, mcy = getCenteredWindowPos(miniWinW, miniWinH)
            pcall(ImGui.SetNextWindowPos, ImVec2(mcx, mcy), condOnce)
        end
        if ImGui.SetNextWindowSize and ImVec2 then
            local okSz = pcall(ImGui.SetNextWindowSize, ImVec2(miniWinW, miniWinH), condAlways)
            if not okSz then pcall(ImGui.SetNextWindowSize, ImVec2(miniWinW, miniWinH)) end
        end
        if ImGui.Begin("BOREN STORE##boren_mini") then
            if ImGui.SetWindowFontScale then pcall(ImGui.SetWindowFontScale, 1.08) end
            drawWindowNeonChrome()

            -- Ukur lebar teks aktual (setelah FontScale) agar tombol & title bar bebas terpotong
            local lblText = "Open Menu"
            local btnTextW, titleTextW = 120, 140
            if ImGui.CalcTextSize then
                local okB, szB = pcall(ImGui.CalcTextSize, lblText)
                if okB and szB then
                    local okW, w = pcall(function() return szB.x end)
                    if okW and type(w) == "number" and w > 20 then btnTextW = w end
                end
                local okT, szT = pcall(ImGui.CalcTextSize, "BOREN STORE")
                if okT and szT then
                    local okW, w = pcall(function() return szT.x end)
                    if okW and type(w) == "number" and w > 20 then titleTextW = w end
                end
            end
            local targetBtnW = math.max(170, math.ceil(btnTextW + 52))
            local exactW = math.max(260, math.min(480, math.ceil(math.max(targetBtnW + 36, titleTextW + 100))))

            local avM = safeAvailX()
            if avM > miniWinW then avM = math.max(160, miniWinW - 24) end
            local drawBtnW = math.max(140, math.min(avM - 4, math.max(targetBtnW, avM - 8)))

            if centeredBtn(lblText .. "##open_boren", drawBtnW, avM, true) then
                windowOpen = true
                switchAnimStart = nowSec()
            end

            -- Auto-fit tinggi presisi dari batas bawah aktual tombol (bebas terpotong di semua DPI HP!)
            local exactH = nil
            local _, by1, _, by2 = getLastItemRect()
            if by1 and by2 and ImGui.GetWindowPos then
                local okP, wp, wpY = pcall(ImGui.GetWindowPos)
                local wy = nil
                if okP and wp then
                    if type(wp) == "number" and type(wpY) == "number" then
                        wy = wpY
                    else
                        local okY, y = pcall(function() return wp.y end)
                        if okY and type(y) == "number" then wy = y end
                    end
                end
                if wy and by2 > wy then
                    local btnH = math.max(26, by2 - by1)
                    local bottomPad = math.max(22, math.ceil(btnH * 0.45))
                    exactH = math.ceil((by2 - wy) + bottomPad)
                end
            end
            if not exactH and ImGui.GetCursorPosY then
                local okCY, cy = pcall(ImGui.GetCursorPosY)
                if okCY and type(cy) == "number" and cy > 30 then
                    exactH = math.ceil(cy + 24)
                end
            end
            if exactH then
                exactH = math.max(115, math.min(340, exactH))
                if math.abs(exactH - miniWinH) >= 2 then miniWinH = exactH end
            end
            if math.abs(exactW - miniWinW) >= 2 then miniWinW = exactW end
        end
        ImGui.End()
        popBorenTheme(cCnt, vCnt)
        return
    end

    local initW, initH = 760, 450
    if ImGui.SetNextWindowBgAlpha then pcall(ImGui.SetNextWindowBgAlpha, 1.0) end
    if ImGui.SetNextWindowSize and ImVec2 then
        pcall(ImGui.SetNextWindowSize, ImVec2(initW, initH), condOnce)
    end
    if ImGui.SetNextWindowPos and ImVec2 then
        if needCenterPos then
            local cx, cy = getCenteredWindowPos(initW, initH)
            pinnedX, pinnedY = cx, cy
            pcall(ImGui.SetNextWindowPos, ImVec2(cx, cy), condAlways)
            needCenterPos = false
        elseif isPinned and (not wasItemActive) and pinnedX and pinnedY then
            pcall(ImGui.SetNextWindowPos, ImVec2(pinnedX, pinnedY), condAlways)
        end
    end

    if ImGui.Begin("BOREN STORE##boren_main") then
        if ImGui.SetWindowFontScale then pcall(ImGui.SetWindowFontScale, 1.08) end
        if ImGui.GetWindowPos then
            local okP, wp = pcall(ImGui.GetWindowPos)
            if okP and wp then
                local okXY, wx, wy = pcall(function() return wp.x, wp.y end)
                if okXY and type(wx) == "number" and type(wy) == "number" then
                    lastWinX, lastWinY = wx, wy
                    if not pinnedX then pinnedX, pinnedY = wx, wy end
                end
            end
        end
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
        drawSwitchEffect(sideW)

        if ImGui.IsAnyItemActive then
            local okA, actv = pcall(ImGui.IsAnyItemActive)
            wasItemActive = (okA and actv == true)
        else
            wasItemActive = false
        end
    end
    ImGui.End()
    popBorenTheme(cCnt, vCnt)
end

-- ============================================================================
-- HOOKS (DIALOG NATIVE INPUT + /hub /reload /add /st COMMANDS + ANTI GEMS)
-- ============================================================================
local function parseDialogReturnFields(pktStr)
    local fields = {}
    for line in tostring(pktStr or ""):gmatch("[^\r\n]+") do
        local k, v = line:match("^([^|]+)|(.*)$")
        if k and k ~= "" then
            fields[k] = tostring(v or ""):gsub("^%s+", ""):gsub("%s+$", "")
        end
    end
    return fields
end

local function handleSendPacket(pktType, pktStr)
    if type(pktStr) == "string" then
        -- 1. Tangkap hasil ketikan dari Native Dialog Popup (Ketik Keyboard HP)
        if pktStr:find("action|dialog_return", 1, true) then
            local dlgName = pktStr:match("dialog_name|([^\r\n|]+)")
            if dlgName and activeNativeDialogs[dlgName] then
                local cb = activeNativeDialogs[dlgName]
                activeNativeDialogs[dlgName] = nil
                local fields = parseDialogReturnFields(pktStr)
                local btn = tostring(fields.buttonClicked or ""):lower()
                if btn ~= "batal" and btn ~= "cancel" and btn ~= "close" then
                    pcall(cb, fields)
                end
                -- Otomatis tampilkan kembali BOREN STORE setelah selesai mengetik!
                windowOpen = true
                switchAnimStart = nowSec()
                return true
            end
        end

        -- 2. Tangkap perintah chat (/hub, /reload, /add, /st, /df, /soil)
        local txt = pktStr:match("text|([^\n\r]+)")
        if txt then
            local trimmed = txt:gsub("^%s+", ""):gsub("%s+$", "")
            local cmd = trimmed:lower()
            if cmd == "/hub" then
                windowOpen = not windowOpen
                if LogToConsole then
                    pcall(LogToConsole, "`e[BOREN STORE] `wUI " .. (windowOpen and "`2DITAMPILKAN" or "`4DISEMBUNYIKAN"))
                end
                return true
            elseif cmd == "/reload" then
                triggerHotReloadAll()
                return true
            elseif cmd == "/ketik" then
                showKetikBtn = not showKetikBtn
                if LogToConsole then
                    pcall(LogToConsole, "`e[BOREN STORE] `wTombol Ketik HP: " .. (showKetikBtn and "`2ON" or "`4HIDDEN"))
                end
                return true
            elseif cmd:sub(1, 5) == "/add " and HUB and HUB.plant then
                local arg = trimmed:sub(6):gsub("^%s+", "")
                local p = HUB.plant.parseRowLine and HUB.plant.parseRowLine(arg)
                if p then
                    table.insert(HUB.plant.STATE.rows, p)
                    HUB.plant.saveData()
                    setNotice("Ditambah via chat: " .. p.name)
                    if LogToConsole then pcall(LogToConsole, "`e[BOREN STORE] `2World Plant ditambah: `w" .. p.name) end
                end
                return true
            elseif cmd:sub(1, 4) == "/st " and HUB and HUB.plant then
                local arg = trimmed:sub(5):gsub("^%s+", "")
                local p = HUB.plant.parseStorageLine and HUB.plant.parseStorageLine(arg)
                if p then
                    local st = HUB.plant.getStorageList and HUB.plant.getStorageList() or {}
                    table.insert(st, p)
                    HUB.plant.setStorageList(st)
                    setNotice("Storage ditambah via chat: " .. p.name)
                    if LogToConsole then pcall(LogToConsole, "`e[BOREN STORE] `2Storage ditambah: `w" .. p.name) end
                end
                return true
            end
        end
    end
    -- Dispatch opsional ke modul fitur dinamis yang menyediakan handleSendPacket
    if HUB then
        for _, feat in ipairs(getDynamicFeatures()) do
            local m = feat.mod or HUB[feat.id]
            if m and type(m.handleSendPacket) == "function" then
                local ok, blocked = pcall(m.handleSendPacket, pktType, pktStr)
                if ok and blocked == true then return true end
            end
        end
    end
    return false
end

local function handleSendPacketRaw(pkt)
    if type(pkt) ~= "table" or not HUB then return false end
    if tonumber(pkt.type) == 11 then
        -- Anti-Take untuk modul apapun yang mengaktifkan anti_take_active (misal Auto Buy Pack)
        for _, feat in ipairs(getDynamicFeatures()) do
            local m = feat.mod or HUB[feat.id]
            if m and m.STATE and m.STATE.anti_take_active then
                return true
            end
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
    for _, feat in ipairs(getDynamicFeatures()) do
        local m = feat.mod or HUB[feat.id]
        if m and type(m.handleSendPacketRaw) == "function" then
            local ok, blocked = pcall(m.handleSendPacketRaw, pkt)
            if ok and blocked == true then return true end
        end
    end
    return false
end

local function handleVariant(var)
    if not HUB then return false end
    if HUB.plant and type(HUB.plant.handleVariant) == "function" then
        local okP, blockedP = pcall(HUB.plant.handleVariant, var)
        if okP and blockedP == true then return true end
    end
    for _, feat in ipairs(getDynamicFeatures()) do
        local m = feat.mod or HUB[feat.id]
        if m and type(m.handleVariant) == "function" then
            local ok, blocked = pcall(m.handleVariant, var)
            if ok and blocked == true then return true end
        end
    end
    return false
end

UI.onSendPacket    = handleSendPacket
UI.onSendPacketRaw = handleSendPacketRaw
UI.onVariant       = handleVariant

function UI.init(hubCtx)
    HUB = hubCtx
    if HUB then HUB.ui_kit = UI_KIT end
    needCenterPos = true
    switchAnimStart = nowSec()
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
