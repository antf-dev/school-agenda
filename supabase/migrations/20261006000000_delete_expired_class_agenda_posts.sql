-- Preserve assignment completion events when expired class agenda posts are removed.
create table if not exists public.student_task_completion_history (
  student_id uuid not null references auth.users(id) on delete cascade,
  agenda_post_id uuid not null,
  completed_at timestamptz not null,
  archived_at timestamptz not null default now(),
  primary key (student_id, agenda_post_id)
);
alter table public.student_task_completion_history enable row level security;
revoke all on public.student_task_completion_history from public, anon, authenticated;

create or replace function public.archive_class_agenda_completions_before_delete()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  insert into public.student_task_completion_history(student_id, agenda_post_id, completed_at)
  select c.student_id, c.agenda_post_id, c.completed_at
  from public.student_task_completions c
  where c.agenda_post_id = old.id
  on conflict (student_id, agenda_post_id) do update
    set completed_at = least(public.student_task_completion_history.completed_at, excluded.completed_at);
  return old;
end;
$$;
revoke all on function public.archive_class_agenda_completions_before_delete() from public, anon, authenticated;

drop trigger if exists archive_class_agenda_completions_before_delete on public.class_agenda_posts;
create trigger archive_class_agenda_completions_before_delete
before delete on public.class_agenda_posts
for each row execute function public.archive_class_agenda_completions_before_delete();

create or replace function public._refresh_student_missions(p_student uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare d date:=current_date; w date:=date_trunc('week',current_date)::date; m record; v_progress integer; v_ref text;
begin
  insert into public.student_missions(student_id,mission_id,period_start,period_end,title,target,xp_reward)
  values
    (p_student,'daily-class-homework',d,d,'Complete a class assignment',1,20),
    (p_student,'daily-study-30',d,d,'Study for 30 minutes',30,30),
    (p_student,'weekly-class-homework',w,w+6,'Complete 5 class assignments',5,100),
    (p_student,'weekly-study-180',w,w+6,'Study for 3 hours',180,150)
  on conflict do nothing;

  for m in select * from public.student_missions where student_id=p_student and period_end>=d and period_start<=d loop
    if m.mission_id like '%homework' then
      select count(*)::integer into v_progress
      from (
        select c.completed_at from public.student_task_completions c where c.student_id=p_student
        union all
        select h.completed_at from public.student_task_completion_history h where h.student_id=p_student
      ) completions
      where completions.completed_at >= m.period_start::timestamptz
        and completions.completed_at < (m.period_end+1)::timestamptz;
    else
      select coalesce(sum(duration_minutes),0)::integer into v_progress
      from public.student_study_sessions s
      where s.student_id=p_student and s.ended_at is not null
        and s.started_at >= m.period_start::timestamptz
        and s.started_at < (m.period_end+1)::timestamptz;
    end if;
    update public.student_missions set progress=v_progress,
      completed_at=case when v_progress>=target then coalesce(completed_at,now()) else completed_at end
    where student_id=p_student and mission_id=m.mission_id and period_start=m.period_start;
    if v_progress>=m.target and m.claimed_at is null then
      v_ref:=m.mission_id||':'||m.period_start::text;
      perform public._award_student_xp(p_student,'mission',v_ref,m.xp_reward);
      update public.student_missions set claimed_at=now()
      where student_id=p_student and mission_id=m.mission_id and period_start=m.period_start and claimed_at is null;
    end if;
  end loop;
end;
$function$;

create or replace function public.delete_expired_class_agenda_posts()
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare deleted_count integer;
begin
  delete from public.class_agenda_posts
  where due_date is not null
    and due_date < (now() at time zone 'Asia/Beirut')::date;
  get diagnostics deleted_count = row_count;
  return deleted_count;
end;
$$;
revoke all on function public.delete_expired_class_agenda_posts() from public, anon, authenticated;

do $$
declare existing_job record;
begin
  for existing_job in select jobid from cron.job where jobname='delete-expired-class-agenda-posts' loop
    perform cron.unschedule(existing_job.jobid);
  end loop;
  perform cron.schedule(
    'delete-expired-class-agenda-posts',
    '0 * * * *',
    'select public.delete_expired_class_agenda_posts();'
  );
end;
$$;

-- Remove any posts that already expired. Completion events are archived by the trigger above.
select public.delete_expired_class_agenda_posts();
