begin;
-- One entitlement trigger, rather than three conflicting guards.
drop trigger dating_entitlement_guard on public.dating_members;
drop trigger dating_guard_member_fields on public.dating_members;
drop trigger dating_lock_entitlements_trigger on public.dating_members;
create or replace function private.dating_lock_entitlements() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='INSERT' then
  select coalesce(email_confirmed_at,created_at)+interval '4 hours' into new.trial_ends_at from auth.users where id=new.user_id;
  new.paid_until:=null; new.created_at:=now();
 else
  new.trial_ends_at:=old.trial_ends_at; new.created_at:=old.created_at;
  if coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb->>'role' is distinct from 'service_role' and coalesce(current_setting('request.jwt.claim.role',true),'') <> 'service_role' then new.paid_until:=old.paid_until; end if;
 end if;
 return new;
end $$;
revoke all on function private.dating_lock_entitlements() from public,anon,authenticated;
create trigger dating_entitlement_guard before insert or update on public.dating_members for each row execute function private.dating_lock_entitlements();
alter policy dating_members_insert on public.dating_members with check ((select auth.uid())=user_id and paid_until is null);
alter policy dating_members_read on public.dating_members using ((select auth.uid())=user_id);
revoke truncate,references,trigger,delete on public.dating_members from authenticated;
alter table public.dating_members add column photo_path text;
grant update(photo_path) on public.dating_members to authenticated;
create table public.dating_blocks(user_id uuid references auth.users on delete cascade not null,target_id uuid references auth.users on delete cascade not null,created_at timestamptz not null default now(),primary key(user_id,target_id),check(user_id<>target_id));
create table public.dating_reports(id bigint generated always as identity primary key,user_id uuid references auth.users on delete cascade not null,target_id uuid references auth.users on delete cascade not null,reason text not null check(length(reason) between 3 and 1000),created_at timestamptz not null default now());
alter table public.dating_blocks enable row level security;
alter table public.dating_reports enable row level security;
revoke all on public.dating_blocks,public.dating_reports from anon,authenticated;
grant select,insert,delete on public.dating_blocks to authenticated;
grant insert on public.dating_reports to authenticated;
create policy blocks_read on public.dating_blocks for select to authenticated using (user_id=(select auth.uid()));
create policy blocks_insert on public.dating_blocks for insert to authenticated with check(user_id=(select auth.uid()));
create policy blocks_delete on public.dating_blocks for delete to authenticated using(user_id=(select auth.uid()));
create policy reports_insert on public.dating_reports for insert to authenticated with check(user_id=(select auth.uid()) and target_id<>user_id);
create function private.dating_can_interact(other uuid) returns boolean language sql stable security definer set search_path='' as $$ select auth.uid() is not null and not exists(select 1 from public.dating_blocks where (user_id=auth.uid() and target_id=other) or (target_id=auth.uid() and user_id=other)) $$;
revoke all on function private.dating_can_interact(uuid) from public,anon;
grant execute on function private.dating_can_interact(uuid) to authenticated;
create policy likes_not_blocked on public.dating_likes as restrictive for all to authenticated using(private.dating_can_interact(case when user_id=auth.uid() then target_id else user_id end)) with check(private.dating_can_interact(target_id));
create policy messages_not_blocked on public.dating_messages as restrictive for all to authenticated using(private.dating_can_interact(case when sender_id=auth.uid() then recipient_id else sender_id end)) with check(private.dating_can_interact(recipient_id));
-- Discovery deliberately returns no birth dates, billing fields or emails.
create function private.dating_discover() returns table(user_id uuid,display_name text,bio text,city text,photo_path text,age integer) language sql stable security definer set search_path='' as $$ select m.user_id,m.display_name,m.bio,m.city,m.photo_path,extract(year from age(m.birth_date))::integer from public.dating_members m where auth.uid() is not null and m.user_id<>auth.uid() and private.dating_is_active(auth.uid()) and private.dating_is_active(m.user_id) and private.dating_can_interact(m.user_id) order by m.created_at desc limit 100 $$;
revoke all on function private.dating_discover() from public,anon;
grant execute on function private.dating_discover() to authenticated;
create function public.dating_discover() returns table(user_id uuid,display_name text,bio text,city text,photo_path text,age integer) language sql stable security invoker set search_path='' as $$ select * from private.dating_discover() $$;
revoke all on function public.dating_discover() from public,anon;
grant execute on function public.dating_discover() to authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('dating-photos','dating-photos',false,5242880,array['image/jpeg','image/png','image/webp']);
create policy dating_photo_insert on storage.objects for insert to authenticated with check(bucket_id='dating-photos' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy dating_photo_read on storage.objects for select to authenticated using(bucket_id='dating-photos' and ((storage.foldername(name))[1]=(select auth.uid())::text or (private.dating_is_active(auth.uid()) and exists(select 1 from public.dating_discover() m where m.photo_path=name))));
create policy dating_photo_delete on storage.objects for delete to authenticated using(bucket_id='dating-photos' and (storage.foldername(name))[1]=(select auth.uid())::text);
commit;
