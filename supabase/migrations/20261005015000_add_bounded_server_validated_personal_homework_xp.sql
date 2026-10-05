alter table public.student_xp_ledger drop constraint if exists student_xp_ledger_source_check;
alter table public.student_xp_ledger add constraint student_xp_ledger_source_check check (source in ('class_assignment','early_completion','personal_homework','study_session','mission','quiz','achievement','streak'));

create table if not exists public.student_personal_task_completions (
  student_id uuid not null references auth.users(id) on delete cascade,
  task_id uuid not null,
  title text not null,
  subject text not null,
  due_date date,
  completed_at timestamptz not null default now(),
  xp_awarded integer not null default 0 check(xp_awarded between 0 and 25),
  primary key(student_id,task_id)
);
alter table public.student_personal_task_completions enable row level security;
drop policy if exists student_personal_task_completions_read_self on public.student_personal_task_completions;
create policy student_personal_task_completions_read_self on public.student_personal_task_completions for select to authenticated using(student_id=auth.uid());
grant select on public.student_personal_task_completions to authenticated;

create or replace function public.award_personal_homework_xp(p_task_id uuid,p_title text,p_subject text,p_due_date date)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_uid uuid:=auth.uid(); v_amount integer; v_today_xp integer; v_added integer; v_total integer; v_level integer:=1;
begin
 if v_uid is null then raise exception 'Authentication required.'; end if;
 if not exists(select 1 from public.students where id=v_uid) then raise exception 'Student profile not found.'; end if;
 if p_task_id is null or length(trim(coalesce(p_title,''))) not between 1 and 160 or length(trim(coalesce(p_subject,''))) not between 1 and 80 then raise exception 'Invalid homework task.'; end if;
 if p_due_date is not null and (p_due_date<current_date-30 or p_due_date>current_date+365) then raise exception 'Homework date is outside the reward window.'; end if;
 insert into public.student_personal_task_completions(student_id,task_id,title,subject,due_date)
 values(v_uid,p_task_id,left(trim(p_title),160),left(trim(p_subject),80),p_due_date)
 on conflict do nothing;
 if not found then return jsonb_build_object('ok',true,'duplicate',true,'xp',0); end if;
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