-- Onboarding registration permissions, using protected admin allowlist.
-- Data calon pengguna tidak dapat dibaca oleh publik.
create table if not exists public.talento_onboarding_admins (
 id uuid primary key references auth.users(id) on delete cascade
);
alter table public.talento_onboarding_admins enable row level security;
revoke all on public.talento_onboarding_admins from anon, authenticated;
grant select on public.talento_onboarding_admins to authenticated;
create policy "Admin melihat entri miliknya"
on public.talento_onboarding_admins for select to authenticated
using (id = (select auth.uid()));
insert into public.talento_onboarding_admins(id)
select id from public.profiles where role = 'superadmin'
on conflict (id) do nothing;

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
-- Allowlist ini hanya dapat diubah oleh pemegang akses database tepercaya.
create policy "Super Admin membaca pengajuan"
on public.talento_onboarding_requests for select to authenticated
using (exists (select 1 from public.talento_onboarding_admins a where a.id = (select auth.uid())));
create policy "Super Admin memproses pengajuan"
on public.talento_onboarding_requests for update to authenticated
using (exists (select 1 from public.talento_onboarding_admins a where a.id = (select auth.uid())))
with check (exists (select 1 from public.talento_onboarding_admins a where a.id = (select auth.uid())));
