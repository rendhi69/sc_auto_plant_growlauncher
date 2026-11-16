-- ============================================================================
-- LOADER AUTO PLANT & SPLICE - BOREN STORE (AUTO-FETCH DARI GITHUB)
-- ============================================================================
-- Skrip ini otomatis mengambil dan menjalankan auto_plant.lua versi
-- terbaru dari GitHub repository: https://github.com/rendhi69/sc_auto_plant_growlauncher
-- Setiap kali ada update di GitHub, bot otomatis memakai kode terbaru tanpa perlu
-- mengganti atau copy-paste file manual lagi di Growlauncher!
-- ============================================================================

local RAW_URL = "https://raw.githubusercontent.com/rendhi69/sc_auto_plant_growlauncher/main/auto_plant.lua"

-- Parameter unik (?v=timestamp) untuk bypass CDN cache Fastly GitHub (selalu fresh)
local fetchUrl = RAW_URL .. "?v=" .. tostring(os.time())

local function notifyUser(msg)
    if sendNotification then
        pcall(sendNotification, msg)
    elseif growtopia and growtopia.notify then
        pcall(growtopia.notify, msg)
    end
end

LogToConsole("`9[Boren Store Loader] `0Menghubungkan ke GitHub (Auto Plant & Splice)...")
notifyUser("Menghubungkan ke GitHub...")

local content, err = fetch(fetchUrl)

if not content or content == "" then
    LogToConsole("`4[Loader Error] `0Gagal mendownload skrip dari GitHub: " .. tostring(err or "koneksi timeout / kosong"))
    notifyUser("Gagal load dari GitHub: " .. tostring(err or "timeout"))
    return
end

local chunk, loadErr = load(content)
if not chunk then
    LogToConsole("`4[Loader Syntax Error] `0Gagal mem-parsing skrip: " .. tostring(loadErr))
    notifyUser("Syntax error pada skrip di GitHub!")
    return
end

LogToConsole("`2[Boren Store Loader] `0Skrip Auto Plant & Splice berhasil dimuat dari GitHub!")
notifyUser("Auto Plant berhasil dimuat dari GitHub!")

-- Eksekusi skrip utama
chunk()
