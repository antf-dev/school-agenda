-- Additive academic dashboard and secure progress foundation. Existing student rows/XP are preserved.
create table if not exists public.student_xp_ledger (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references auth.users(id) on delete cascade,
  source text not null check (source in ('class_assignment','early_completion','study_session','mission','quiz','achievement','streak')),
  source_ref text not null,
  amount integer not null check (amount > 0 and amount <= 250),
  created_at timestamptz not null default now(),
  unique(student_id, source, source_ref)
);
alter table public.student_xp_ledger enable row level security;
drop policy if exists student_xp_ledger_read_self on public.student_xp_ledger;
create policy student_xp_ledger_read_self on public.student_xp_ledger for select to authenticated using(student_id=auth.uid());

create table if not exists public.student_task_completions (
  student_id uuid not null references auth.users(id) on delete cascade,
  agenda_post_id uuid not null references public.class_agenda_posts(id) on delete cascade,
  completed_at timestamptz not null default now(),
  primary key(student_id, agenda_post_id)
);
alter table public.student_task_completions enable row level security;
drop policy if exists student_task_completions_read_self on public.student_task_completions;
create policy student_task_completions_read_self on public.student_task_completions for select to authenticated using(student_id=auth.uid());

create table if not exists public.student_study_sessions (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references auth.users(id) on delete cascade,
  subject text,
  topic text,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  duration_minutes integer check (duration_minutes between 1 and 180),
  created_at timestamptz not null default now()
);
create index if not exists student_study_sessions_student_started on public.student_study_sessions(student_id, started_at desc);
alter table public.student_study_sessions enable row level security;
drop policy if exists student_study_sessions_read_self on public.student_study_sessions;
create policy student_study_sessions_read_self on public.student_study_sessions for select to authenticated using(student_id=auth.uid());

create table if not exists public.student_missions (
  student_id uuid not null references auth.users(id) on delete cascade,
  mission_id text not null,
  period_start date not null,
  period_end date not null,
  title text not null,
  target integer not null check (target > 0),
  xp_reward integer not null check (xp_reward between 1 and 250),
  progress integer not null default 0 check (progress >= 0),
  completed_at timestamptz,
  claimed_at timestamptz,
  created_at timestamptz not null default now(),
  primary key(student_id, mission_id, period_start),
  check (period_end >= period_start)
);
alter table public.student_missions enable row level security;
drop policy if exists student_missions_read_self on public.student_missions;
create policy student_missions_read_self on public.student_missions for select to authenticated using(student_id=auth.uid());

create table if not exists public.student_tests (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references auth.users(id) on delete cascade,
  subject text not null,
  title text not null,
  test_at timestamptz not null,
  created_at timestamptz not null default now()
);
alter table public.student_tests enable row level security;
drop policy if exists student_tests_owner_all on public.student_tests;
create policy student_tests_owner_all on public.student_tests for all to authenticated using(student_id=auth.uid()) with check(student_id=auth.uid());

create table if not exists public.student_plan_items (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references auth.users(id) on delete cascade,
  subject text not null,
  title text not null,
  details text,
  starts_at timestamptz,
  duration_minutes integer not null default 25 check(duration_minutes between 5 and 180),
  curriculum_topic_id uuid,
  completed_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.student_plan_items enable row level security;
drop policy if exists student_plan_items_owner_all on public.student_plan_items;
create policy student_plan_items_owner_all on public.student_plan_items for all to authenticated using(student_id=auth.uid()) with check(student_id=auth.uid());

create table if not exists public.curriculum_topics (
  id uuid primary key default gen_random_uuid(),
  crdp_grade text not null,
  subject text not null,
  unit text,
  chapter text,
  topic text not null,
  learning_objective text,
  source_url text not null,
  source_version text not null,
  source_page integer,
  mapping_status text not null default 'verified' check(mapping_status in ('verified','unavailable','track_required')),
  created_at timestamptz not null default now()
);
create index if not exists curriculum_topics_lookup on public.curriculum_topics(crdp_grade, subject);
alter table public.curriculum_topics enable row level security;
drop policy if exists curriculum_topics_public_read on public.curriculum_topics;
create policy curriculum_topics_public_read on public.curriculum_topics for select to anon, authenticated using(true);

create table if not exists public.student_quiz_attempts (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references auth.users(id) on delete cascade,
  curriculum_topic_id uuid references public.curriculum_topics(id) on delete set null,
  quiz_key text not null,
  score integer not null check(score between 0 and 100),
  question_count integer not null check(question_count > 0 and question_count <= 50),
  weak_areas jsonb not null default '[]'::jsonb,
  completed_at timestamptz not null default now(),
  xp_awarded integer not null default 0 check(xp_awarded between 0 and 100),
  unique(student_id, quiz_key)
);
alter table public.student_quiz_attempts enable row level security;
drop policy if exists student_quiz_attempts_read_self on public.student_quiz_attempts;
create policy student_quiz_attempts_read_self on public.student_quiz_attempts for select to authenticated using(student_id=auth.uid());

create table if not exists public.deadline_reminders (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references auth.users(id) on delete cascade,
  source_type text not null check(source_type in ('homework','test','school_event','class_agenda')),
  source_id text not null,
  reminder_key text not null,
  scheduled_for timestamptz not null,
  delivered_at timestamptz,
  created_at timestamptz not null default now(),
  unique(student_id, source_type, source_id, reminder_key)
);
alter table public.deadline_reminders enable row level security;
drop policy if exists deadline_reminders_read_self on public.deadline_reminders;
create policy deadline_reminders_read_self on public.deadline_reminders for select to authenticated using(student_id=auth.uid());

create table if not exists public.student_notification_preferences (
  student_id uuid primary key references auth.users(id) on delete cascade,
  enabled boolean not null default true,
  browser_notifications boolean not null default false,
  reminder_offsets integer[] not null default array[3,1,0],
  updated_at timestamptz not null default now(),
  check (reminder_offsets <@ array[0,1,3]::integer[])
);
alter table public.student_notification_preferences enable row level security;
drop policy if exists student_notification_preferences_owner_all on public.student_notification_preferences;
create policy student_notification_preferences_owner_all on public.student_notification_preferences for all to authenticated using(student_id=auth.uid()) with check(student_id=auth.uid());

create or replace function public._award_student_xp(p_student uuid,p_source text,p_source_ref text,p_amount integer)
returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare v_added integer; v_total integer; v_level integer:=1;
begin
  if p_student is null or p_source_ref is null or length(p_source_ref)>180 or p_amount not between 1 and 250 then raise exception 'Invalid XP award.'; end if;
  insert into public.student_xp_ledger(student_id,source,source_ref,amount)
  values(p_student,p_source,p_source_ref,p_amount)
  on conflict(student_id,source,source_ref) do nothing;
  if not found then return 0; end if;
  update public.students set total_xp=total_xp+p_amount, updated_at=now()
    where id=p_student returning total_xp into v_total;
  if v_total is null then raise exception 'Student profile not found.'; end if;
  while v_total >= v_level * (100*(v_level+1)+300) loop v_level:=v_level+1; end loop;
  update public.students set level=v_level where id=p_student;
  return p_amount;
end $$;
revoke all on function public._award_student_xp(uuid,text,text,integer) from public, anon, authenticated;

create or replace function public._refresh_student_missions(p_student uuid)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
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
      select count(*)::integer into v_progress from public.student_task_completions c
      where c.student_id=p_student and c.completed_at >= m.period_start::timestamptz and c.completed_at < (m.period_end+1)::timestamptz;
    else
      select coalesce(sum(duration_minutes),0)::integer into v_progress from public.student_study_sessions s
      where s.student_id=p_student and s.ended_at is not null and s.started_at >= m.period_start::timestamptz and s.started_at < (m.period_end+1)::timestamptz;
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
end $$;
revoke all on function public._refresh_student_missions(uuid) from public, anon, authenticated;

create or replace function public.get_student_missions()
returns table(mission_id text,period_start date,period_end date,title text,target integer,progress integer,xp_reward integer,completed_at timestamptz,claimed_at timestamptz)
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if auth.uid() is null then raise exception 'Authentication required.'; end if;
  if not exists(select 1 from public.students where id=auth.uid()) then raise exception 'Student profile not found.'; end if;
  perform public._refresh_student_missions(auth.uid());
  return query select m.mission_id,m.period_start,m.period_end,m.title,m.target,m.progress,m.xp_reward,m.completed_at,m.claimed_at
    from public.student_missions m where m.student_id=auth.uid() and m.period_end>=current_date
    order by m.period_start,m.mission_id;
end $$;
revoke all on function public.get_student_missions() from public, anon;
grant execute on function public.get_student_missions() to authenticated;

create or replace function public.complete_class_agenda_assignment(p_agenda_post_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_uid uuid:=auth.uid(); v_post public.class_agenda_posts; v_added integer; v_bonus integer:=0;
begin
  if v_uid is null then raise exception 'Authentication required.'; end if;
  select * into v_post from public.class_agenda_posts where id=p_agenda_post_id and class_key=public.current_user_class_key();
  if v_post.id is null then raise exception 'Assignment not found in your class.'; end if;
  if v_post.type not in ('homework','project') then raise exception 'This post is not a homework assignment.'; end if;
  insert into public.student_task_completions(student_id,agenda_post_id) values(v_uid,p_agenda_post_id) on conflict do nothing;
  if not found then return jsonb_build_object('ok',true,'duplicate',true,'xp',0); end if;
  v_added:=public._award_student_xp(v_uid,'class_assignment',p_agenda_post_id::text,20);
  if v_post.due_date is not null and v_post.due_date>current_date then
    v_bonus:=public._award_student_xp(v_uid,'early_completion',p_agenda_post_id::text,5);
  end if;
  perform public._refresh_student_missions(v_uid);
  return jsonb_build_object('ok',true,'duplicate',false,'xp',v_added+v_bonus);
end $$;
revoke all on function public.complete_class_agenda_assignment(uuid) from public, anon;
grant execute on function public.complete_class_agenda_assignment(uuid) to authenticated;

create or replace function public.start_student_study_session(p_subject text default null,p_topic text default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid;
begin
 if auth.uid() is null then raise exception 'Authentication required.'; end if;
 if not exists(select 1 from public.students where id=auth.uid()) then raise exception 'Student profile not found.'; end if;
 if exists(select 1 from public.student_study_sessions where student_id=auth.uid() and ended_at is null) then raise exception 'Finish your current study session first.'; end if;
 insert into public.student_study_sessions(student_id,subject,topic) values(auth.uid(),left(trim(coalesce(p_subject,'')),80),left(trim(coalesce(p_topic,'')),180)) returning id into v_id;
 return v_id;
end $$;
revoke all on function public.start_student_study_session(text,text) from public, anon;
grant execute on function public.start_student_study_session(text,text) to authenticated;

create or replace function public.finish_student_study_session(p_session_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare s public.student_study_sessions; mins integer; v_xp integer;
begin
 if auth.uid() is null then raise exception 'Authentication required.'; end if;
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
 return jsonb_build_object('ok',true,'duplicate',false,'minutes',mins,'xp',v_xp);
end $$;
revoke all on function public.finish_student_study_session(uuid) from public, anon;
grant execute on function public.finish_student_study_session(uuid) to authenticated;

-- The historical sync accepted client-supplied totals. Preserve the function and all rows,
-- but remove client execute privileges; future XP is awarded only through validated RPCs.
revoke all on function public.update_student_progress(integer,integer) from public, anon, authenticated;
