create or replace function public._award_current_student_streak(p_student uuid)
returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare v_day date:=current_date; v_streak integer:=0; v_bonus integer;
begin
 while v_streak<365 and (
   exists(select 1 from public.student_task_completions c where c.student_id=p_student and c.completed_at>=v_day::timestamptz and c.completed_at<(v_day+1)::timestamptz)
   or exists(select 1 from public.student_personal_task_completions c where c.student_id=p_student and c.completed_at>=v_day::timestamptz and c.completed_at<(v_day+1)::timestamptz)
 ) loop
   v_streak:=v_streak+1;v_day:=v_day-1;
 end loop;
 if v_streak<2 then return 0; end if;
 v_bonus:=least(v_streak,7)*5;
 return public._award_student_xp(p_student,'streak','streak:'||current_date::text,v_bonus);
end $$;
revoke all on function public._award_current_student_streak(uuid) from public,anon,authenticated;

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
  perform public._award_current_student_streak(v_uid);
  perform public._refresh_student_missions(v_uid);
  select total_xp into v_after from public.students where id=v_uid;
  return jsonb_build_object('ok',true,'duplicate',false,'xp',greatest(0,v_after-v_before));
end $$;
grant execute on function public.complete_class_agenda_assignment(uuid) to authenticated;

create or replace function public.award_personal_homework_xp(p_task_id uuid,p_title text,p_subject text,p_due_date date)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_uid uuid:=auth.uid(); v_amount integer; v_today_xp integer; v_added integer; v_total integer; v_level integer:=1;
begin
 if v_uid is null then raise exception 'Authentication required.'; end if;
 if not exists(select 1 from public.students where id=v_uid) then raise exception 'Student profile not found.'; end if;
 if p_task_id is null or length(trim(coalesce(p_title,''))) not between 1 and 160 or length(trim(coalesce(p_subject,''))) not between 1 and 80 then raise exception 'Invalid homework task.'; end if;
 if p_due_date is not null and p_due_date>current_date+365 then raise exception 'Homework date is outside the reward window.'; end if;
 insert into public.student_personal_task_completions(student_id,task_id,title,subject,due_date)
 values(v_uid,p_task_id,left(trim(p_title),160),left(trim(p_subject),80),p_due_date)
 on conflict do nothing;
 if not found then return jsonb_build_object('ok',true,'duplicate',true,'xp',0); end if;
 perform pg_advisory_xact_lock(hashtextextended(v_uid::text,0));
 select coalesce(sum(amount),0)::integer into v_today_xp from public.student_xp_ledger
 where student_id=v_uid and source='personal_homework' and created_at>=date_trunc('day',now());
 v_amount:=20+case when p_due_date is not null and p_due_date>current_date then 5 else 0 end;
 if v_today_xp+v_amount>100 then
   return jsonb_build_object('ok',true,'duplicate',false,'reward_limited',true,'xp',0);
 end if;
 v_added:=public._award_student_xp(v_uid,'personal_homework',p_task_id::text,v_amount);
 perform public._award_current_student_streak(v_uid);
 select total_xp into v_total from public.students where id=v_uid;
 while v_total >= v_level * (100*(v_level+1)+300) loop v_level:=v_level+1; end loop;
 update public.students set level=v_level,updated_at=now() where id=v_uid;
 update public.student_personal_task_completions set xp_awarded=v_added where student_id=v_uid and task_id=p_task_id;
 return jsonb_build_object('ok',true,'duplicate',false,'reward_limited',false,'xp',v_added,'total_xp',v_total,'level',v_level);
end $$;
revoke all on function public.award_personal_homework_xp(uuid,text,text,date) from public,anon;
grant execute on function public.award_personal_homework_xp(uuid,text,text,date) to authenticated;