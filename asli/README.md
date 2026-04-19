# Arsip referensi — modul **proprietary** (DSAL)

Folder `asli/` menyimpan **salinan struktur path repository** untuk kode yang sebelumnya berada di:

- `apps/dokploy/components/proprietary/`
- `apps/dokploy/server/api/routers/proprietary/`
- `packages/server/src/services/proprietary/`

## Struktur di dalam `asli/`

```
asli/
├── README.md                    ← berkas ini
├── apps/dokploy/components/proprietary/   … UI, gate enterprise, SSO, whitelabel, audit, roles
├── apps/dokploy/server/api/routers/proprietary/ … router tRPC terkait
└── packages/server/src/services/proprietary/    … license-key, sso helpers, audit-log service
```

Path relatif **setelah** `asli/` mengikuti path asli di monorepo, sehingga Anda dapat memetakan `asli/apps/...` → `apps/...` dengan mudah.

## Hubungan dengan path aktif (build)

Saat ini **path yang dipakai TypeScript / Next.js / pnpm** tetap yang standar:

- `apps/dokploy/components/proprietary/`
- `apps/dokploy/server/api/routers/proprietary/`
- `packages/server/src/services/proprietary/`

Isinya **disamakan** dengan arsip di `asli/` (salinan operasional) agar proyek tetap dapat di-build dan dijalankan.

**Alur kerja yang disarankan saat Anda membuat ulang tanpa menyalin DSAL:**

1. Implementasikan modul baru Anda di lokasi **baru** (mis. `apps/dokploy/components/hosting/` atau `packages/server/src/services/hosting/`).
2. Alihkan impor dari `@/components/proprietary/...` ke modul baru Anda.
3. Hapus folder `.../proprietary/` di **path aktif** saat tidak ada lagi referensi.
4. Pertahankan folder `asli/` sebagai **referensi saja** sampai Anda yakin tidak membutuhkannya; setelah itu bisa dihapus dari repo (atau dipindahkan ke arsip zip di luar git).

> **Catatan lisensi:** isi di bawah `asli/` tetap karya yang dilindungi sesuai [`LICENSE_PROPRIETARY.md`](../LICENSE_PROPRIETARY.md) (DSAL) untuk bagian yang memang berada di `/proprietary` upstream. Memindahkan lokasi fisik di disk **tidak** mengubah hak cipta atau syarat DSAL.
