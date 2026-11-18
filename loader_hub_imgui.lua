-- ============================================================================
-- LOADER BOREN STORE IMGUI (PERMANENT THIN LOADER)
-- File: loader_hub_imgui.lua
-- ============================================================================
-- Loader tipis permanen — tidak perlu diubah lagi saat ada penambahan fitur.
-- Endpoint remote di-encode agar URL sumber tidak tampil polos di file loader.
-- ============================================================================

local function _d(t, seed)
    local out = {}
    for i = 1, #t do
        local k = (seed + i * 17) % 256
        out[i] = string.char((t[i] - k) % 256)
    end
    return table.concat(out)
end

local _u = _d({
    164,193,210,223,243,203,209,226,54,54,93,37,111,130,158,163,193,191,227,
    242,245,19,21,50,66,89,91,117,140,87,157,186,201,156,240,244,14,21,42,60,
    26,46,53,138,139,152,171,208,224,236,237,15,28,34,64,87,83,108,136,150,
    175,181,187,224,234,240,6,20,50,0,79,84,109,131,85
}, 43)

local _p = _d({
    193,214,225,0,5,12,38,68,66,32,100,130,147,169,116,195,221,218
}, 71)

local function makeTag()
    if getTime then
        local ok, ms = pcall(getTime)
        if ok and tonumber(ms) then return tostring(math.floor(tonumber(ms))) end
    end
    if os and os.time then
        local ok, t = pcall(os.time)
        if ok and tonumber(t) then return tostring(math.floor(tonumber(t))) end
    end
    return tostring(math.random(100000, 999999))
end

local function logMsg(msg)
    if LogToConsole then pcall(LogToConsole, "`e[BOREN STORE] `w" .. tostring(msg)) end
end

local function notifyMsg(msg)
    if sendNotification then pcall(sendNotification, tostring(msg))
    elseif growtopia and growtopia.notify then pcall(growtopia.notify, tostring(msg)) end
end

local code = nil
if fetch then
    local okF, res = pcall(fetch, _u .. _p .. "?v=" .. makeTag())
    if okF and type(res) == "string" and res ~= "" and not res:match("^404") and not res:match("^<!DOCTYPE") then
        code = res
    end
end

if not code or code == "" then
    local localRoots = {
        "/storage/emulated/0/Android/media/launcher.powerkuy.growlauncher/ScriptLua/",
        "/storage/emulated/0/Android/data/launcher.powerkuy.growlauncher/files/ScriptLua/",
        "/storage/emulated/0/Download/",
        "script/",
        "",
    }
    for _, root in ipairs(localRoots) do
        local okO, f = pcall(io.open, root .. _p, "r")
        if okO and f then
            local txt = f:read("*a")
            f:close()
            if txt and txt ~= "" then code = txt; break end
        end
    end
end

if not code or code == "" then
    logMsg("`4Gagal memuat BOREN STORE! Cek koneksi internet.")
    notifyMsg("Gagal memuat BOREN STORE! Cek koneksi.")
    return
end

local loaderFn = loadstring or load
local chunk, err = loaderFn(code)
if not chunk then
    logMsg("`4Error kompilasi core: " .. tostring(err))
    return
end

local okRun, boot = pcall(chunk)
if not okRun or type(boot) ~= "table" or type(boot.start) ~= "function" then
    logMsg("`4Error menjalankan core: " .. tostring(boot))
    return
end

boot.start(_u)
