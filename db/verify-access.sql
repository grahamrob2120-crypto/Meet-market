begin;
insert into auth.users(id,email,created_at,email_confirmed_at) values ('00000000-0000-4000-8000-000000000001','meet-market-test-a@example.invalid',now(),now()),('00000000-0000-4000-8000-000000000002','meet-market-test-b@example.invalid',now(),now());
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
insert into public.dating_members(user_id,display_name,birth_date) values(auth.uid(),'Test A','1990-01-01');
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
insert into public.dating_members(user_id,display_name,birth_date) values(auth.uid(),'Test B','1990-01-01');
insert into public.dating_likes(user_id,target_id) values(auth.uid(),'00000000-0000-4000-8000-000000000001');
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
do $$ begin
 if (select count(*) from public.dating_members)<>1 then raise exception 'Private profile data leaked'; end if;
 if (select count(*) from public.dating_discover())<>1 then raise exception 'Discovery failed'; end if;
 begin insert into public.dating_messages(sender_id,recipient_id,body) values(auth.uid(),'00000000-0000-4000-8000-000000000002','No mutual match'); raise exception 'Unmatched message accepted'; exception when insufficient_privilege then null; end;
end $$;
insert into public.dating_likes(user_id,target_id) values(auth.uid(),'00000000-0000-4000-8000-000000000002');
insert into public.dating_messages(sender_id,recipient_id,body) values(auth.uid(),'00000000-0000-4000-8000-000000000002','Mutual match works');
insert into public.dating_blocks(user_id,target_id) values(auth.uid(),'00000000-0000-4000-8000-000000000002');
do $$ begin
 if (select count(*) from public.dating_discover())<>0 then raise exception 'Blocked member visible'; end if;
 if (select count(*) from public.dating_messages)<>0 then raise exception 'Blocked messages visible'; end if;
 begin insert into public.dating_messages(sender_id,recipient_id,body) values(auth.uid(),'00000000-0000-4000-8000-000000000002','Blocked'); raise exception 'Blocked message accepted'; exception when insufficient_privilege then null; end;
 begin update public.dating_members set paid_until=now()+interval '1 year' where user_id=auth.uid(); raise exception 'Client entitlement update accepted'; exception when insufficient_privilege then null; end;
end $$;
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select set_config('request.jwt.claim.role','',true);
select public.dating_redeem_verified_capture('00000000-0000-4000-8000-000000000001','TEST-ROLLBACK-CAPTURE');
do $$ begin
 if not exists(select 1 from public.dating_members where user_id='00000000-0000-4000-8000-000000000001' and paid_until>now()+interval '29 days') then raise exception 'Payment activation failed'; end if;
 begin perform public.dating_redeem_verified_capture('00000000-0000-4000-8000-000000000001','TEST-ROLLBACK-CAPTURE'); raise exception 'Duplicate capture accepted'; exception when unique_violation then null; end;
end $$;
rollback;
