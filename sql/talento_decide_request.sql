-- Review and run in a staging database before production rollout.
-- Invoker privileges preserve RLS; production RLS must also be hardened separately.
create or replace function public.talento_decide_request(p_id uuid,p_status text)
returns text language plpgsql security invoker set search_path = '' as $$
declare
  r public.requests%rowtype;
  actor_role text;
  target public.profiles%rowtype;
  choice text;
  kind text;
  clock_time text;
  att_id uuid;
begin
  if auth.uid() is null or p_status is null or p_status not in ('Disetujui','Ditolak') then
    raise exception 'Aksi tidak valid';
  end if;
  select * into r from public.requests where id=p_id for update;
  if not found then raise exception 'Pengajuan tidak ditemukan'; end if;
  select role into actor_role from public.profiles where id=auth.uid();
  if not found then raise exception 'Profil atasan tidak ditemukan'; end if;
  select * into target from public.profiles where id=r.user_id for update;
  if not found or (actor_role is distinct from 'superadmin' and target.supervisor_id is distinct from auth.uid()) then
    raise exception 'Tidak berwenang menyetujui pengajuan ini';
  end if;
  if r.status is distinct from 'Pending' then
    if r.status=p_status then return r.status; end if;
    raise exception 'Pengajuan sudah diproses';
  end if;
  choice := coalesce(r.shift_choice,'');
  if p_status='Disetujui' then
    if r.type in ('cuti','izin') and (choice like '%CT%' or choice like '%Cuti Tahunan%') then
      update public.profiles set saldo_cuti_tahunan=greatest(0,coalesce(saldo_cuti_tahunan,0)-1) where id=r.user_id;
      if not found then raise exception 'Saldo gagal diperbarui'; end if;
    end if;
    if r.type in ('cuti','izin') and (choice like '%CKOMP%' or choice like '%Cuti Kompensasi%') then
      update public.profiles set saldo_cuti_kompensasi=greatest(0,coalesce(saldo_cuti_kompensasi,0)-1) where id=r.user_id;
      if not found then raise exception 'Saldo gagal diperbarui'; end if;
    end if;
    if r.type='lembur' and choice like '%Saldo Cuti Kompensasi%' then
      update public.profiles set saldo_cuti_kompensasi=coalesce(saldo_cuti_kompensasi,0)+1 where id=r.user_id;
      if not found then raise exception 'Saldo gagal diperbarui'; end if;
    end if;
    if r.type='claim_absen' then
      kind := split_part(choice,' ',1);
      clock_time := substring(choice from '\(([0-9]{2}:[0-9]{2})\)');
      if r.date is null or kind not in ('Masuk','Pulang') or clock_time is null or clock_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
        raise exception 'Tanggal atau jam klaim tidak valid';
      end if;
      select id into att_id from public.attendances where user_id=r.user_id and tipe=kind
        and (created_at at time zone 'Asia/Jakarta')::date=r.date
        order by created_at,id limit 1 for update;
      if found then
        update public.attendances set jam_masuk=clock_time,alamat='[KLAIM DISETUJUI] '||coalesce(r.description,'Klaim Presensi'),status='Hadir' where id=att_id;
        if not found then raise exception 'Presensi gagal diperbarui'; end if;
      else
        insert into public.attendances(user_id,jam_masuk,alamat,tipe,status,created_at)
        values(r.user_id,clock_time,'[KLAIM DISETUJUI] '||coalesce(r.description,'Klaim Presensi'),kind,'Hadir',
          (r.date+clock_time::time) at time zone 'Asia/Jakarta');
      end if;
    end if;
  end if;
  update public.requests set status=p_status where id=p_id and status='Pending';
  if not found then raise exception 'Status gagal diperbarui'; end if;
  return p_status;
end;
$$;
revoke all on function public.talento_decide_request(uuid,text) from public,anon;
grant execute on function public.talento_decide_request(uuid,text) to authenticated;
