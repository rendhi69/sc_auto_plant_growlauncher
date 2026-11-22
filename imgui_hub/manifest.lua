-- ============================================================================
-- BOREN STORE - FEATURE MANIFEST (AUTO PLANT CONSOLE)
-- File: imgui_hub/manifest.lua
-- ============================================================================

return {
    schema = "boren_gl_manifest_v1",
    core = {
        { key = "conn",  path = "imgui_hub/conn_guard.lua",   required = false },
        { key = "plant", path = "imgui_hub/plant_engine.lua", required = true },
        { key = "ui",    path = "imgui_hub/tab_plant.lua",    required = true },
    },
    features = {},
}
