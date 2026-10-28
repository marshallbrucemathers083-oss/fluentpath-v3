do $$ declare administrator uuid:=auth.uid(); member uuid:='00000000-0000-4000-8000-000000000202'; p jsonb; ex uuid; opt uuid; post uuid; operation text; q text; response jsonb; initial_xp integer;
begin
 p:=public.get_lesson('a1-verb-to-be'); ex:=(p->'exercises'->0->>'id')::uuid;
 select (o->>'id')::uuid into opt from jsonb_array_elements(p->'exercises'->0->'options') o where o->>'option_text'='are';
 post:=public.create_forum_thread('RLS restrictions fixture','Synthetic target for restricted-account interactions.');
 perform public.admin_moderate_user(member,'warn','Synthetic warning before restrictions');
 perform set_config('request.jwt.claim.sub',member::text,false);
 if not exists(select 1 from public.user_warnings where user_id=auth.uid()) then raise exception 'Member cannot read own warning'; end if;
 select total_xp into initial_xp from public.profiles where id=member;
 foreach operation in array array['suspend','ban'] loop
 perform set_config('request.jwt.claim.sub',administrator::text,false);
 perform public.admin_moderate_user(member,operation,'Synthetic restriction check',case when operation='suspend' then now()+interval '1 hour' else null end);
 perform set_config('request.jwt.claim.sub',member::text,false);
 if public.account_active() then raise exception 'Restricted member remains active'; end if;
 foreach q in array array[
 format('select public.submit_exercise(%L::uuid,%L::uuid)',ex,opt),
 format('select public.submit_written_response(%L::uuid,%L)',ex,'A sufficiently long synthetic practice response.'),
 'select public.create_forum_thread(''Restricted post'',''This synthetic post must never be inserted.'')',
 format('select public.create_forum_reply(%L::uuid,''This reply must be denied.'')',post),
 format('select public.report_forum_content(''thread'',%L::uuid,''Spam or advertising: must be denied'')',post),
 'select public.start_toefl_attempt()'
 ] loop
 begin execute q; raise exception 'Restricted operation succeeded: %',q;
 exception when others then if sqlerrm<>'Account access restricted' then raise; end if; end;
 end loop;
 perform set_config('request.jwt.claim.sub',administrator::text,false);
 if operation='ban' then perform public.admin_set_user_ban(member,false);
 else perform public.admin_moderate_user(member,'restore','Synthetic restoration check'); end if;
 perform set_config('request.jwt.claim.sub',member::text,false);
 if not public.account_active() then raise exception 'Restore did not clear restriction'; end if;
 response:=public.submit_exercise(ex,opt);
 if (response->>'correct')::boolean is distinct from true then raise exception 'Restored learner cannot submit'; end if;
 perform public.create_forum_thread('Restored member fixture','This synthetic post is allowed after restoration.');
 if (select total_xp from public.profiles where id=member)<>initial_xp then raise exception 'Restoration/replay changed existing XP'; end if;
 if not exists(select 1 from public.lesson_progress where user_id=member and status='completed') then raise exception 'Existing completed progress lost'; end if;
 end loop;
 perform set_config('request.jwt.claim.sub',administrator::text,false);
 if (select count(*) from public.moderation_history where target_id=member and action in ('warn','suspend','ban','restore'))<5 then raise exception 'Restriction audit incomplete'; end if;
end $$;
