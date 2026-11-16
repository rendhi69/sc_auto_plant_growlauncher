# Auto Plant & Splice - Growlauncher (Boren Store)

Script otomatisasi tanam (Plant) dan kawin bibit (Splice) untuk Growlauncher Android & PC.

## Fitur Utama & Pembaruan
1. **Navigasi Serpentine Dinamis (S-Pattern Traversal)**:
   - Dari ujung kanan baris platform (`x >= 50`), bot langsung turun ke baris bawahnya dan menanam ke arah kiri (`Kanan -> Kiri`).
   - Dari ujung kiri baris platform (`x < 50`), bot langsung turun dan menanam ke arah kanan (`Kiri -> Kanan`).
   - Mengeliminasi gerakan bolak-balik yang membuang waktu dan menghemat durasi penanaman hingga 50%.
2. **Pacing Delay Riil 180ms Terintegrasi**:
   - Delay default terset ke **180 ms** (`plant_delay` & `splice_delay`).
   - Eksekusi real delay presisi tanpa clamping / batas minimum palsu.
   - Sinkronisasi dua arah real-time antara slider UI dan input teks angka (Int).
3. **Batch Section Splicing & Auto-Recovery (Punch Sprouted Trees)**:
   - Splicing batch 3 petak sekaligus (tanam bibit 1, tunggu cooldown server, lalu timpa bibit 2).
   - Validasi kepastian splice dengan verifikasi multi-retry langsung di tempat.
   - Fitur pemulihan cerdas: jika terdeteksi bibit yang gagal splice dan telanjur bertunas, bot otomatis memukul (punch) untuk mereset petak dan menanam bibit baru.
4. **Anti False Completion saat Disconnect**:
   - Jika koneksi terputus saat proses tanam berlangsung, status world TIDAK ditandai selesai (DONE). World tetap berstatus ANTRI untuk dilanjutkan saat reconnect.
5. **Penyimpanan Daftar World & Storage Anti-Crash**:
   - Form dan list terpadu dengan sinkronisasi instan ke file teks penyimpanan (`boren_plant_worlds.txt` & `boren_plant_storage.txt`), mencegah daftar hilang saat force close, restart, atau crash.
6. **Dukungan Modular Component**:
   - Tersedia modul komponen siap pakai di folder `component/` untuk arsitektur skrip modular.

## Cara Menggunakan
Jalankan `loader_plant.lua` pada Growlauncher untuk selalu mendapatkan versi skrip terbaru secara otomatis langsung dari GitHub.
