-- ============================================================================
-- BOREN STORE - AUTO-GENERATED FEATURE MANIFEST (GL MODULAR LOADER)
-- File: imgui_hub/manifest.lua
-- Catatan: File ini otomatis diperbarui saat push berdasarkan modul mod_*.lua
--          yang memiliki META.type == "boren_gl_feature" dan enabled == true.
-- ============================================================================

return {
    schema = "boren_gl_manifest_v1",
    core = {
        { key = "conn",  path = "imgui_hub/conn_guard.lua",   required = false },
        { key = "plant", path = "imgui_hub/plant_engine.lua", required = true },
        { key = "ui",    path = "imgui_hub/tab_plant.lua",    required = true },
    },
    features = {
        { id = "harvest", label = "Harvest", order = 15, path = "imgui_hub/mod_harvest.lua" },
        { id = "transfer", label = "Transfer", order = 18, path = "imgui_hub/mod_transfer.lua" },
        { id = "dirt_farm", label = "Dirt Farm", order = 20, path = "imgui_hub/mod_dirt_farm.lua" },
        { id = "build_soil", label = "Build Soil", order = 30, path = "imgui_hub/mod_soil_builder.lua" },
        { id = "buy_pack", label = "Buy Pack", order = 40, path = "imgui_hub/mod_buy_pack.lua" },
        { id = "chemsynth", label = "Chemsynth", order = 45, path = "imgui_hub/mod_chemsynth.lua" },
        { id = "database_id", label = "Database ID", order = 50, path = "imgui_hub/mod_database_id.lua" },
    },
}
