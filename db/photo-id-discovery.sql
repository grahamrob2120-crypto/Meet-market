-- Photo ID review replaces the unavailable SMS gate.
drop trigger if exists dating_likes_verified_phone on public.dating_likes;
create or replace function private.dating_ready(uid uuid) returns boolean
language sql stable security definer set search_path='' as $$
select auth.uid() is not null and exists(
select 1 from public.dating_members m
join public.dating_id_submissions i on i.user_id=m.user_id and i.status='approved'
join auth.users u on u.id=m.user_id and u.email_confirmed_at is not null
where m.user_id=uid and nullif(m.photo_path,'') is not null and nullif(m.photo_path_2,'') is not null)
$$;
revoke all on function private.dating_ready(uuid) from public,anon;
grant execute on function private.dating_ready(uuid) to authenticated,service_role;
create or replace function private.dating_discover()
returns table(user_id uuid,display_name text,bio text,city text,photo_path text,age integer)
language sql stable security definer set search_path='' as $$
select m.user_id,m.display_name,m.bio,m.city,m.photo_path,extract(year from age(m.birth_date))::integer
from public.dating_members m
where auth.uid() is not null and m.user_id<>auth.uid()
and private.dating_is_active(auth.uid()) and private.dating_ready(auth.uid())
and private.dating_is_active(m.user_id) and private.dating_ready(m.user_id)
and private.dating_can_interact(m.user_id) order by m.created_at desc limit 100
$$;
create or replace function private.dating_nearby()
returns table(user_id uuid,display_name text,bio text,city text,photo_path text,age integer,distance_km integer)
language sql stable security definer set search_path='' as $$
select d.user_id,d.display_name,d.bio,d.city,d.photo_path,d.age,
case when me.latitude is not null and me.longitude is not null and them.latitude is not null and them.longitude is not null
then round(6371*acos(least(1.0,greatest(-1.0,cos(radians(me.latitude))*cos(radians(them.latitude))*cos(radians(them.longitude-me.longitude))+sin(radians(me.latitude))*sin(radians(them.latitude))))))::integer
else null end
from private.dating_discover() d
join public.dating_members me on me.user_id=auth.uid()
join public.dating_members them on them.user_id=d.user_id
order by 7 nulls last,d.display_name
$$;
revoke all on function private.dating_nearby() from public,anon;
grant execute on function private.dating_nearby() to authenticated,service_role;
create or replace function public.dating_nearby()
returns table(user_id uuid,display_name text,bio text,city text,photo_path text,age integer,distance_km integer)
language sql stable set search_path='' as $$select * from private.dating_nearby()$$;
revoke all on function public.dating_nearby() from public,anon;
grant execute on function public.dating_nearby() to authenticated,service_role;
create policy dating_likes_reviewed on public.dating_likes as restrictive for insert to authenticated
with check(private.dating_ready(user_id) and private.dating_ready(target_id));
create policy dating_messages_reviewed on public.dating_messages as restrictive for insert to authenticated
with check(private.dating_ready(sender_id) and private.dating_ready(recipient_id));
