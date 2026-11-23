-- Terapkan setelah review sebelum halaman onboarding dipublikasikan.
-- Data calon pengguna tidak dapat dibaca oleh publik.
create table if not exists public.talento_onboarding_requests (
  id uuid primary key default gen_random_uuid(),
  nama text not null check (char_length(trim(nama)) between 2 and 150),
  telepon text not null check (char_length(trim(telepon)) between 8 and 25),
  email text not null check (char_length(trim(email)) between 5 and 254),
  unit_kerja text not null check (char_length(trim(unit_kerja)) between 2 and 150),
  join_date date not null,
  status text not null default 'Menunggu' check (status in ('Menunggu','Diproses','Selesai','Ditolak')),
  created_at timestamptz not null default now(),
  processed_at timestamptz
);
create index if not exists talento_onboarding_requests_status_idx on public.talento_onboarding_requests(status,created_at desc);
alter table public.talento_onboarding_requests enable row level security;
revoke all on public.talento_onboarding_requests from anon, authenticated;
grant insert (nama,telepon,email,unit_kerja,join_date) on public.talento_onboarding_requests to anon;
grant select, update on public.talento_onboarding_requests to authenticated;
create policy "Calon pengguna dapat mengirim pendaftaran"
on public.talento_onboarding_requests for insert to anon
with check (status = 'Menunggu' and processed_at is null);
-- Kewenangan didasarkan pada kolom role di database, bukan user_metadata.
-- Kebijakan berikut mengasumsikan pengguna dapat membaca profil miliknya.
create policy "Super Admin membaca pengajuan"
on public.talento_onboarding_requests for select to authenticated
using (exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'superadmin'));
create policy "Super Admin memproses pengajuan"
on public.talento_onboarding_requests for update to authenticated
using (exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'superadmin'))
with check (exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'superadmin'));
