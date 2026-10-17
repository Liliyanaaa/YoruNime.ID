-- Jalankan sekali di Supabase > SQL Editor
create table if not exists profiles(id uuid primary key references auth.users on delete cascade,email text,is_premium boolean not null default false,premium_until timestamptz,created_at timestamptz default now());
create table if not exists watch_log(id bigserial primary key,user_id uuid not null references auth.users on delete cascade,episode_key text not null,watch_date date not null default (now() at time zone 'Asia/Jakarta')::date,created_at timestamptz default now(),unique(user_id,episode_key,watch_date));
create table if not exists comments(id bigserial primary key,anime_id int not null,episode int not null,user_id uuid not null default auth.uid(),name text,rating int check(rating between 1 and 5),body text not null check(char_length(body)<=300),created_at timestamptz default now());
create table if not exists payments(id bigserial primary key,user_id uuid not null default auth.uid(),email text,amount int default 50000,status text default 'pending',created_at timestamptz default now());
create table if not exists reports(id bigserial primary key,anime_id int,episode int,server text,created_at timestamptz default now());
create table if not exists video_sources(id bigserial primary key,mal_id int not null,episode int not null,server text not null,quality text,url text not null,subtitle_url text);

alter table profiles enable row level security;alter table watch_log enable row level security;alter table comments enable row level security;
alter table payments enable row level security;alter table reports enable row level security;alter table video_sources enable row level security;

-- profiles: user hanya bisa MEMBACA miliknya. Tidak ada policy update, jadi is_premium hanya bisa diubah admin dari dashboard.
create policy p_sel on profiles for select using(auth.uid()=id);
create policy w_sel on watch_log for select using(auth.uid()=user_id);
create policy w_ins on watch_log for insert with check(auth.uid()=user_id);
create policy c_sel on comments for select using(true);
create policy c_ins on comments for insert with check(auth.uid()=user_id);
create policy y_sel on payments for select using(auth.uid()=user_id);
create policy y_ins on payments for insert with check(auth.uid()=user_id);
create policy r_ins on reports for insert with check(true);
create policy v_sel on video_sources for select using(true);

grant select on profiles,watch_log,payments to authenticated;
grant insert on watch_log,payments to authenticated;
grant select on comments,video_sources to anon,authenticated;
grant insert on comments to authenticated;
grant insert on reports to anon,authenticated;
grant usage,select on all sequences in schema public to anon,authenticated;

-- Profil otomatis dibuat saat user mendaftar
create or replace function new_profile() returns trigger language plpgsql security definer set search_path=public as $$
begin insert into profiles(id,email) values(new.id,new.email) on conflict do nothing; return new; end $$;
drop trigger if exists on_signup on auth.users;
create trigger on_signup after insert on auth.users for each row execute function new_profile();

-- Limit 5 episode/hari untuk akun gratis, dicek di server (tanggal WIB, reset 00.00)
create or replace function enforce_limit() returns trigger language plpgsql security definer set search_path=public as $$
begin
  new.watch_date := (now() at time zone 'Asia/Jakarta')::date;
  if not coalesce((select is_premium from profiles where id=new.user_id),false)
     and (select count(*) from watch_log where user_id=new.user_id and watch_date=new.watch_date)>=5
  then raise exception 'LIMIT'; end if;
  return new;
end $$;
drop trigger if exists t_limit on watch_log;
create trigger t_limit before insert on watch_log for each row execute function enforce_limit();

-- Aktifkan premium setelah cek transfer GoPay (ganti emailnya):
-- update profiles set is_premium=true, premium_until=now()+interval '30 days' where email='user@email.com';
-- update payments set status='verified' where email='user@email.com' and status='pending';

-- Contoh isi video berlisensi milikmu (server: 'Server 1' / 'Server 2 Backup' / 'Server 3 HD'):
-- insert into video_sources(mal_id,episode,server,quality,url,subtitle_url) values(52991,1,'Server 1','720','https://domainmu/ep1-720.mp4','https://domainmu/ep1-id.vtt');
