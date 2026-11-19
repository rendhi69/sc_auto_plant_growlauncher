-- ============================================================================
-- LOADER AUTO PLANT & SPLICE - BOREN STORE (AUTO-FETCH DARI GITHUB)
-- ============================================================================
-- Skrip ini otomatis mengambil dan menjalankan auto_plant.lua versi
-- terbaru dari GitHub repository: https://github.com/rendhi69/sc_auto_plant_growlauncher
-- Setiap kali ada update di GitHub, bot otomatis memakai kode terbaru tanpa perlu
-- mengganti atau copy-paste file manual lagi di Growlauncher!
-- Dilengkapi fallback file lokal dan pelaporan error runtime mendalam.
-- ============================================================================

local RAW_URL = "https://raw.githubusercontent.com/rendhi69/sc_auto_plant_growlauncher/main/auto_plant.lua"

-- Parameter unik (?v=timestamp) untuk bypass CDN cache Fastly GitHub (selalu fresh)
local cacheBuster = tostring(math.floor((os and os.time and os.time()) or (os and os.clock and os.clock() * 1000) or math.random(100000, 999999)))
local fetchUrl = RAW_URL .. "?v=" .. cacheBuster

local function notifyUser(msg)
    if sendNotification then
        pcall(sendNotification, msg)
    elseif growtopia and growtopia.notify then
        pcall(growtopia.notify, msg)
    end
end

if LogToConsole then
    LogToConsole("`9[Boren Plant Loader] `0Menghubungkan ke GitHub (Auto Plant & Splice)...")
end
notifyUser("Menghubungkan ke GitHub...")

local content, err = nil, nil
if fetch then
    local okFetch, res, fetchErr = pcall(fetch, fetchUrl)
    if okFetch and res and type(res) == "string" and res ~= "" and not res:match("^404") and res:find("Auto Plant") then
        content = res
    else
        err = fetchErr or "Respons invalid atau kosong"
    end
end

-- Fallback jika koneksi offline atau fetch timeout di Growlauncher
if not content or content == "" then
    if LogToConsole then
        LogToConsole("`e[Boren Plant Loader] `0Fetch online dilewati / offline (" .. tostring(err or "timeout") .. "). Mencari file lokal...")
    end
    local candidatePaths = {
        "/storage/emulated/0/Android/media/launcher.powerkuy.growlauncher/ScriptLua/auto_plant.lua",
        "/storage/emulated/0/Android/media/launcher.powerkuy.growlauncher/ScriptLua/script code/auto_plant.lua",
        "/storage/emulated/0/Android/data/launcher.powerkuy.growlauncher/files/ScriptLua/auto_plant.lua",
        "/storage/emulated/0/Download/auto_plant.lua",
        "script/script code/auto_plant.lua",
        "auto_plant.lua"
    }
    for _, p in ipairs(candidatePaths) do
        local okF, fh = pcall(io.open, p, "r")
        if okF and fh then
            local text = fh:read("*a")
            fh:close()
            if text and text ~= "" then
                content = text
                if LogToConsole then
                    LogToConsole("`2[Boren Plant Loader] `0File lokal berhasil dimuat dari: " .. p)
                end
                break
            end
        end
    end
end

if content and content ~= "" then
    local loaderFn = loadstring or load
    local chunk, loadErr = loaderFn(content)
    if chunk then
        local okExec, runErr = pcall(chunk)
        if okExec then
            if LogToConsole then
                LogToConsole("`2[Boren Plant Loader] `0Auto Plant berhasil dijalankan & menu siap di kategori 'Boren Plant'!")
            end
            notifyUser("Auto Plant Siap Digunakan!")
        else
            local errMsg = "Error runtime: " .. tostring(runErr)
            if LogToConsole then LogToConsole("`4[Boren Plant Loader] `0" .. errMsg) end
            notifyUser(errMsg)
        end
    else
        local errMsg = "Error kompilasi script: " .. tostring(loadErr)
        if LogToConsole then LogToConsole("`4[Boren Plant Loader] `0" .. errMsg) end
        notifyUser(errMsg)
    end
else
    local errMsg = "Gagal memuat auto_plant.lua (koneksi offline dan file lokal tidak ditemukan)."
    if LogToConsole then LogToConsole("`4[Boren Plant Loader] `0" .. errMsg) end
    notifyUser(errMsg)
end
