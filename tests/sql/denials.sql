do $$ declare q text;
begin
 begin update public.profiles set role='admin' where id=auth.uid(); raise exception 'Direct self-promotion succeeded'; exception when insufficient_privilege then null; end;
 begin update public.profiles set total_xp=999999 where id=auth.uid(); raise exception 'Direct XP inflation succeeded'; exception when insufficient_privilege then null; end;
 foreach q in array array[
 'select public.admin_list_users()',
 'select public.admin_platform_stats()',
 'select public.admin_set_user_role(auth.uid(),''admin'')',
 'select public.admin_set_user_ban(auth.uid(),true)',
 'select public.admin_moderate_user(auth.uid(),''ban'',''Synthetic denial test'')',
 'select public.admin_save_material(''lesson'',null,''{}''::jsonb)',
 'select public.admin_create_practice(''{"kind":"set"}''::jsonb)',
 'select public.admin_set_practice_status(null,true)',
 'select public.admin_report_context(null)',
 'select public.moderate_forum_report(null,''dismiss'')',
 'select public.moderate_forum_content(''thread'',null,''removed'')'
 ] loop
 begin execute q; raise exception 'Unauthorized admin RPC succeeded: %',q;
 exception when others then if sqlerrm<>'Administrator access required' then raise; end if; end;
 end loop;
 if public.is_admin() or (select role from public.profiles where id=auth.uid())<>'student' then raise exception 'Denial tests changed student privileges'; end if;
end $$;
