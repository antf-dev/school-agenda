create or replace function public.complete_class_agenda_assignment(p_agenda_post_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_uid uuid:=auth.uid(); v_post public.class_agenda_posts; v_added integer; v_bonus integer:=0; v_before integer; v_after integer;
begin
  if v_uid is null then raise exception 'Authentication required.'; end if;
  select total_xp into v_before from public.students where id=v_uid;
  select * into v_post from public.class_agenda_posts where id=p_agenda_post_id and class_key=public.current_user_class_key();
  if v_post.id is null then raise exception 'Assignment not found in your class.'; end if;
  if v_post.type not in ('homework','project') then raise exception 'This post is not a homework assignment.'; end if;
  if v_post.owner_id=v_uid then raise exception 'You cannot earn XP for an assignment you posted.'; end if;
  insert into public.student_task_completions(student_id,agenda_post_id) values(v_uid,p_agenda_post_id) on conflict do nothing;
  if not found then return jsonb_build_object('ok',true,'duplicate',true,'xp',0); end if;
  v_added:=public._award_student_xp(v_uid,'class_assignment',p_agenda_post_id::text,20);
  if v_post.due_date is not null and v_post.due_date>current_date then
    v_bonus:=public._award_student_xp(v_uid,'early_completion',p_agenda_post_id::text,5);
  end if;
  perform public._refresh_student_missions(v_uid);
  select total_xp into v_after from public.students where id=v_uid;
  return jsonb_build_object('ok',true,'duplicate',false,'xp',greatest(0,v_after-v_before));
end $$;
grant execute on function public.complete_class_agenda_assignment(uuid) to authenticated;

create or replace function public.finish_student_study_session(p_session_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare s public.student_study_sessions; mins integer; v_xp integer; v_before integer; v_after integer;
begin
 if auth.uid() is null then raise exception 'Authentication required.'; end if;
 select total_xp into v_before from public.students where id=auth.uid();
 select * into s from public.student_study_sessions where id=p_session_id and student_id=auth.uid() for update;
 if s.id is null then raise exception 'Study session not found.'; end if;
 if s.ended_at is not null then return jsonb_build_object('ok',true,'duplicate',true,'minutes',s.duration_minutes,'xp',0); end if;
 mins:=floor(extract(epoch from (now()-s.started_at))/60)::integer;
 if mins<5 then raise exception 'Study for at least 5 minutes before completing a session.'; end if;
 mins:=least(mins,180);
 update public.student_study_sessions set ended_at=now(),duration_minutes=mins where id=s.id;
 v_xp:=least(60,mins);
 perform public._award_student_xp(auth.uid(),'study_session',p_session_id::text,v_xp);
 perform public._refresh_student_missions(auth.uid());
 select total_xp into v_after from public.students where id=auth.uid();
 return jsonb_build_object('ok',true,'duplicate',false,'minutes',mins,'xp',greatest(0,v_after-v_before));
end $$;
grant execute on function public.finish_student_study_session(uuid) to authenticated;