-- ============================================================================
-- BOREN HUB IMGUI - SAFE THEME & REUSABLE WIDGETS MODULE
-- File: imgui_hub/theme_widgets.lua
-- ============================================================================

local M = {}

local colorCache = nil
local vec4Supported = nil
local styleVarVec2Supported = nil

local function canUseImVec4()
    if vec4Supported ~= nil then return vec4Supported end
    if ImVec4 then
        local ok, v = pcall(ImVec4, 1.0, 1.0, 1.0, 1.0)
        vec4Supported = (ok and v ~= nil)
    else
        vec4Supported = false
    end
    return vec4Supported
end

function M.vec2(x, y)
    if ImVec2 then
        local ok, v = pcall(ImVec2, x or 0, y or 0)
        if ok and v ~= nil then return v end
    end
    return nil
end

function M.vec4(r, g, b, a)
    if canUseImVec4() then
        local ok, v = pcall(ImVec4, r or 1, g or 1, b or 1, a or 1)
        if ok and v ~= nil then return v end
    end
    return nil
end

-- Buat palet secara lazy (hanya dipanggil saat ImGui sudah siap di OnDrawImGui)
function M.getColors()
    if colorCache then return colorCache end
    local v4 = M.vec4
    colorCache = {
        windowBg        = v4(0.03, 0.06, 0.11, 0.96),
        childBg         = v4(0.04, 0.08, 0.14, 0.98),
        popupBg         = v4(0.04, 0.08, 0.15, 0.98),
        border          = v4(0.14, 0.27, 0.43, 0.85),
        frameBg         = v4(0.05, 0.10, 0.18, 1.00),
        frameBgHovered  = v4(0.08, 0.16, 0.28, 1.00),
        frameBgActive   = v4(0.11, 0.22, 0.38, 1.00),
        titleBg         = v4(0.04, 0.08, 0.15, 1.00),
        titleBgActive   = v4(0.07, 0.15, 0.27, 1.00),
        button          = v4(0.06, 0.12, 0.21, 1.00),
        buttonHovered   = v4(0.11, 0.23, 0.39, 1.00),
        buttonActive    = v4(0.15, 0.33, 0.56, 1.00),
        sidebarActive   = v4(0.13, 0.34, 0.58, 1.00),
        sidebarInactive = v4(0.05, 0.10, 0.18, 1.00),
        header          = v4(0.11, 0.28, 0.48, 0.85),
        headerHovered   = v4(0.15, 0.35, 0.59, 0.95),
        headerActive    = v4(0.18, 0.41, 0.68, 1.00),
        tableHeaderBg   = v4(0.06, 0.13, 0.23, 1.00),
        tableRowBg      = v4(0.04, 0.08, 0.14, 0.60),
        tableRowBgAlt   = v4(0.05, 0.10, 0.17, 0.70),
        tableBorder     = v4(0.12, 0.24, 0.38, 0.75),
        text            = v4(0.89, 0.94, 0.99, 1.00),
        textMuted       = v4(0.56, 0.66, 0.78, 1.00),
        toggleOn        = v4(0.16, 0.48, 0.84, 1.00),
        toggleOnHover   = v4(0.22, 0.56, 0.92, 1.00),
        toggleOff       = v4(0.12, 0.17, 0.25, 1.00),
        toggleOffHover  = v4(0.17, 0.24, 0.34, 1.00),
        statusReady     = v4(0.76, 0.84, 0.92, 1.00),
        statusActive    = v4(0.26, 0.78, 1.00, 1.00),
        statusDone      = v4(0.28, 0.86, 0.48, 1.00),
        statusWarn      = v4(1.00, 0.76, 0.26, 1.00),
        statusError     = v4(0.98, 0.36, 0.36, 1.00),
    }
    return colorCache
end

-- Flag tabel aman (tanpa ScrollY berisiko — scroll ditangani oleh BeginChild pembungkus)
function M.getTableFlags()
    -- RowBg(64) + BordersInnerH(128) + BordersOuterH(256) + BordersInnerV(512) + BordersOuterV(1024)
    return 64 + 128 + 256 + 512 + 1024
end

-- Push style warna/var secara aman: hanya menghitung yang benar-benar berhasil di-push!
function M.pushTheme()
    local colCount, varCount = 0, 0
    if not ImGui then return 0, 0 end

    local C = ImGui.Col or {}
    local V = ImGui.StyleVar or {}
    local pal = M.getColors()

    if ImGui.PushStyleColor and canUseImVec4() then
        local function pushC(idx, col)
            if idx ~= nil and col ~= nil then
                local ok = pcall(ImGui.PushStyleColor, idx, col)
                if ok then colCount = colCount + 1 end
            end
        end

        pushC(C.WindowBg,          pal.windowBg)
        pushC(C.ChildBg,           pal.childBg)
        pushC(C.PopupBg,           pal.popupBg)
        pushC(C.Border,            pal.border)
        pushC(C.FrameBg,           pal.frameBg)
        pushC(C.FrameBgHovered,    pal.frameBgHovered)
        pushC(C.FrameBgActive,     pal.frameBgActive)
        pushC(C.TitleBg,           pal.titleBg)
        pushC(C.TitleBgActive,     pal.titleBgActive)
        pushC(C.Button,            pal.button)
        pushC(C.ButtonHovered,     pal.buttonHovered)
        pushC(C.ButtonActive,      pal.buttonActive)
        pushC(C.Header,            pal.header)
        pushC(C.HeaderHovered,     pal.headerHovered)
        pushC(C.HeaderActive,      pal.headerActive)
        pushC(C.TableHeaderBg,     pal.tableHeaderBg)
        pushC(C.TableRowBg,        pal.tableRowBg)
        pushC(C.TableRowBgAlt,     pal.tableRowBgAlt)
        pushC(C.TableBorderStrong, pal.tableBorder)
        pushC(C.TableBorderLight,  pal.tableBorder)
        pushC(C.Text,              pal.text)
        pushC(C.TextDisabled,      pal.textMuted)
        pushC(C.Separator,         pal.border)
    end

    if ImGui.PushStyleVar then
        local function pushVFloat(idx, val)
            if idx ~= nil and val ~= nil then
                local ok = pcall(ImGui.PushStyleVar, idx, val)
                if ok then varCount = varCount + 1 end
            end
        end

        pushVFloat(V.WindowRounding,   6.0)
        pushVFloat(V.ChildRounding,    4.0)
        pushVFloat(V.FrameRounding,    4.0)
        pushVFloat(V.WindowBorderSize, 1.0)
        pushVFloat(V.ChildBorderSize,  1.0)
        pushVFloat(V.FrameBorderSize,  1.0)

        if styleVarVec2Supported ~= false then
            local wp = M.vec2(8, 8)
            if V.WindowPadding and wp then
                local ok1 = pcall(ImGui.PushStyleVar, V.WindowPadding, wp)
                if ok1 then
                    varCount = varCount + 1
                    styleVarVec2Supported = true
                    local is = M.vec2(6, 5)
                    if V.ItemSpacing and is and pcall(ImGui.PushStyleVar, V.ItemSpacing, is) then
                        varCount = varCount + 1
                    end
                    local fp = M.vec2(7, 4)
                    if V.FramePadding and fp and pcall(ImGui.PushStyleVar, V.FramePadding, fp) then
                        varCount = varCount + 1
                    end
                else
                    styleVarVec2Supported = false
                end
            end
        end
    end

    return colCount, varCount
end

function M.popTheme(colCount, varCount)
    if not ImGui then return end
    if varCount and varCount > 0 and ImGui.PopStyleVar then
        pcall(ImGui.PopStyleVar, varCount)
    end
    if colCount and colCount > 0 and ImGui.PopStyleColor then
        pcall(ImGui.PopStyleColor, colCount)
    end
end

-- Button aman lintas signature (ImVec2 atau 1 arg)
function M.button(label, w, h)
    if w and h then
        local sz = M.vec2(w, h)
        if sz then
            local ok, res = pcall(ImGui.Button, label, sz)
            if ok then return res == true end
        end
    end
    local ok, res = pcall(ImGui.Button, label)
    return ok and (res == true)
end

-- Custom Toggle Switch gaya pil geser (stack-safe)
function M.toggleSwitch(id, isOn)
    local C = ImGui.Col or {}
    local V = ImGui.StyleVar or {}
    local pal = M.getColors()

    local pCol, pVar = 0, 0
    if V.FrameRounding and ImGui.PushStyleVar then
        if pcall(ImGui.PushStyleVar, V.FrameRounding, 11.0) then pVar = pVar + 1 end
    end
    if ImGui.PushStyleColor and canUseImVec4() then
        local cMain = isOn and pal.toggleOn or pal.toggleOff
        local cHov  = isOn and pal.toggleOnHover or pal.toggleOffHover
        if C.Button and cMain and pcall(ImGui.PushStyleColor, C.Button, cMain) then pCol = pCol + 1 end
        if C.ButtonHovered and cHov and pcall(ImGui.PushStyleColor, C.ButtonHovered, cHov) then pCol = pCol + 1 end
        if C.ButtonActive and pal.toggleOnHover and pcall(ImGui.PushStyleColor, C.ButtonActive, pal.toggleOnHover) then pCol = pCol + 1 end
    end

    local caption = (isOn and " ON " or "OFF ") .. "##sw_" .. tostring(id)
    local clicked = M.button(caption, 46, 22)

    if pVar > 0 and ImGui.PopStyleVar then pcall(ImGui.PopStyleVar, pVar) end
    if pCol > 0 and ImGui.PopStyleColor then pcall(ImGui.PopStyleColor, pCol) end

    if clicked then
        return true, (not isOn)
    end
    return false, isOn
end

-- InputText aman (prioritaskan ImGui.InputText yang sudah teruji di world_saver.lua)
function M.inputTextHint(id, hint, currentText, maxLen)
    currentText = tostring(currentText or "")
    maxLen = maxLen or 256
    if ImGui.InputTextWithHint then
        local ok, changed, newText = pcall(ImGui.InputTextWithHint, id, hint, currentText, maxLen)
        if ok then
            if type(newText) == "string" then
                return (changed == true), newText
            elseif type(changed) == "string" then
                return (changed ~= currentText), changed
            end
        end
    end
    if ImGui.InputText then
        local ok, changed, newText = pcall(ImGui.InputText, id, currentText, maxLen)
        if ok then
            if type(newText) == "string" then
                return (changed == true), newText
            elseif type(changed) == "string" then
                return (changed ~= currentText), changed
            end
        end
    end
    return false, currentText
end

function M.statusColor(status)
    local pal = M.getColors()
    local s = tostring(status or ""):lower()
    if s:find("done", 1, true) or s:find("selesai", 1, true) then
        return pal.statusDone
    elseif s:find("plant", 1, true) or s:find("warp", 1, true) or s:find("restock", 1, true) or s:find("y=", 1, true) then
        return pal.statusActive
    elseif s:find("inaccessible", 1, true) or s:find("error", 1, true) or s:find("lock", 1, true) then
        return pal.statusError
    elseif s:find("no seed", 1, true) or s:find("habis", 1, true) or s:find("sisa", 1, true) then
        return pal.statusWarn
    end
    return pal.statusReady
end

function M.textColored(col, text)
    text = tostring(text or "")
    if col and ImGui.TextColored then
        local ok = pcall(ImGui.TextColored, col, text)
        if ok then return end
    end
    ImGui.Text(text)
end

-- Helper GetContentRegionAvail aman
function M.getAvailSize()
    if ImGui.GetContentRegionAvail then
        local ok, a, b = pcall(ImGui.GetContentRegionAvail)
        if ok then
            if type(a) == "number" and type(b) == "number" then
                return a, b
            elseif (type(a) == "table" or type(a) == "userdata") then
                local okX, ax = pcall(function() return a.x end)
                local okY, ay = pcall(function() return a.y end)
                if okX and okY and type(ax) == "number" and type(ay) == "number" then
                    return ax, ay
                end
            end
        end
    end
    return 460, 320
end

return M
