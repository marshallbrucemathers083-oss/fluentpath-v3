-- REVIEW TEMPLATE ONLY. Execute as the trusted database owner after explicit approval.
-- Never expose this operation as an RPC, signup option, client script, or public endpoint.
begin;
do $$
declare selected_account uuid := null; -- Set the explicitly approved auth.users UUID.
 expected_email text := null; -- Set the independently verified account email.
 target record;
begin
 if selected_account is null or expected_email is null then raise exception 'Set the approved UUID and verified email before bootstrap'; end if;
 -- Serialize first-admin bootstrap with ordinary profile writes during this short transaction.
 lock table public.profiles in share row exclusive mode;
 if exists(select 1 from public.profiles where role='admin') then raise exception 'An administrator already exists; review access instead of bootstrapping again'; end if;
 select p.id,p.role,p.is_banned,p.suspended_until,u.email,u.email_confirmed_at into target
 from public.profiles p join auth.users u on u.id=p.id
 where p.id=selected_account and u.email=expected_email and p.email=expected_email for update of p,u;
 if not found then raise exception 'Approved UUID/email pair does not match an existing account'; end if;
 if target.email_confirmed_at is null or target.is_banned or target.suspended_until>now() then raise exception 'Verify the email and resolve account restrictions before granting access'; end if;
 if auth.uid() is not null then raise exception 'Run bootstrap as a trusted database session without a user JWT'; end if;
 update public.profiles set role='admin',updated_at=now() where id=selected_account;
 if not exists(select 1 from public.moderation_history where target_id=selected_account and actor_id is null and action='profiles:UPDATE') then raise exception 'Bootstrap audit entry missing'; end if;
end $$;
commit;
