-- ============================================================================
-- BOREN HUB IMGUI - SAFE SHELL WRAPPER (BACKWARD COMPATIBLE DENGAN LOADER LAMA)
-- File: imgui_hub/hub_shell.lua
-- ============================================================================

local Shell = {}

function Shell.init(hubContext)
    if hubContext and hubContext.tabs then
        for _, t in ipairs(hubContext.tabs) do
            if type(t) == "table" and type(t.init) == "function" then
                t.init(hubContext)
                return
            end
        end
    end
end

return Shell
