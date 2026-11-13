# Auto Plant & Splice - Growlauncher (Boren Store)

Script otomatisasi tanam (Plant) dan kawin bibit (Splice) untuk Growlauncher Android & PC.

## Fitur Utama
1. **Item Picker Native (Sama Seperti SC DF)**:
   - Menggunakan item picker native Growlauncher: tinggal pegang/pilih item langsung dari tas (backpack) tanpa tebak-tebak ID ngawur.
   - Didukung input ID manual jika ingin mengetik ID bibit secara langsung.
2. **Mode Tanam 3 Zig-Zag Rapat & Anti Bolong (Zero Hole)**:
   - Bot berdiri tepat di titik pijakan (X tengah) dan menanam 3 petak sekaligus (kiri - tengah - kanan) dalam radius 1 tile.
   - Dilengkapi verifikasi seketika di tempat: jika ada petak yang belum tertanam akibat lag/packet drop, bot langsung menanam ulang sebelum melangkah 3 tile maju.
   - Menjamin seluruh deretan platform tertanam rata tanpa ada bolong seperti pada foto.
3. **Penyapuan Template dari Paling Atas (Y=0 s/d 53 Urut Kiri ke Kanan)**:
   - Langsung menanam dari baris lantai paling atas ke bawah tanpa terjebak deteksi layout.
   - Otomatis menanam world saat ini jika daftar antrean world kosong saat START BOT.
4. **Fitur Splice (Kawin Bibit Otomatis)**:
   - Toggle ON / OFF Splice.
   - Bot menanam Seed 1 lalu langsung detik itu juga menanam Seed 2 di petak yang sama.
5. **Menu Kelola World Farm & Gudang Terpadu (Unified Dialog)**:
   - Salin semua daftar world farm ke clipboard (: / | / Nama Saja).
   - Tempel banyak world farm sekaligus (Quick Paste cerdas) dengan auto validasi format koma/titik koma/enter acak.
   - Edit nama world dan Door ID langsung di dalam dialog game.
   - Simpan dan muat antrean paten dari folder Download HP (`boren_plant_worlds.txt`).
6. **Gudang Seed Cerdas & Mode Tanpa Gudang (Zero-Storage)**:
   - Multi-world gudang seed dengan Door ID.
   - Auto restock dan auto-skip ke gudang berikutnya jika stok gudang habis.
   - Jika tidak ada gudang, bot menanam sampai seed di tas habis 0 tanpa pernah macet.
7. **Anti-Collect & Ignore Gems**:
   - Interceptor TankPacket Type 11 mengabaikan Gems (ID 112) agar tas tidak cepat penuh.

## Cara Menggunakan Loader
Jalankan kode loader di Growlauncher untuk selalu mendapatkan pembaruan otomatis dari GitHub:
```lua
local RAW_URL = "https://raw.githubusercontent.com/rendhi69/sc_auto_plant_growlauncher/main/auto_plant.lua"
local content = fetch(RAW_URL .. "?v=" .. tostring(os.time()))
load(content)()
```
