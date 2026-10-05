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
 -- Serialize each student's daily-cap check so concurrent requests cannot race past 100 XP.
 perform pg_advisory_xact_lock(hashtextextended(v_uid::text,0));
 select coalesce(sum(amount),0)::integer into v_today_xp from public.student_xp_ledger
 where student_id=v_uid and source='personal_homework' and created_at>=date_trunc('day',now());
 v_amount:=20+case when p_due_date is not null and p_due_date>current_date then 5 else 0 end;
 if v_today_xp+v_amount>100 then
   return jsonb_build_object('ok',true,'duplicate',false,'reward_limited',true,'xp',0);
 end if;
 v_added:=public._award_student_xp(v_uid,'personal_homework',p_task_id::text,v_amount);
 update public.student_personal_task_completions set xp_awarded=v_added where student_id=v_uid and task_id=p_task_id;
 select total_xp into v_total from public.students where id=v_uid;
 while v_total >= v_level * (100*(v_level+1)+300) loop v_level:=v_level+1; end loop;
 update public.students set level=v_level,updated_at=now() where id=v_uid;
 return jsonb_build_object('ok',true,'duplicate',false,'reward_limited',false,'xp',v_added,'total_xp',v_total,'level',v_level);
end $$;
revoke all on function public.award_personal_homework_xp(uuid,text,text,date) from public, anon;
grant execute on function public.award_personal_homework_xp(uuid,text,text,date) to authenticated;