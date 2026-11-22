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
   - Sinkronisasi dua arah real-time antara slider UI dan input teks angka.
4. **Batch Section Splicing & Auto-Recovery (Punch Sprouted Trees)**:
   - Splicing batch 3 petak sekaligus (tanam bibit 1, tunggu cooldown server, lalu timpa bibit 2).
   - Validasi kepastian splice dengan verifikasi multi-retry langsung di tempat.
   - Fitur pemulihan cerdas: jika terdeteksi bibit yang gagal splice dan telanjur bertunas, bot otomatis memukul (punch) untuk mereset petak dan menanam bibit baru.
5. **Anti False Completion saat Disconnect**:
   - Jika koneksi terputus saat proses tanam berlangsung, status world TIDAK ditandai selesai (DONE). World tetap berstatus ANTRI untuk dilanjutkan saat reconnect.
6. **Penyimpanan Daftar World & Storage Otomatis & Anti-Hilang**:
   - ID Door kini tersimpan sempurna saat menambahkan World Farm maupun Storage World.
   - Sinkronisasi instan dua arah ke file penyimpanan fisik di memori HP (`boren_plant_worlds.txt` & `boren_plant_storage.txt`), mencegah daftar world hilang meskipun Growlauncher di-force close atau crash.
7. **Pendeteksian & Pengabaian Otomatis Area Lock Orang Lain**:
   - Bot otomatis memindai area perlindungan kunci milik pemain lain (Small Lock, Big Lock, Huge Lock, Builder's Lock, dan World Lock) saat masuk ke world.
   - Area yang dilindungi lock orang lain secara cerdas dilewati dan tidak akan dipaksa tanam maupun dipukul.
   - Dilengkapi sistem *reactive failure blacklist*: jika sebuah petak gagal ditanam sebanyak 2x akibat proteksi lock server, petak otomatis di-blacklist sehingga bot langsung melanjutkan ke petak berikutnya tanpa stuck.
8. **Kompatibilitas Penuh Android & PC**:
   - Bebas error `os.getenv` di Android Growlauncher dengan safe environment guards dan native file fallback.

## Cara Menggunakan
1. **Via Loader**: Jalankan `loader_plant.lua` pada Growlauncher untuk memuat script secara otomatis dari GitHub.
2. **Via Standalone File**: Jalankan langsung `auto_plant.lua` di Script Manager Growlauncher (100% offline, bebas ketergantungan jaringan).
