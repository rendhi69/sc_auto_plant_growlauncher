-- ============================================================================
-- LOADER AUTO TRANSFER - BOREN STORE (GROWLAUNCHER)
-- File: loader_transfer.lua
-- ============================================================================

local RAW_URL = "https://raw.githubusercontent.com/rendhi69/sc_transfer_growlauncher-/main/auto_transfer.lua"
local cacheBuster = tostring(math.floor((os and os.time and os.time()) or (os and os.clock and os.clock() * 1000) or math.random(100000, 999999)))
local fetchUrl = RAW_URL .. "?v=" .. cacheBuster

local function notifyUser(msg)
    if sendNotification then pcall(sendNotification, msg)
    elseif growtopia and growtopia.notify then pcall(growtopia.notify, msg) end
end

if LogToConsole then LogToConsole("`9[Boren Transfer Loader] `0Memuat Auto Transfer...") end
notifyUser("Memuat Auto Transfer...")

local content = nil
if fetch then
    local ok, res = pcall(fetch, fetchUrl)
    if ok and type(res) == "string" and res ~= "" and not res:match("^404") and not res:match("^<!DOCTYPE") then
        content = res
    end
end

if not content or content == "" then
    local paths = {
        "/storage/emulated/0/Android/media/launcher.powerkuy.growlauncher/ScriptLua/auto_transfer.lua",
        "/storage/emulated/0/Android/data/launcher.powerkuy.growlauncher/files/ScriptLua/auto_transfer.lua",
        "/storage/emulated/0/Download/auto_transfer.lua",
        "script/script code/auto_transfer.lua",
        "auto_transfer.lua",
    }
    for _, p in ipairs(paths) do
        local okF, fh = pcall(io.open, p, "r")
        if okF and fh then
            local txt = fh:read("*a"); fh:close()
            if txt and txt ~= "" then content = txt; break end
        end
    end
end

if content and content ~= "" then
    local chunk, err = (loadstring or load)(content)
    if chunk then
        local okRun, runErr = pcall(chunk)
        if okRun then
            if LogToConsole then LogToConsole("`2[Boren Transfer Loader] `0Auto Transfer siap! (/transfer)") end
            notifyUser("Auto Transfer Siap!")
        else
            if LogToConsole then LogToConsole("`4[Boren Transfer Loader] `0Runtime error: " .. tostring(runErr)) end
        end
    else
        if LogToConsole then LogToConsole("`4[Boren Transfer Loader] `0Compile error: " .. tostring(err)) end
    end
else
    if LogToConsole then LogToConsole("`4[Boren Transfer Loader] `0Gagal memuat auto_transfer.lua.") end
end
