# Auto Plant & Splice - Growlauncher (Boren Store)

Script otomatisasi tanam (Plant) dan kawin bibit (Splice) untuk Growlauncher Android & PC.

## Fitur Utama
1. **Pilih Seed Langsung dari Backpack & Search BP**:
   - Tombol `🎒 Pilih Seed 1 dari Tas` dan `🎒 Pilih Seed 2 dari Tas` langsung membuka daftar seed yang ada di backpack pemain.
   - Fitur pencarian bibit (Search Seed) berdasarkan nama atau ID barang di dalam tas.
   - Bot otomatis mendeteksi dan memilih bibit terbanyak di tas jika user lupa menyetel ID bibit saat start.
2. **Mode Tanam Langsung Template (Top-to-Bottom Y=0 s/d 53 Urut Kiri ke Kanan)**:
   - Penanaman langsung menyapu dari baris paling atas (Y=0) menuju ke bawah (Y=53), urut kiri ke kanan tanpa perlu pre-detection rumit.
   - Menanam di semua petak kosong yang memiliki lantai/platform di bawahnya.
   - Mendukung Mode 3 Zig-Zag (Lucifer Style) dan Mode 1 by 1 tanpa ada petak yang terlewat (zero-hole).
   - Otomatis menanam world saat ini jika antrean world kosong saat START BOT.
3. **Fitur Splice (Kawin Bibit Otomatis)**:
   - Toggle ON / OFF Splice.
   - Bot menanam Seed 1 dan langsung detik itu juga menanam Seed 2 di petak yang sama.
4. **Menu Kelola World Farm & Gudang Terpadu (Unified Dialog)**:
   - Salin semua daftar world farm ke clipboard (: / | / Nama Saja).
   - Tempel banyak world farm sekaligus (Quick Paste cerdas) dengan auto validasi format koma/titik koma/enter acak.
   - Edit nama world dan Door ID langsung di dalam dialog game.
   - Simpan dan muat antrean paten dari folder Download HP (`boren_plant_worlds.txt`).
5. **Gudang Seed Cerdas & Mode Tanpa Gudang (Zero-Storage)**:
   - Multi-world gudang seed dengan Door ID.
   - Auto restock dan auto-skip ke gudang berikutnya jika stok gudang habis.
   - Jika tidak ada gudang, bot menanam sampai seed di tas habis 0 tanpa pernah macet di Deteksi Layout.
6. **Anti-Collect & Ignore Gems**:
   - Interceptor TankPacket Type 11 mengabaikan Gems (ID 112) agar tas tidak cepat penuh.

## Cara Menggunakan Loader
Jalankan kode loader di Growlauncher untuk selalu mendapatkan pembaruan otomatis dari GitHub:
```lua
local RAW_URL = "https://raw.githubusercontent.com/rendhi69/sc_auto_plant_growlauncher/main/auto_plant.lua"
local content = fetch(RAW_URL .. "?v=" .. tostring(os.time()))
load(content)()
```
