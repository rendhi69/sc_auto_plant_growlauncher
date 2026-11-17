-- ============================================================================
-- BOREN HUB IMGUI - THEME & REUSABLE WIDGETS MODULE
-- File: imgui_hub/theme_widgets.lua
-- ============================================================================

local M = {}

local function vec2(x, y)
    if ImVec2 then return ImVec2(x or 0, y or 0) end
    return { x = x or 0, y = y or 0 }
end

local function vec4(r, g, b, a)
    if ImVec4 then return ImVec4(r or 1, g or 1, b or 1, a or 1) end
    return { x = r or 1, y = g or 1, z = b or 1, w = a or 1 }
end

M.vec2 = vec2
M.vec4 = vec4

-- Palet Dark Navy Blue (terinspirasi gaya menu hub modern)
M.COLORS = {
    windowBg        = vec4(0.03, 0.06, 0.11, 0.96),
    childBg         = vec4(0.04, 0.08, 0.14, 0.98),
    popupBg         = vec4(0.04, 0.08, 0.15, 0.98),
    border          = vec4(0.14, 0.27, 0.43, 0.85),
    frameBg         = vec4(0.05, 0.10, 0.18, 1.00),
    frameBgHovered  = vec4(0.08, 0.16, 0.28, 1.00),
    frameBgActive   = vec4(0.11, 0.22, 0.38, 1.00),
    titleBg         = vec4(0.04, 0.08, 0.15, 1.00),
    titleBgActive   = vec4(0.07, 0.15, 0.27, 1.00),
    button          = vec4(0.06, 0.12, 0.21, 1.00),
    buttonHovered   = vec4(0.11, 0.23, 0.39, 1.00),
    buttonActive    = vec4(0.15, 0.33, 0.56, 1.00),
    sidebarActive   = vec4(0.13, 0.34, 0.58, 1.00),
    sidebarInactive = vec4(0.05, 0.10, 0.18, 1.00),
    header          = vec4(0.11, 0.28, 0.48, 0.85),
    headerHovered   = vec4(0.15, 0.35, 0.59, 0.95),
    headerActive    = vec4(0.18, 0.41, 0.68, 1.00),
    tableHeaderBg   = vec4(0.06, 0.13, 0.23, 1.00),
    tableRowBg      = vec4(0.04, 0.08, 0.14, 0.60),
    tableRowBgAlt   = vec4(0.05, 0.10, 0.17, 0.70),
    tableBorder     = vec4(0.12, 0.24, 0.38, 0.75),
    text            = vec4(0.89, 0.94, 0.99, 1.00),
    textMuted       = vec4(0.56, 0.66, 0.78, 1.00),
    toggleOn        = vec4(0.16, 0.48, 0.84, 1.00),
    toggleOnHover   = vec4(0.22, 0.56, 0.92, 1.00),
    toggleOff       = vec4(0.12, 0.17, 0.25, 1.00),
    toggleOffHover  = vec4(0.17, 0.24, 0.34, 1.00),
    statusReady     = vec4(0.76, 0.84, 0.92, 1.00),
    statusActive    = vec4(0.26, 0.78, 1.00, 1.00),
    statusDone      = vec4(0.28, 0.86, 0.48, 1.00),
    statusWarn      = vec4(1.00, 0.76, 0.26, 1.00),
    statusError     = vec4(0.98, 0.36, 0.36, 1.00),
}

-- Konstanta numerik aman untuk flag ImGui (kompatibel Lua 5.1 / LuaJIT / 5.4)
function M.getTableFlags()
    local tf = ImGui and ImGui.TableFlags
    local resizable   = (tf and tf.Resizable) or 1
    local rowBg       = (tf and tf.RowBg) or 64
    local borderInH   = (tf and tf.BordersInnerH) or 128
    local borderOutH  = (tf and tf.BordersOuterH) or 256
    local borderInV   = (tf and tf.BordersInnerV) or 512
    local borderOutV  = (tf and tf.BordersOuterV) or 1024
    local scrollY     = (tf and tf.ScrollY) or 33554432
    return resizable + rowBg + borderInH + borderOutH + borderInV + borderOutV + scrollY
end

function M.getSelectableSpanFlag()
    local sf = ImGui and ImGui.SelectableFlags
    return (sf and sf.SpanAllColumns) or 2
end

-- Terapkan tema Dark Navy Blue (mengembalikan jumlah color & var yang di-push)
function M.pushTheme()
    local colCount, varCount = 0, 0
    if not ImGui or not ImGui.PushStyleColor then return 0, 0 end

    local C = ImGui.Col or {}
    local V = ImGui.StyleVar or {}
    local pal = M.COLORS

    local function pushC(idx, col)
        if idx ~= nil then
            ImGui.PushStyleColor(idx, col)
            colCount = colCount + 1
        end
    end

    local function pushV(idx, val)
        if idx ~= nil and ImGui.PushStyleVar then
            ImGui.PushStyleVar(idx, val)
            varCount = varCount + 1
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

    pushV(V.WindowRounding,   6.0)
    pushV(V.ChildRounding,    4.0)
    pushV(V.FrameRounding,    4.0)
    pushV(V.WindowBorderSize, 1.0)
    pushV(V.ChildBorderSize,  1.0)
    pushV(V.FrameBorderSize,  1.0)
    pushV(V.WindowPadding,    vec2(8, 8))
    pushV(V.ItemSpacing,      vec2(6, 5))
    pushV(V.FramePadding,     vec2(7, 4))

    return colCount, varCount
end

function M.popTheme(colCount, varCount)
    if ImGui then
        if varCount and varCount > 0 and ImGui.PopStyleVar then
            ImGui.PopStyleVar(varCount)
        end
        if colCount and colCount > 0 and ImGui.PopStyleColor then
            ImGui.PopStyleColor(colCount)
        end
    end
end

-- Custom Toggle Switch gaya pil geser (seperti Enable / Loop pada gambar)
function M.toggleSwitch(id, isOn)
    local C = ImGui.Col or {}
    local V = ImGui.StyleVar or {}
    local pal = M.COLORS

    local pCol, pVar = 0, 0
    if V.FrameRounding and ImGui.PushStyleVar then
        ImGui.PushStyleVar(V.FrameRounding, 11.0)
        pVar = pVar + 1
    end
    if C.Button and ImGui.PushStyleColor then
        ImGui.PushStyleColor(C.Button, isOn and pal.toggleOn or pal.toggleOff)
        pCol = pCol + 1
    end
    if C.ButtonHovered and ImGui.PushStyleColor then
        ImGui.PushStyleColor(C.ButtonHovered, isOn and pal.toggleOnHover or pal.toggleOffHover)
        pCol = pCol + 1
    end
    if C.ButtonActive and ImGui.PushStyleColor then
        ImGui.PushStyleColor(C.ButtonActive, pal.toggleOnHover)
        pCol = pCol + 1
    end

    local caption = (isOn and "  ON" or "OFF ") .. "##sw_" .. tostring(id)
    local clicked = ImGui.Button(caption, vec2(44, 22))

    if pVar > 0 and ImGui.PopStyleVar then ImGui.PopStyleVar(pVar) end
    if pCol > 0 and ImGui.PopStyleColor then ImGui.PopStyleColor(pCol) end

    if clicked then
        return true, (not isOn)
    end
    return false, isOn
end

-- InputText dengan Hint aman lintas versi GL
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

-- Warna status baris tabel
function M.statusColor(status)
    local s = tostring(status or ""):lower()
    if s:find("done", 1, true) or s:find("selesai", 1, true) then
        return M.COLORS.statusDone
    elseif s:find("plant", 1, true) or s:find("warp", 1, true) or s:find("restock", 1, true) then
        return M.COLORS.statusActive
    elseif s:find("inaccessible", 1, true) or s:find("error", 1, true) or s:find("lock", 1, true) then
        return M.COLORS.statusError
    elseif s:find("no seed", 1, true) or s:find("habis", 1, true) or s:find("pause", 1, true) then
        return M.COLORS.statusWarn
    end
    return M.COLORS.statusReady
end

function M.textColored(col, text)
    if ImGui.TextColored then
        local ok = pcall(ImGui.TextColored, col, tostring(text))
        if ok then return end
    end
    ImGui.Text(tostring(text))
end

return M
