alter table public.students
  add column if not exists has_password boolean not null default false,
  add column if not exists total_xp integer not null default 0,
  add column if not exists level integer not null default 1;

create index if not exists students_class_leaderboard_idx on public.students (class_key, level, total_xp);

create or replace function public.update_student_progress(p_total_xp integer,p_level integer)
returns public.students language plpgsql security definer set search_path=public as $$
declare v_row public.students;
begin
  if auth.uid() is null then raise exception 'Authentication required.'; end if;
  update public.students
  set total_xp=greatest(total_xp,greatest(coalesce(p_total_xp,0),0)),
      level=greatest(level,greatest(coalesce(p_level,1),1)),updated_at=now()
  where id=auth.uid() returning * into v_row;
  if v_row.id is null then raise exception 'Student profile not found.'; end if;
  return v_row;
end; $$;

create or replace function public.get_class_leaderboard()
returns table(id uuid,name text,class_name text,total_xp integer,level integer)
language plpgsql security definer set search_path=public as $$
declare v_class_key text;
begin
  if auth.uid() is null then raise exception 'Authentication required.'; end if;
  select s.class_key into v_class_key from public.students s where s.id=auth.uid();
  if v_class_key is null then raise exception 'Student profile not found.'; end if;
  return query
  select s.id,s.name,s.class_name,s.total_xp,s.level
  from public.students s where s.class_key=v_class_key
  order by s.level asc,s.total_xp asc,lower(s.name) asc,s.created_at asc;
end; $$;

revoke all on function public.update_student_progress(integer,integer) from public;
grant execute on function public.update_student_progress(integer,integer) to authenticated;
revoke all on function public.get_class_leaderboard() from public;
grant execute on function public.get_class_leaderboard() to authenticated;
