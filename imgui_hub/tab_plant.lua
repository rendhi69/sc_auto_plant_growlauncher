-- ============================================================================
-- BOREN HUB IMGUI - TAB PLANT UI MODULE (1:1 LAYOUT SEPERTI REFERENSI)
-- File: imgui_hub/tab_plant.lua
-- ============================================================================

local TabPlant = {
    id    = "plant",
    label = "Plant",
}

local addInputBuf = ""

local function notify(msg)
    if sendNotification then
        pcall(sendNotification, msg)
    end
end

function TabPlant.render(HUB)
    local W = HUB.widgets
    local E = HUB.plant
    if not W or not E then
        ImGui.Text("Modul Plant belum siap.")
        return
    end

    local avail = ImGui.GetContentRegionAvail and ImGui.GetContentRegionAvail() or { x = 460, y = 320 }
    local availW = (type(avail) == "table" or type(avail) == "userdata") and (avail.x or 460) or 460

    -- ========================================================================
    -- BARIS 1: Enable [Toggle]  |  Loop [Toggle]
    -- ========================================================================
    if ImGui.AlignTextToFramePadding then ImGui.AlignTextToFramePadding() end
    ImGui.Text("Enable")
    ImGui.SameLine(math.max(120, math.floor(availW * 0.40)))
    local chEn, newEn = W.toggleSwitch("plant_enable", E.STATE.enabled)
    if chEn then
        if newEn then
            E.start()
        else
            E.stop()
        end
    end

    ImGui.SameLine()
    W.textColored(W.COLORS.textMuted, " | ")
    ImGui.SameLine()
    ImGui.Text("Loop")
    ImGui.SameLine(math.max(260, availW - 52))
    local chLp, newLp = W.toggleSwitch("plant_loop", E.CFG.loop_enabled)
    if chLp then
        E.CFG.loop_enabled = newLp
        E.saveData()
    end

    -- ========================================================================
    -- BARIS 2: [ Seed Storage [Required] ]  [ Remove Inaccessible ]
    -- ========================================================================
    local btnRemW = 148
    local storInputW = math.max(120, availW - btnRemW - 8)
    if ImGui.SetNextItemWidth then ImGui.SetNextItemWidth(storInputW) end
    local chStor, newStor = W.inputTextHint("##plant_storage", "Seed Storage [Required]", E.CFG.storage_raw, 256)
    if chStor then
        E.CFG.storage_raw = newStor
        E.saveData()
    end

    ImGui.SameLine()
    if ImGui.Button("Remove Inaccessible", W.vec2(btnRemW, 0)) then
        local removed = E.removeInaccessible()
        notify("Dihapus " .. tostring(removed) .. " world inaccessible.")
    end

    -- ========================================================================
    -- BAGIAN TENGAH: TABEL 5 KOLOM (Name | Door ID | Seed ID | Splice ID | Status)
    -- ========================================================================
    local bottomBarH = 34
    local tableH = math.max(120, ((avail.y or 300) - 66 - bottomBarH))
    local tableFlags = W.getTableFlags()
    local spanFlag = W.getSelectableSpanFlag()

    if ImGui.BeginTable and ImGui.BeginTable("##plant_world_table", 5, tableFlags, W.vec2(0, tableH)) then
        if ImGui.TableSetupScrollFreeze then
            pcall(ImGui.TableSetupScrollFreeze, 0, 1)
        end
        ImGui.TableSetupColumn("Name",      0, 1.4)
        ImGui.TableSetupColumn("Door ID",   0, 0.85)
        ImGui.TableSetupColumn("Seed ID",   0, 0.75)
        ImGui.TableSetupColumn("Splice ID", 0, 0.75)
        ImGui.TableSetupColumn("Status",    0, 1.05)
        ImGui.TableHeadersRow()

        for i, row in ipairs(E.STATE.rows) do
            ImGui.TableNextRow()
            ImGui.TableNextColumn()

            local isSel = (E.STATE.selected_idx == i)
            local rowLabel = tostring(row.name or "") .. "##row_" .. tostring(i)
            local clicked = false
            if ImGui.Selectable then
                local okS, resS = pcall(ImGui.Selectable, rowLabel, isSel, spanFlag)
                if okS and resS then clicked = true end
            else
                ImGui.Text(tostring(row.name or ""))
            end
            if clicked then
                E.STATE.selected_idx = isSel and 0 or i
            end

            ImGui.TableNextColumn()
            ImGui.Text(row.door ~= "" and tostring(row.door) or "-")

            ImGui.TableNextColumn()
            ImGui.Text(tostring(tonumber(row.seed_id) or 0))

            ImGui.TableNextColumn()
            local sp = tonumber(row.splice_id) or 0
            ImGui.Text(sp > 0 and tostring(sp) or "-")

            ImGui.TableNextColumn()
            W.textColored(W.statusColor(row.status), tostring(row.status or "Ready"))
        end

        ImGui.EndTable()
    end

    -- ========================================================================
    -- BARIS BAWAH: [ Name:ID:SeedID:SpliceID ] [ + ] [ - ] [ Import ] [ Export ] [ Reset Status ]
    -- ========================================================================
    local fixedBtnsW = 24 + 24 + 56 + 56 + 92 + (6 * 5)
    local addInputW = math.max(110, availW - fixedBtnsW)
    if ImGui.SetNextItemWidth then ImGui.SetNextItemWidth(addInputW) end
    local chAdd, newAdd = W.inputTextHint("##plant_add_line", "Name:ID:SeedID:SpliceID", addInputBuf, 256)
    if chAdd then
        addInputBuf = newAdd
    end

    ImGui.SameLine()
    if ImGui.Button("+##plant_add", W.vec2(24, 0)) then
        local parsed = E.parseRowLine(addInputBuf)
        if parsed then
            table.insert(E.STATE.rows, parsed)
            addInputBuf = ""
            E.saveData()
            E.addLog("[+] Ditambahkan: " .. E.formatRowLine(parsed))
        else
            notify("Format salah! Gunakan Name:ID:SeedID:SpliceID")
        end
    end

    ImGui.SameLine()
    if ImGui.Button("-##plant_del", W.vec2(24, 0)) then
        local idx = E.STATE.selected_idx
        if idx < 1 or idx > #E.STATE.rows then
            idx = #E.STATE.rows
        end
        if idx >= 1 and idx <= #E.STATE.rows then
            local rem = table.remove(E.STATE.rows, idx)
            E.STATE.selected_idx = 0
            E.saveData()
            E.addLog("[-] Dihapus: " .. tostring(rem and rem.name or ""))
        end
    end

    ImGui.SameLine()
    if ImGui.Button("Import", W.vec2(56, 0)) then
        local clip = ""
        if ImGui.GetClipboardText then
            local okC, resC = pcall(ImGui.GetClipboardText)
            if okC and type(resC) == "string" then clip = resC end
        end
        if clip == "" then
            notify("Clipboard kosong! Salin daftar Name:ID:SeedID:SpliceID terlebih dahulu.")
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
                E.addLog(string.format("[Import] Berhasil mengimpor %d baris dari clipboard.", added))
                notify("Berhasil import " .. tostring(added) .. " world!")
            else
                notify("Tidak ada baris valid di clipboard.")
            end
        end
    end

    ImGui.SameLine()
    if ImGui.Button("Export", W.vec2(56, 0)) then
        local out = {}
        for _, row in ipairs(E.STATE.rows) do
            table.insert(out, E.formatRowLine(row))
        end
        local textOut = table.concat(out, "\n")
        if ImGui.SetClipboardText then
            pcall(ImGui.SetClipboardText, textOut)
            E.addLog(string.format("[Export] %d baris disalin ke clipboard.", #out))
            notify("Exported " .. tostring(#out) .. " world ke clipboard!")
        end
    end

    ImGui.SameLine()
    if ImGui.Button("Reset Status", W.vec2(92, 0)) then
        E.resetAllStatus()
        notify("Semua status di-reset ke Ready.")
    end
end

return TabPlant
