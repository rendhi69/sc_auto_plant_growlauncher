# Auto Plant & Splice - Growlauncher (Boren Store)

Script otomatisasi tanam (Plant) dan kawin bibit (Splice) untuk Growlauncher Android & PC.

## Fitur Utama
1. **Mode Tanam 3 Zig-Zag (Lucifer Style) & 1 by 1**:
   - Menanam 3 petak sekaligus sepanjang jalur platform baris farm layaknya fitur Lucifer, atau 1 per 1 petak dengan navigasi aman.
2. **Fitur Splice (Kawin Bibit Otomatis)**:
   - Toggle ON / OFF Splice.
   - Pilih Seed 1 (Base) dan Seed 2 (Splice) via Item Picker atau Input ID manual. Bot langsung menimpa Seed 2 di petak yang sama saat Splice aktif.
3. **Menu Kelola World Farm Terpadu (Unified Dialog)**:
   - Salin semua daftar world farm ke clipboard dengan pilihan format (: / | / Nama Saja).
   - Tempel banyak world farm sekaligus (Quick Paste cerdas) dengan pemisah koma, titik koma, spasi, enter, baris baru, kutip, dll.
   - Edit nama world dan Door ID langsung di dalam dialog game.
   - Hapus satuan antrean world farm.
   - Simpan dan muat otomatis ke folder Download HP (`/storage/emulated/0/Download/boren_plant_worlds.txt`).
4. **Gudang Seed Cerdas (Storage Restock & Auto-Skip)**:
   - Daftar gudang multi-world.
   - Bot otomatis terbang/warp ke gudang saat seed di tas habis.
   - Auto-skip ke gudang berikutnya jika stok seed di gudang saat ini kosong.
5. **Anti-Collect & Ignore Gems**:
   - Hook interceptor TankPacket Type 11 otomatis mengabaikan Gems (ID 112) agar tas tidak cepat penuh dan kecepatan tanam maksimal.

## Cara Menggunakan Loader
Jalankan kode loader di Growlauncher untuk selalu mendapatkan pembaruan otomatis dari GitHub:
```lua
local RAW_URL = "https://raw.githubusercontent.com/rendhi69/sc_auto_plant_growlauncher/main/auto_plant.lua"
local content = fetch(RAW_URL .. "?v=" .. tostring(os.time()))
load(content)()
```
