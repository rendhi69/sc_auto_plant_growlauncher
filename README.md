# Auto Plant & Splice - Growlauncher (Boren Store)

Script otomatisasi tanam (Plant) dan kawin bibit (Splice) untuk Growlauncher Android & PC.

## Fitur Utama & Pembaruan
1. **Deteksi Cerdas Seed Terakhir & Arah Tanam Otomatis (Smart Resume)**:
   - Bot mendeteksi koordinat seed terakhir yang sudah ditanam pada baris aktif.
   - Bot langsung menghampiri petak kosong di sebelahnya dan menentukan arah tanam (`Kiri -> Kanan` atau `Kanan -> Kiri`) secara otomatis tanpa harus berjalan ke ujung kanan/kiri terlebih dahulu.
   - Menghilangkan waktu tempuh sia-sia saat menyambung tanam world yang sudah terisi sebagian.
2. **Navigasi Serpentine Dinamis (S-Pattern Traversal)**:
   - Dari ujung kanan baris platform (`x >= 50`), bot langsung turun ke baris bawahnya dan menanam ke arah kiri (`Kanan -> Kiri`).
   - Dari ujung kiri baris platform (`x < 50`), bot langsung turun dan menanam ke arah kanan (`Kiri -> Kanan`).
3. **Pacing Delay Riil 180ms Terintegrasi**:
   - Delay default terset ke **180 ms** (`plant_delay` & `splice_delay`).
   - Eksekusi real delay presisi tanpa clamping / batas minimum palsu.
   - Sinkronisasi dua arah real-time antara slider UI dan input teks angka (Int).
4. **Batch Section Splicing & Auto-Recovery (Punch Sprouted Trees)**:
   - Splicing batch 3 petak sekaligus (tanam bibit 1, tunggu cooldown server, lalu timpa bibit 2).
   - Validasi kepastian splice dengan verifikasi multi-retry langsung di tempat.
   - Fitur pemulihan cerdas: jika terdeteksi bibit yang gagal splice dan telanjur bertunas, bot otomatis memukul (punch) untuk mereset petak dan menanam bibit baru.
5. **Anti False Completion saat Disconnect**:
   - Jika koneksi terputus saat proses tanam berlangsung, status world TIDAK ditandai selesai (DONE). World tetap berstatus ANTRI untuk dilanjutkan saat reconnect.
6. **Penyimpanan Daftar World & Storage Anti-Crash**:
   - Form dan list terpadu dengan sinkronisasi instan ke file teks penyimpanan (`boren_plant_worlds.txt` & `boren_plant_storage.txt`), mencegah daftar hilang saat force close, restart, atau crash.
7. **Kompatibilitas Penuh Android & PC**:
   - Bebas error `os.getenv` di Android Growlauncher dengan safe environment guards dan native file fallback.

## Cara Menggunakan
Jalankan `loader_plant.lua` pada Growlauncher untuk selalu mendapatkan versi skrip terbaru secara otomatis langsung dari GitHub.
