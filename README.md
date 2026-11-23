# Auto Plant & Splice - Growlauncher (Boren Store)

Script otomatisasi tanam (Plant) dan kawin bibit (Splice) untuk Growlauncher Android & PC.

Repository ini menyediakan **2 Versi Antarmuka (UI)** yang terpisah dan terorganisir:

---

## 1. Versi Native UI (Bawaan Growlauncher)
Tampilan terintegrasi langsung di **menu samping / drawer resmi Growlauncher**. Ringan, stabil, dan tanpa jendela melayang di layar game.

* **Folder:** `sc_plant_native/`
* **File Script Utama:** `sc_plant_native/auto_plant.lua`
* **Loader Cepat:** `loader_plant_native.lua` (Jalankan file ini untuk memuat menu Native secara otomatis dari GitHub).

---

## 2. Versi Console ImGui (Floating Window Melayang)
Tampilan berupa **jendela console ImGui semi-transparan yang melayang di atas layar game Growtopia**. Dapat digeser, ditutup, atau di-*minimize* menjadi Mini HUD ringkas saat bot bekerja.

* **Folder:** `sc_plant_console/`
* **File Script Utama:** `sc_plant_console/tab_plant.lua` + `sc_plant_console/plant_engine.lua`
* **Loader Cepat:** `loader_plant_console.lua` (Jalankan file ini untuk memuat Console ImGui secara otomatis dari GitHub).

---

## Struktur Lengkap File Repository
```text
├── loader_plant_native.lua       # Loader untuk memuat Versi Native UI
├── loader_plant_console.lua      # Loader untuk memuat Versi Console ImGui
├── auto_plant.lua                # Standalone script offline Native UI
├── sc_plant_native/              # Folder Khusus Native UI
│   ├── auto_plant.lua
│   └── loader_plant_native.lua
├── sc_plant_console/             # Folder Khusus Console ImGui
│   ├── tab_plant.lua
│   ├── plant_engine.lua
│   └── loader_plant_console.lua
├── imgui_hub/                    # Engine ImGui Hub Core
│   ├── boot.lua
│   ├── manifest.lua
│   ├── plant_engine.lua
│   ├── tab_plant.lua
│   └── theme_widgets.lua
└── component/                    # Komponen mesin zigzag & pathfinding
    └── component_plant_engine_3zigzag.lua
```

## Fitur Unggulan Engine
1. **Smart Resume**: Deteksi cerdas koordinat bibit terakhir dan menentukan arah tanam otomatis (`Kiri -> Kanan` atau `Kanan -> Kiri`).
2. **Navigasi Serpentine (S-Pattern)**: Menuruni platform secara otomatis tanpa bolak-balik kosong.
3. **Pacing Delay Riil 180ms**: Delay presisi tinggi tanpa penundaan palsu.
4. **Auto-Recovery Failed Splice**: Memukul tunas yang gagal kawin dan menanam ulang secara otomatis.
5. **Anti False Completion saat Disconnect**: Status antrean tetap terjaga saat terputus dari server.
6. **Penyimpanan World Anti-Hilang**: Terhubung ke file lokal (`boren_plant_worlds.txt` & `boren_plant_storage.txt`).
7. **Deteksi & Bypass Lock Pemain Lain**: Menghindari area yang terkunci lock orang lain secara otomatis.


## Edisi Khusus: sc_plant_dialog (100% In-Game Dialog UI)
Folder: `sc_plant_dialog/`  
Loader: `loader_plant_dialog.lua` (tersedia di root dan folder `sc_plant_dialog/`)

### Fitur Utama Edisi Dialog:
- **100% In-Game Growtopia Dialog**: Menggunakan sistem dialog asli game (`OnDialogRequest` & `action|dialog_return`). 0% ImGui, 0% Native GL Drawer, sangat ringan dan anti-crash di semua HP Android & PC.
- **Intersepsi Chat Command**: Buka menu kapan saja dengan mengetik `/plant`, `/p`, atau `/boren` di chat game.
- **Form Khusus Tambah World Saat Ini**: Mengatur Door ID dan ID benih yang akan ditanam secara interaktif langsung lewat formulir in-game.
- **Database 16.480 Item**: Pencarian benih instan berdasarkan ID angka atau nama item, otomatis konversi blok/pohon ke seed via `BOREN_ITEM_DB`.
- **Deteksi Floating Seed Pintar**: Menggunakan `getUnifiedWorldObjects` dan `isMatchingSeedID` untuk menjamin seed di world storage terdeteksi dan diambil sempurna.
