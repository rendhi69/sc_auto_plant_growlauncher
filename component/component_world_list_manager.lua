-- ============================================================================
-- COMPONENT: REUSABLE WORLD LIST MANAGER UNTUK GROWLAUNCHER
-- ============================================================================
-- File: component_world_list_manager.lua
-- Lokasi: script/component/component_world_list_manager.lua
--
-- KEGUNAAN:
--   Komponen serbaguna (plug-and-play) untuk mengelola daftar world pada
--   skrip GrowLauncher apapun (World Farm Antrean, Gudang Alat, Gudang Seed,
--   Gudang Block, dsb) tanpa perlu menulis ulang atau debug dari awal.
--
-- FITUR LENGKAP:
--   1. Form Input UI: Kolom Nama World & Door ID, tombol [+ Tambah], [+ World Saat Ini],
--      [Kelola Massal / Dialog], dan [Kosongkan List].
--   2. Display List Native: Sinkronisasi langsung ke addDisplayList() GrowLauncher.
--   3. Dialog Manager Lengkap:
--      - Salin semua world (format Titik Dua ':', Garis '|', atau Hanya Nama).
--      - Tempel / Tambah Massal (bebas format comma, newline, spasi, tab, pipe, colon).
--      - Checkbox Replace (timpa semua antrean atau tambahkan ke yang sudah ada).
--      - Tombol Edit per item (nama world & door ID) dan tombol Hapus per item.
--   4. Ekspor / Impor File TXT: Simpan ke file teks dan muat dari file teks.
--   5. Persistensi Preferences Android Safe: Tersimpan otomatis sebagai flat string
--      (WORLD|DOOR|STATUS) sehingga anti-corrupt dan aman saat game restart.
--   6. Queue Engine: Fungsi getNextPending(), markDone(), resetQueue(), dan count().
-- ============================================================================

local BOREN_WORLD_MANAGER = {}
BOREN_WORLD_MANAGER.__index = BOREN_WORLD_MANAGER

-- Helper internal: membersihkan string
local function trimStr(s)
    return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

-- Helper internal: JSON encoder sederhana bila modul JSON belum ada
local function simpleJsonEncode(tbl)
    if json and json.encode then
        local ok, res = pcall(json.encode, tbl)
        if ok and res then return res end
    end
    if jsonEncode then
        local ok, res = pcall(jsonEncode, tbl)
        if ok and res then return res end
    end
    local function esc(s)
        return '"' .. tostring(s):gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r') .. '"'
    end
    local function enc(v)
        local t = type(v)
        if t == "string" then return esc(v)
        elseif t == "number" or t == "boolean" then return tostring(v)
        elseif t == "table" then
            local isArr = (#v > 0) or (next(v) == nil)
            local parts = {}
            if isArr then
                for i = 1, #v do parts[i] = enc(v[i]) end
                return "[" .. table.concat(parts, ",") .. "]"
            else
                for k, val in pairs(v) do
                    table.insert(parts, esc(k) .. ":" .. enc(val))
                end
                return "{" .. table.concat(parts, ",") .. "}"
            end
        end
        return "null"
    end
    return enc(tbl)
end

-- Helper internal: pengiriman dialog ke GrowLauncher
local function safeSendRawDialog(dText)
    if not dText or dText == "" then return false end
    if growtopia and type(growtopia.sendDialog) == "function" then
        local ok = pcall(growtopia.sendDialog, dText)
        if ok then return true end
    end
    if sendVariant then
        local ok = pcall(sendVariant, { v1 = "OnDialogRequest", v2 = dText })
        if ok then return true end
    end
    if sendDialog then
        pcall(sendDialog, dText)
        return true
    end
    return false
end

-- ============================================================================
-- KONSTRUKTOR / FACTORY
-- ============================================================================
-- Parameter opts:
--   id              : String ID unik (misal: "farm", "tool_store", "seed_store")
--   label           : Label yang tampil di UI (misal: "World Farm", "Gudang Alat")
--   pref_key        : Key penyimpanan di preferences (misal: "farm_world_list_str")
--   show_status     : Boolean (true = ada status [ANTRI]/[PROSES]/[DONE], false = list gudang biasa)
--   default_file    : Nama file backup txt (misal: "farm_worlds.txt")
-- ============================================================================
function BOREN_WORLD_MANAGER.new(opts)
    opts = opts or {}
    local self = setmetatable({}, BOREN_WORLD_MANAGER)

    self.id           = opts.id or "world_queue"
    self.label        = opts.label or "World List"
    self.pref_key     = opts.pref_key or (self.id .. "_str")
    self.show_status  = (opts.show_status == true)
    self.default_file = opts.default_file or (self.id .. "_list.txt")

    -- Alias UI GrowLauncher
    self.alias_input_w   = opts.alias_input_w or (self.id .. "_in_w")
    self.alias_input_d   = opts.alias_input_d or (self.id .. "_in_d")
    self.alias_btn_add   = opts.alias_btn_add or (self.id .. "_btn_add")
    self.alias_btn_cur   = opts.alias_btn_cur or (self.id .. "_btn_cur")
    self.alias_btn_mgr   = opts.alias_btn_mgr or (self.id .. "_btn_mgr")
    self.alias_btn_clr   = opts.alias_btn_clr or (self.id .. "_btn_clr")
    self.alias_disp_list = opts.alias_disp_list or (self.id .. "_display_list")
    self.alias_file_in   = opts.alias_file_in or (self.id .. "_file_in")
    self.alias_btn_save  = opts.alias_btn_save or (self.id .. "_btn_save_file")
    self.alias_btn_load  = opts.alias_btn_load or (self.id .. "_btn_load_file")

    -- Nama Dialog Growtopia
    self.dialog_mgr_name  = "boren_mgr_" .. self.id
    self.dialog_edit_name = "boren_edit_" .. self.id

    -- Buffer Input Sementara
    self.buf_world = ""
    self.buf_door  = ""
    self.active_world = ""

    -- Data List
    self.list = {}
    self:loadFromPrefs()

    return self
end

-- ============================================================================
-- 1. PARSING & VALIDASI TOKEN / BATCH STRING
-- ============================================================================
function BOREN_WORLD_MANAGER:parseToken(rawToken, defDoor)
    local clean = trimStr(rawToken)
    if clean == "" or clean:sub(1, 1) == "#" then return nil end

    local body = clean
    local isDone = false
    local statusTag = nil

    local b1, tag1 = clean:match("^(.-)[|:](DONE)$")
    if not b1 then b1, tag1 = clean:match("^(.-)[|:](done)$") end
    if not b1 then b1, tag1 = clean:match("^(.-)[|:](PROSES)$") end
    if not b1 then b1, tag1 = clean:match("^(.-)[|:](ANTRI)$") end
    if not b1 then b1, tag1 = clean:match("^(.-)|([01])$") end
    if b1 and tag1 then
        body = b1
        statusTag = tag1:upper()
        isDone = (statusTag == "DONE" or statusTag == "1")
    end

    local wName, dId = body:match("^([^|:]+)[|:](.*)$")
    if not wName then
        wName = body
        dId = defDoor or ""
    end
    wName = trimStr(wName):upper()
    dId = trimStr(dId)
    if wName == "" or wName == "EXIT" or wName == "0" then return nil end

    local validName = wName:match("^([%w_]+)$")
    if not validName or #validName < 1 or #validName > 24 then return nil end

    return {
        name = validName:upper(),
        door = dId,
        done = isDone,
        status = isDone and "DONE" or (statusTag or "ANTRI")
    }
end

function BOREN_WORLD_MANAGER:parseBatch(rawText)
    local results = {}
    if type(rawText) ~= "string" or rawText == "" then return results end
    local cleaned = rawText:gsub("[\"\'%[%]%(%)]", " "):gsub("\t", " ")
    for part in cleaned:gmatch("[^\r\n;,]+") do
        local token = trimStr(part):gsub("%s*[:|]%s*", ":")
        local entry = self:parseToken(token, "")
        if entry then
            table.insert(results, entry)
        end
    end
    return results
end

-- ============================================================================
-- 2. PERSISTENSI PREFERENCES (SAFE SERIALIZATION)
-- ============================================================================
function BOREN_WORLD_MANAGER:saveToPrefs()
    if not saved or not saved.set then return end
    pcall(function()
        local parts = {}
        for _, e in ipairs(self.list) do
            if e and e.name and e.name ~= "" then
                local flag = e.done and "1" or "0"
                table.insert(parts, tostring(e.name) .. "|" .. tostring(e.door or "") .. "|" .. flag)
            end
        end
        saved:set(self.pref_key, table.concat(parts, ";"))
        if saved.save then saved:save() end
    end)
end

function BOREN_WORLD_MANAGER:loadFromPrefs()
    self.list = {}
    if not saved or not saved.get then return end
    pcall(function()
        local raw = saved:get(self.pref_key, "")
        if type(raw) == "string" and raw ~= "" then
            for token in raw:gmatch("[^;\r\n]+") do
                local entry = self:parseToken(token, "")
                if entry then
                    table.insert(self.list, entry)
                end
            end
        end
    end)
end

-- ============================================================================
-- 3. MANIPULASI DATA LIST (ADD / EDIT / DELETE / CLEAR)
-- ============================================================================
function BOREN_WORLD_MANAGER:find(worldName)
    local target = trimStr(worldName):upper()
    if target == "" then return nil, nil end
    for i, e in ipairs(self.list) do
        if e.name:upper() == target then
            return e, i
        end
    end
    return nil, nil
end

function BOREN_WORLD_MANAGER:add(worldName, doorID)
    local parsed = self:parseBatch(worldName)
    local defDoor = trimStr(doorID)
    if #parsed == 0 and trimStr(worldName) ~= "" then
        local single = self:parseToken(worldName, defDoor)
        if single then table.insert(parsed, single) end
    end

    local addedCount = 0
    for _, item in ipairs(parsed) do
        local finalDoor = (item.door and item.door ~= "") and item.door or defDoor
        local existing, idx = self:find(item.name)
        if not existing then
            table.insert(self.list, {
                name = item.name,
                door = finalDoor,
                done = item.done or false,
                status = item.status or "ANTRI"
            })
            addedCount = addedCount + 1
        else
            existing.door = finalDoor
        end
    end

    if addedCount > 0 then
        self:saveToPrefs()
        self:updateDisplayList()
    end
    return addedCount
end

function BOREN_WORLD_MANAGER:edit(idx, newName, newDoor)
    idx = math.floor(tonumber(idx) or 0)
    if idx < 1 or idx > #self.list then return false, "Indeks tidak valid!" end
    local entry = self.list[idx]
    local cleanName = trimStr(newName):upper()
    local cleanDoor = trimStr(newDoor)

    if cleanName == "" then return false, "Nama world tidak boleh kosong!" end
    if cleanName:find("[:|]") then
        local p = self:parseToken(cleanName, cleanDoor)
        if p then
            cleanName = p.name
            cleanDoor = p.door
        end
    end

    entry.name = cleanName
    entry.door = cleanDoor
    self:saveToPrefs()
    self:updateDisplayList()
    return true, string.format("World #%d diubah -> %s [Door: %s]", idx, cleanName, cleanDoor ~= "" and cleanDoor or "-")
end

function BOREN_WORLD_MANAGER:delete(idx)
    idx = math.floor(tonumber(idx) or 0)
    if idx < 1 or idx > #self.list then return false, "Indeks tidak valid!" end
    local removed = table.remove(self.list, idx)
    self:saveToPrefs()
    self:updateDisplayList()
    return true, string.format("World #%d (%s) dihapus!", idx, removed and removed.name or "")
end

function BOREN_WORLD_MANAGER:clear()
    self.list = {}
    self:saveToPrefs()
    self:updateDisplayList()
    return true
end

function BOREN_WORLD_MANAGER:replaceBatch(rawText)
    local parsed = self:parseBatch(rawText)
    self.list = {}
    local seen = {}
    local added = 0
    for _, item in ipairs(parsed) do
        if not seen[item.name] then
            seen[item.name] = true
            table.insert(self.list, {
                name = item.name,
                door = item.door or "",
                done = item.done or false,
                status = item.status or "ANTRI"
            })
            added = added + 1
        end
    end
    self:saveToPrefs()
    self:updateDisplayList()
    return added
end

-- ============================================================================
-- 4. QUEUE ENGINE (NEXT / STATUS / DONE)
-- ============================================================================
function BOREN_WORLD_MANAGER:getNextPending()
    for idx, entry in ipairs(self.list) do
        if not entry.done and entry.status ~= "DONE" then
            entry.status = "PROSES"
            self.active_world = entry.name
            self:updateDisplayList()
            return entry.name, entry.door or "", idx
        end
    end
    return nil, nil, nil
end

function BOREN_WORLD_MANAGER:markDone(worldName, isDone)
    if isDone == nil then isDone = true end
    local entry = self:find(worldName)
    if entry then
        entry.done = isDone
        entry.status = isDone and "DONE" or "ANTRI"
        self:saveToPrefs()
        self:updateDisplayList()
        return true
    end
    return false
end

function BOREN_WORLD_MANAGER:resetQueue()
    for _, e in ipairs(self.list) do
        e.done = false
        e.status = "ANTRI"
    end
    self:saveToPrefs()
    self:updateDisplayList()
end

function BOREN_WORLD_MANAGER:hasPending()
    for _, e in ipairs(self.list) do
        if not e.done and e.status ~= "DONE" then
            return true
        end
    end
    return false
end

function BOREN_WORLD_MANAGER:count()
    local total = #self.list
    local done = 0
    for _, e in ipairs(self.list) do
        if e.done or e.status == "DONE" then
            done = done + 1
        end
    end
    return total, done, total - done
end

function BOREN_WORLD_MANAGER:getAll()
    return self.list
end

-- ============================================================================
-- 5. NATIVE DISPLAY LIST BUILDER & SYNC
-- ============================================================================
function BOREN_WORLD_MANAGER:buildDisplayRows()
    local rows = {}
    for i, e in ipairs(self.list) do
        local doorStr = (e.door and e.door ~= "") and ("Door: " .. e.door) or "White Door"
        if self.show_status then
            local tag = e.done and "DONE" or ((self.active_world == e.name or e.status == "PROSES") and "PROSES" or "ANTRI")
            table.insert(rows, { string.format("%d. %s [%s]", i, e.name, tag), doorStr })
        else
            table.insert(rows, { string.format("%d. %s", i, e.name), doorStr })
        end
    end
    if #rows == 0 then
        table.insert(rows, { self.label .. " masih kosong", "Ketik Nama World lalu klik + Tambah" })
    end
    return rows
end

function BOREN_WORLD_MANAGER:updateDisplayList()
    if not editValue then return end
    pcall(editValue, self.alias_disp_list, simpleJsonEncode(self:buildDisplayRows()))
end

-- ============================================================================
-- 6. ATTACH TO GROWLAUNCHER UI PAGE (PLUG AND PLAY)
-- ============================================================================
function BOREN_WORLD_MANAGER:attachToUI(uiTab, includeFileTools)
    if not uiTab then return end

    uiTab:addLabel(self.label .. ":")
    uiTab:addInputString("Nama " .. self.label, self.buf_world, "World", "WORLD1", "Public", self.alias_input_w)
    uiTab:addInputString("Door ID (Opsional)", self.buf_door, "Door ID", "Kosong = White Door", "DoorFront", self.alias_input_d)
    uiTab:addButton("➕ Tambah ke " .. self.label, self.alias_btn_add)
    uiTab:addButton("🌐 Tambah World Saat Ini", self.alias_btn_cur)
    uiTab:addButton("📋 Kelola & Paste Massal", self.alias_btn_mgr)
    uiTab:addButton("🗑️ Kosongkan " .. self.label, self.alias_btn_clr)

    if includeFileTools then
        uiTab:addInputString("File Backup (.txt)", self.default_file, "Nama File", "worlds.txt", "Drive", self.alias_file_in)
        uiTab:addButton("📥 Simpan ke File TXT", self.alias_btn_save)
        uiTab:addButton("📤 Muat dari File TXT", self.alias_btn_load)
    end

    uiTab:addDisplayList("Daftar " .. self.label, "Default", self.alias_disp_list)
end

-- ============================================================================
-- 7. DIALOG MANAGER & EDIT DIALOG
-- ============================================================================
function BOREN_WORLD_MANAGER:openManagerDialog(fmt)
    fmt = fmt or "colon"
    local copyLines = {}
    for _, e in ipairs(self.list) do
        local d = (e.door and e.door ~= "") and e.door or ""
        if fmt == "colon" then
            table.insert(copyLines, d ~= "" and (e.name .. ":" .. d) or e.name)
        elseif fmt == "pipe" then
            table.insert(copyLines, d ~= "" and (e.name .. "|" .. d) or e.name)
        else
            table.insert(copyLines, e.name)
        end
    end
    local rawBoxText = table.concat(copyLines, ", ")

    local dLines = {
        "set_default_color|`o",
        "add_quick_exit|",
        string.format("add_label_with_icon|big|`2Kelola %s (%d)``|left|242|", self.label, #self.list),
        string.format("add_textbox|`oSalin daftar, tempel massal, atau edit/hapus entri %s.|left|", self.label),
        "add_spacer|small|",

        -- Bagian 1: Salin
        "add_textbox|`2[1. Salin Semua ke Clipboard]|left|",
        string.format("add_text_input|boren_cp_box|Salin Antrean|%s|9999|", rawBoxText),
        "add_button|boren_btn_fmt_colon|Format Titik Dua (:)|noflags|0|0|",
        "add_button|boren_btn_fmt_pipe|Format Garis (|)|noflags|0|0|",
        "add_button|boren_btn_fmt_name|Hanya Nama World|noflags|0|0|",
        "add_spacer|small|",

        -- Bagian 2: Tempel Massal
        "add_textbox|`2[2. Tempel / Tambah Massal]|left|",
        "add_textbox|`eFormat: WORLD:DOOR atau WORLD|DOOR atau WORLD. Bebas koma/enter.|left|",
        "add_text_input|boren_paste_raw|Tempel di sini:||9999|",
        "add_checkbox|boren_paste_replace|Ganti seluruh daftar (Replace)|0|",
        "add_button|boren_submit_paste|`2+ Tempel / Tambah Sekarang|noflags|0|0|",
        "add_spacer|small|",

        -- Bagian 3: Daftar Saat Ini
        string.format("add_textbox|`2[3. Daftar Saat Ini (%d World)]|left|", #self.list)
    }

    if #self.list == 0 then
        table.insert(dLines, "add_textbox|`4(Daftar masih kosong. Silakan tempel di atas!)|left|")
    else
        for i, e in ipairs(self.list) do
            local doorStr = (e.door and e.door ~= "") and e.door or "-"
            if self.show_status then
                local tag = e.done and "`2[DONE]" or ((self.active_world == e.name or e.status == "PROSES") and "`6[PROSES]" or "`9[ANTRI]")
                table.insert(dLines, string.format("add_textbox|`w%d. `9%s `o[Door: %s] %s|left|", i, e.name, doorStr, tag))
            else
                table.insert(dLines, string.format("add_textbox|`w%d. `9%s `o[Door: %s]|left|", i, e.name, doorStr))
            end
            table.insert(dLines, string.format("add_button|boren_edit_%d|Edit|noflags|0|0|", i))
            table.insert(dLines, string.format("add_button|boren_del_%d|Hapus|noflags|0|0|", i))
            table.insert(dLines, "add_spacer|small|")
        end
    end

    table.insert(dLines, string.format("end_dialog|%s|Tutup||", self.dialog_mgr_name))
    return safeSendRawDialog(table.concat(dLines, "\n"))
end

function BOREN_WORLD_MANAGER:openEditDialog(idx)
    idx = math.floor(tonumber(idx) or 0)
    local entry = self.list[idx]
    if not entry then return end

    local dLines = {
        "set_default_color|`o",
        "add_quick_exit|",
        string.format("add_label_with_icon|big|`wEdit %s #%d: %s``|left|242|", self.label, idx, entry.name),
        "add_spacer|small|",
        string.format("add_text_input|edit_name|Nama World:|%s|32|", entry.name),
        string.format("add_text_input|edit_door|Door ID:|%s|32|", entry.door or ""),
        "add_spacer|small|",
        "add_button|save_entry_edit|`2Simpan Perubahan|noflags|0|0|",
        "add_button|del_entry_edit|`4Hapus Entri Ini|noflags|0|0|",
        string.format("end_dialog|%s_%d|Batal||", self.dialog_edit_name, idx),
    }
    safeSendRawDialog(table.concat(dLines, "\n"))
end

-- ============================================================================
-- 8. EVENT HANDLER DISPATCHER (ONVALUE & PACKET 2 DIALOG RETURN)
-- ============================================================================
function BOREN_WORLD_MANAGER:handleUIValue(name, value)
    name = tostring(name or "")
    if name == self.alias_input_w then
        self.buf_world = trimStr(value):upper()
        return true
    elseif name == self.alias_input_d then
        self.buf_door = trimStr(value)
        return true
    elseif name == self.alias_file_in then
        self.default_file = trimStr(value)
        return true
    elseif name == self.alias_btn_add then
        local rawW = self.buf_world
        if rawW == "" and readGLString then
            rawW = readGLString(self.alias_input_w, "")
        end
        local rawD = self.buf_door
        if rawD == "" and readGLString then
            rawD = readGLString(self.alias_input_d, "")
        end
        local added = self:add(rawW, rawD)
        if added > 0 then
            self.buf_world = ""
            if editValue then pcall(editValue, self.alias_input_w, "") end
            if sendNotification then
                pcall(sendNotification, string.format("%d %s ditambahkan! (Total: %d)", added, self.label, #self.list))
            end
        else
            if sendNotification then pcall(sendNotification, "Isi Nama World terlebih dahulu!") end
        end
        return true
    elseif name == self.alias_btn_cur then
        local curW = ""
        if getCurrentWorldName then
            local ok, w = pcall(getCurrentWorldName)
            if ok and w then curW = tostring(w):upper() end
        elseif getWorldNameSafe then
            curW = tostring(getWorldNameSafe()):upper()
        end
        if curW ~= "" and curW ~= "EXIT" and curW ~= "START" then
            local rawD = self.buf_door
            if rawD == "" and readGLString then rawD = readGLString(self.alias_input_d, "") end
            local added = self:add(curW, rawD)
            if added > 0 then
                if sendNotification then pcall(sendNotification, "World aktif masuk ke " .. self.label .. ": " .. curW) end
            else
                if sendNotification then pcall(sendNotification, "World sudah terdaftar!") end
            end
        else
            if sendNotification then pcall(sendNotification, "Masuk ke world dulu sebelum klik + World Saat Ini!") end
        end
        return true
    elseif name == self.alias_btn_mgr or name == self.alias_disp_list then
        self:openManagerDialog()
        return true
    elseif name == self.alias_btn_clr then
        self:clear()
        if sendNotification then pcall(sendNotification, self.label .. " dikosongkan!") end
        return true
    elseif name == self.alias_btn_save then
        local lines = {}
        for _, e in ipairs(self.list) do
            local d = (e.door and e.door ~= "") and e.door or ""
            table.insert(lines, d ~= "" and (e.name .. ":" .. d) or e.name)
        end
        if writeFile then
            pcall(writeFile, self.default_file, table.concat(lines, "\n"))
            if sendNotification then
                pcall(sendNotification, string.format("%d %s disimpan ke %s", #self.list, self.label, self.default_file))
            end
        end
        return true
    elseif name == self.alias_btn_load then
        if readFile then
            local ok, content = pcall(readFile, self.default_file)
            if ok and content and content ~= "" then
                local added = self:add(content, "")
                if sendNotification then
                    pcall(sendNotification, string.format("%d %s dimuat dari %s!", added, self.label, self.default_file))
                end
            else
                if sendNotification then pcall(sendNotification, "Gagal membaca file: " .. self.default_file) end
            end
        end
        return true
    end
    return false
end

function BOREN_WORLD_MANAGER:handleDialogPacket(pkt)
    if type(pkt) ~= "string" or not pkt:find("action|dialog_return", 1, true) then
        return false
    end

    local dName = pkt:match("dialog_name|([^|\r\n]+)") or ""
    local btn = pkt:match("buttonClicked|([^|\r\n]+)") or ""

    -- 1. Main Manager Dialog
    if dName == self.dialog_mgr_name then
        local editIdx = btn:match("^boren_edit_(%d+)$")
        local delIdx = btn:match("^boren_del_(%d+)$")

        if btn == "boren_btn_fmt_colon" then
            self:openManagerDialog("colon")
            return true
        elseif btn == "boren_btn_fmt_pipe" then
            self:openManagerDialog("pipe")
            return true
        elseif btn == "boren_btn_fmt_name" then
            self:openManagerDialog("name_only")
            return true
        elseif btn == "boren_submit_paste" then
            local raw = pkt:match("boren_paste_raw|(.-)\nboren_paste_replace|")
                or pkt:match("boren_paste_raw|(.-)\nbuttonClicked|")
                or pkt:match("boren_paste_raw|(.*)$") or ""
            local isReplace = (pkt:find("boren_paste_replace|1", 1, true) ~= nil)
            local added = isReplace and self:replaceBatch(raw) or self:add(raw, "")
            if sendNotification then
                pcall(sendNotification, string.format("%d %s dimasukkan! (Total: %d)", added, self.label, #self.list))
            end
            self:openManagerDialog()
            return true
        elseif delIdx then
            local _, msg = self:delete(tonumber(delIdx))
            if sendNotification then pcall(sendNotification, msg) end
            self:openManagerDialog()
            return true
        elseif editIdx then
            self:openEditDialog(tonumber(editIdx))
            return true
        end
        return true
    end

    -- 2. Edit Entry Dialog
    local editTargetIdx = dName:match("^" .. self.dialog_edit_name .. "_(%d+)$")
    if editTargetIdx then
        local idx = tonumber(editTargetIdx)
        if btn == "del_entry_edit" then
            local _, msg = self:delete(idx)
            if sendNotification then pcall(sendNotification, msg) end
        elseif btn == "save_entry_edit" or pkt:find("edit_name|", 1, true) then
            local newName = pkt:match("edit_name|([^|\r\n]+)") or ""
            local newDoor = pkt:match("edit_door|([^|\r\n]+)") or ""
            local _, msg = self:edit(idx, newName, newDoor)
            if sendNotification then pcall(sendNotification, msg) end
        end
        self:openManagerDialog()
        return true
    end

    return false
end

-- Daftarkan ke Global agar bisa dipakai langsung
_G.BOREN_WORLD_MANAGER = BOREN_WORLD_MANAGER
return BOREN_WORLD_MANAGER
