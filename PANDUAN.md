<div align="center">
  <a href="https://dokploy.com">
    <img src=".github/sponsors/logo.png" alt="Dokploy - Open Source Alternative to Vercel, Heroku and Netlify." width="100%"  />
  </a>
  <br/>
  <h1>Panduan Dokploy (Fork Lokal)</h1>
  <p>Panduan lengkap dalam Bahasa Indonesia untuk membangun, menjalankan, dan men-deploy fork Dokploy ini.</p>
</div>

> Dokumen ini adalah pelengkap [`README.md`](./README.md) resmi. Berisi langkah-langkah yang **sudah disesuaikan** dengan konfigurasi tambahan pada repository ini — yaitu `docker-compose.yml`, `install.sh` yang dimodifikasi, `.env.production`/`.env.example`, dan `LICENSE_PROPRIETARY_ADDENDUM.md`.

---

## Daftar Isi

1. [Tentang Fork Ini](#1-tentang-fork-ini)
2. [Prasyarat](#2-prasyarat)
3. [Struktur Repository](#3-struktur-repository)
4. [Tiga Cara Menjalankan](#4-tiga-cara-menjalankan)
   - [4.1 Mode Pengembangan (lokal, tanpa Docker)](#41-mode-pengembangan-lokal-tanpa-docker)
   - [4.2 Mode Self-Host Sederhana (Docker Compose)](#42-mode-self-host-sederhana-docker-compose)
   - [4.3 Mode Produksi (Docker Swarm via `install.sh`)](#43-mode-produksi-docker-swarm-via-installsh)
5. [Variabel Environment](#5-variabel-environment)
6. [Operasional Sehari-hari](#6-operasional-sehari-hari)
7. [Update / Upgrade](#7-update--upgrade)
8. [Pencadangan & Pemulihan](#8-pencadangan--pemulihan)
9. [Pemecahan Masalah (Troubleshooting)](#9-pemecahan-masalah-troubleshooting)
10. [Keamanan](#10-keamanan)
11. [Lisensi](#11-lisensi)
12. [Kontribusi](#12-kontribusi)

---

## 1. Tentang Fork Ini

Fork ini menambahkan beberapa berkas tambahan di atas Dokploy upstream **tanpa mengubah berkas inti**:

| Berkas                            | Tujuan                                                                                               |
| --------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `docker-compose.yml`              | Menjalankan Dokploy + Postgres + Redis dengan satu perintah (single host, tanpa Swarm)               |
| `.env.example`                    | Template variabel environment untuk Compose                                                          |
| `.env.production`                 | Berkas minimal yang dibutuhkan `Dockerfile` saat build (`COPY .env.production ./.env`)               |
| `install.sh` (modifikasi)         | Default-nya **build dari source repo** ini, bukan pull dari Docker Hub                               |
| `LICENSE_PROPRIETARY_ADDENDUM.md` | Adendum lisensi proprietary milik **Ardan Ari Tri Wibowo / Ardantus** untuk modifikasi/karya turunan |

Lisensi upstream **tidak** disentuh:

- `LICENSE.MD` → Apache License 2.0 (Dokploy Technology, Inc.)
- `LICENSE_PROPRIETARY.md` → DSAL v1.0 (untuk konten di `/proprietary`)

---

## 2. Prasyarat

### Mode pengembangan lokal

| Tool       | Versi                         | Catatan                                                       |
| ---------- | ----------------------------- | ------------------------------------------------------------- |
| Node.js    | `^24.4.0`                     | Lihat `.nvmrc`                                                |
| pnpm       | `>=9.12.0` (target `10.22.0`) | `corepack enable && corepack prepare pnpm@10.22.0 --activate` |
| PostgreSQL | `16+`                         | Atau pakai container `postgres:16`                            |
| Docker     | `28.x`                        | Diperlukan agar fitur orkestrasi Dokploy bisa diuji           |

### Mode Docker Compose / Swarm

| Tool                  | Versi minimum                                                                      |
| --------------------- | ---------------------------------------------------------------------------------- |
| Docker Engine         | `28.5`                                                                             |
| Docker Compose plugin | v2.x                                                                               |
| OS                    | Linux (Ubuntu 22.04+ direkomendasikan). **Tidak didukung di macOS untuk produksi** |
| RAM                   | ≥ 4 GB (build pertama berat)                                                       |
| Disk                  | ≥ 20 GB lapang                                                                     |
| Port                  | `80`, `443`, `3000` harus bebas                                                    |

---

## 3. Struktur Repository

```
.
├── apps/
│   ├── api/                # API publik (REST / OpenAPI)
│   ├── dokploy/            # Aplikasi Next.js utama (UI + tRPC)
│   ├── monitoring/         # Worker monitoring resource
│   └── schedules/          # Worker job terjadwal
├── packages/
│   └── server/             # Logika inti (database, builder, deployer)
├── Dockerfile              # Image utama (multi-stage)
├── Dockerfile.cloud        # Varian untuk Dokploy Cloud
├── Dockerfile.monitoring   # Image monitoring
├── Dockerfile.schedule     # Image schedules
├── Dockerfile.server       # Image API/server
├── docker-compose.yml      # ← Dibuat oleh fork ini
├── install.sh              # ← Disesuaikan oleh fork ini
├── .env.example            # ← Dibuat oleh fork ini (untuk compose)
├── .env.production         # ← Dibuat oleh fork ini (dibutuhkan saat build)
├── LICENSE.MD              # Apache 2.0 (upstream)
├── LICENSE_PROPRIETARY.md  # DSAL (upstream)
└── LICENSE_PROPRIETARY_ADDENDUM.md  # ← Dibuat oleh fork ini
```

---

## 4. Tiga Cara Menjalankan

Pilih satu dari tiga metode berikut sesuai kebutuhan Anda.

### 4.1 Mode Pengembangan (lokal, tanpa Docker)

Cocok untuk pengembangan kode (hot-reload).

```bash
corepack enable
corepack prepare pnpm@10.22.0 --activate
pnpm install

cp apps/dokploy/.env.example apps/dokploy/.env

docker run -d --name dokploy-postgres-dev \
  -e POSTGRES_USER=dokploy \
  -e POSTGRES_DB=dokploy \
  -e POSTGRES_PASSWORD=amukds4wi9001583845717ad2 \
  -p 5432:5432 \
  postgres:16-alpine

pnpm dokploy:setup
pnpm dokploy:dev
```

Aplikasi akan tersedia di `http://localhost:3000`.

> Beberapa fitur (deploy aplikasi, manajemen Swarm, Traefik) memerlukan akses ke Docker daemon dan **tidak akan jalan penuh** di macOS dev environment. Untuk uji menyeluruh, gunakan mode 4.2.

---

### 4.2 Mode Self-Host Sederhana (Docker Compose)

Cocok untuk **mencoba Dokploy di satu VPS** atau lab lokal Linux. Menggunakan `docker-compose.yml` yang ada di repo ini.

```bash
cp .env.example .env
# Wajib: ganti BETTER_AUTH_SECRET. Contoh:
sed -i "s|^BETTER_AUTH_SECRET=.*|BETTER_AUTH_SECRET=$(openssl rand -hex 32)|" .env

docker compose up -d --build
```

Buka `http://<ip-host>:3000`.

Layanan yang dijalankan:

| Service            | Image                            | Port host | Volume                          |
| ------------------ | -------------------------------- | --------- | ------------------------------- |
| `dokploy`          | dibangun lokal dari `Dockerfile` | `3000`    | `dokploy-data` → `/etc/dokploy` |
| `dokploy-postgres` | `postgres:16-alpine`             | –         | `dokploy-postgres-database`     |
| `dokploy-redis`    | `redis:7-alpine`                 | –         | `redis-data-volume`             |

**Penting**: Container `dokploy` me-mount `/var/run/docker.sock`. Itu memberi Dokploy kemampuan mengorkestrasi container lain di host yang sama, **dan secara efektif setara dengan akses root ke host**. Jangan jalankan di mesin yang tidak Anda percayai.

> Mode ini **tidak menginisialisasi Swarm**. Sebagian fitur multi-node Dokploy mengasumsikan Swarm aktif; untuk produksi penuh, pakai metode 4.3.

---

### 4.3 Mode Produksi (Docker Swarm via `install.sh`)

Cocok untuk **server produksi** (VPS Linux). Script `install.sh` di fork ini secara default akan **membangun image dari source repository ini**, sehingga modifikasi lokal Anda ikut terbawa.

```bash
sudo bash install.sh
```

Script akan:

1. Memeriksa: root, OS Linux, port 80/443/3000 bebas, Docker terpasang (auto-install bila tidak).
2. Membangun image `dokploy/dokploy:local-<versi>` dari `Dockerfile`.
3. Inisialisasi Docker Swarm (`docker swarm init`).
4. Membuat overlay network `dokploy-network`.
5. Menyimpan password Postgres sebagai **Docker Secret** terenkripsi.
6. Menjalankan service `dokploy-postgres`, `dokploy-redis`, `dokploy`, dan container Traefik `v3.6.7`.

#### Variabel environment untuk `install.sh`

| Variabel                 | Default                | Keterangan                                                                                          |
| ------------------------ | ---------------------- | --------------------------------------------------------------------------------------------------- |
| `DOKPLOY_INSTALL_MODE`   | `build`                | `build` = bangun dari Dockerfile lokal · `registry` = pull dari Docker Hub (perilaku upstream lama) |
| `DOKPLOY_VERSION`        | auto                   | Mode build → baca `apps/dokploy/package.json`. Mode registry → deteksi rilis terbaru di GitHub      |
| `DOKPLOY_IMAGE`          | *(kosong)*             | Override penuh nama:tag image (mis. `ghcr.io/ardantus/dokploy:dev`)                                 |
| `ADVERTISE_ADDR`         | auto-detect IP private | IP yang dipakai Swarm                                                                               |
| `DOCKER_SWARM_INIT_ARGS` | *(kosong)*             | Argumen tambahan untuk `docker swarm init`, mis. `--default-addr-pool 172.20.0.0/16`                |

Contoh:

```bash
sudo DOKPLOY_INSTALL_MODE=registry bash install.sh        # perilaku upstream lama
sudo DOKPLOY_IMAGE=ghcr.io/ardantus/dokploy:dev bash install.sh
sudo ADVERTISE_ADDR=192.168.1.50 bash install.sh
```

---

## 5. Variabel Environment

Variabel berikut dipakai oleh `docker-compose.yml`. Mode `install.sh` mengekspor sebagian besar variabel ini secara otomatis.

| Variabel             | Default                       | Wajib?                   | Keterangan                                     |
| -------------------- | ----------------------------- | ------------------------ | ---------------------------------------------- |
| `NODE_ENV`           | `production`                  | ya                       | Selalu `production` untuk image                |
| `PORT`               | `3000`                        | –                        | Port HTTP aplikasi                             |
| `ADVERTISE_ADDR`     | `127.0.0.1`                   | – (Compose) / ya (Swarm) | Alamat publik yang dipakai Swarm               |
| `POSTGRES_USER`      | `dokploy`                     | –                        | User Postgres                                  |
| `POSTGRES_DB`        | `dokploy`                     | –                        | Nama database                                  |
| `POSTGRES_PASSWORD`  | default lemah                 | **ya, ganti!**           | Password Postgres (Compose)                    |
| `POSTGRES_HOST`      | `dokploy-postgres`            | –                        | Host Postgres (di-set otomatis)                |
| `POSTGRES_PORT`      | `5432`                        | –                        | Port Postgres                                  |
| `DATABASE_URL`       | dirakit dari variabel di atas | –                        | Dapat di-override langsung                     |
| `REDIS_URL`          | `redis://dokploy-redis:6379`  | –                        | URL Redis                                      |
| `BETTER_AUTH_SECRET` | placeholder                   | **ya, ganti!**           | Rahasia auth. Generate: `openssl rand -hex 32` |
| `TRAEFIK_PORT`       | `80`                          | –                        | Port HTTP Traefik di host                      |
| `TRAEFIK_SSL_PORT`   | `443`                         | –                        | Port HTTPS Traefik di host                     |
| `TRAEFIK_HTTP3_PORT` | `443`                         | –                        | Port HTTP/3 (UDP)                              |
| `TRAEFIK_VERSION`    | `3.6.7`                       | –                        | Versi Traefik                                  |

> Mode produksi (`install.sh`) menggunakan **Docker Secret** untuk password Postgres, sehingga `POSTGRES_PASSWORD_FILE=/run/secrets/postgres_password` dipakai sebagai pengganti `POSTGRES_PASSWORD`. Kode di `packages/server/src/db/constants.ts` mendukung kedua pola tersebut.

---

## 6. Operasional Sehari-hari

### Mode Compose

```bash
docker compose ps                          # status
docker compose logs -f dokploy             # log realtime
docker compose restart dokploy             # restart aplikasi
docker compose stop                        # stop semua
docker compose down                        # stop + hapus container (volume tetap)
docker compose down -v                     # ⚠️ HAPUS VOLUME (data hilang)
docker compose exec dokploy sh             # masuk ke container
```

### Mode Swarm (install.sh)

```bash
docker service ls                          # daftar service
docker service ps dokploy --no-trunc       # status replika
docker service logs -f dokploy             # log realtime
docker service update --force dokploy      # restart paksa
docker stack ps dokploy                    # status semua tugas
docker secret ls                           # daftar secret
```

### Reset password admin (mode Compose)

```bash
docker compose exec dokploy node /app/dist/reset-password.js
```

### Reset 2FA (mode Compose)

```bash
docker compose exec dokploy node /app/dist/reset-2fa.js
```

---

## 7. Update / Upgrade

### Mode Compose

```bash
git pull                                   # ambil perubahan terbaru
docker compose pull                        # update image dasar (postgres/redis)
docker compose up -d --build               # rebuild & restart Dokploy
```

### Mode Swarm

```bash
git pull
sudo bash install.sh update                # rebuild + service update (mode build)
# atau
sudo DOKPLOY_INSTALL_MODE=registry bash install.sh update   # pull dari Docker Hub
```

---

## 8. Pencadangan & Pemulihan

### Backup database (Compose)

```bash
docker compose exec -T dokploy-postgres \
  pg_dump -U dokploy -d dokploy --format=custom \
  > "backup-dokploy-$(date +%F).dump"
```

### Backup direktori state

Direktori `/etc/dokploy` (mode Swarm) atau volume `dokploy-data` (mode Compose) berisi konfigurasi Traefik, kunci SSH, kredensial registry, dll. **Sertakan dalam backup**.

```bash
docker run --rm \
  -v dokploy_dokploy-data:/data \
  -v "$PWD":/backup \
  alpine tar czf /backup/dokploy-data-$(date +%F).tgz -C /data .
```

### Restore

```bash
docker compose exec -T dokploy-postgres \
  pg_restore -U dokploy -d dokploy --clean --if-exists < backup-dokploy-XXXX.dump
```

---

## 9. Pemecahan Masalah (Troubleshooting)

| Gejala                                                       | Penyebab umum                                   | Solusi                                                                                                                   |
| ------------------------------------------------------------ | ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `docker compose build` gagal di tahap `COPY .env.production` | File tidak ada                                  | Sudah disediakan di repo. Jika hilang, buat ulang minimal: `printf 'NODE_ENV=production\nPORT=3000\n' > .env.production` |
| Build Next.js OOM (out-of-memory)                            | RAM host kurang                                 | Naikkan RAM ≥ 4 GB, atau set `NODE_OPTIONS=--max-old-space-size=4096` saat build                                         |
| `port 80/443/3000 already in use`                            | Layanan lain memakai port                       | `sudo ss -tulnp \| grep -E ':(80\|443\|3000) '` lalu hentikan layanan terkait                                            |
| Healthcheck `dokploy` selalu gagal                           | Postgres belum siap / `DATABASE_URL` salah      | `docker compose logs dokploy` & `dokploy-postgres`. Periksa `BETTER_AUTH_SECRET` ter-set                                 |
| Login gagal / cookie invalid                                 | `BETTER_AUTH_SECRET` masih default atau berubah | Set ke nilai stabil & rahasia, lalu restart                                                                              |
| Traefik tidak bisa start (mode install.sh)                   | Direktori `/etc/dokploy/traefik/` belum ada     | Pastikan `mkdir -p /etc/dokploy && chmod 777 /etc/dokploy` sudah dijalankan                                              |
| LXC/Proxmox: service tidak saling kenal                      | Mode endpoint default                           | Script otomatis menambah `--endpoint-mode dnsrr` saat mendeteksi LXC                                                     |
| Mode build di Swarm tetap pull image                         | Tag image bertabrakan dgn registry              | Pastikan tag default `dokploy/dokploy:local-<versi>` digunakan, atau set `DOKPLOY_IMAGE` ke nama unik                    |

### Mengumpulkan diagnosa cepat

```bash
docker compose ps
docker compose logs --tail=200 dokploy
docker compose logs --tail=50 dokploy-postgres dokploy-redis
docker version
docker info | grep -E 'Server Version|Operating System|Total Memory'
```

---

## 10. Keamanan

- **Ganti** semua nilai default sebelum produksi: `POSTGRES_PASSWORD`, `BETTER_AUTH_SECRET`.
- Untuk produksi, prioritaskan **mode Swarm** (`install.sh`) karena password Postgres disimpan sebagai Docker Secret, bukan environment variable di `docker inspect`.
- Container Dokploy memegang `/var/run/docker.sock` → setara root host. **Batasi akses SSH** ke server tersebut.
- Aktifkan firewall (UFW/nftables); hanya buka `22`, `80`, `443`, dan opsional `3000` (idealnya `3000` hanya boleh diakses lewat tunnel/VPN setelah setup).
- Aktifkan **HTTPS** lewat Traefik secepat mungkin (Let's Encrypt) — diatur dari UI Dokploy.
- Lihat juga [`SECURITY.md`](./SECURITY.md) untuk pelaporan kerentanan.

---

## 11. Lisensi

Repository ini berada di bawah **tiga lapis lisensi** yang **berlaku bersamaan**:

1. **[Apache License 2.0](./LICENSE.MD)** — lisensi utama untuk kode upstream Dokploy (Dokploy Technology, Inc.).
2. **[Dokploy Source Available License (DSAL) v1.0](./LICENSE_PROPRIETARY.md)** — berlaku untuk konten di dalam direktori `/proprietary` milik Dokploy Technology, Inc.
3. **[Proprietary License Addendum](./LICENSE_PROPRIETARY_ADDENDUM.md)** — adendum proprietary milik **Ardan Ari Tri Wibowo / Ardantus** (`ardantus@gmail.com`) yang **hanya** berlaku untuk modifikasi/karya turunan oleh Licensor; **tidak** menggantikan dua lisensi di atas.

> Saat terjadi konflik antara adendum dan lisensi upstream, **lisensi upstream yang berlaku** untuk berkas terkait.

---

## 12. Kontribusi

- Lihat [`CONTRIBUTING.md`](./CONTRIBUTING.md) (upstream).
- Untuk diskusi komunitas: [Discord Dokploy](https://discord.gg/2tBnJ3jDJc).
- Dokumentasi resmi: [docs.dokploy.com](https://docs.dokploy.com).
- Untuk pertanyaan terkait fork/adendum ini: `ardantus@gmail.com`.

---

<div align="center">
  <sub>Panduan ini dibuat sebagai pelengkap khusus fork. Berkas inti, perilaku, dan perjanjian lisensi upstream tetap mengikuti repository resmi Dokploy.</sub>
</div>
