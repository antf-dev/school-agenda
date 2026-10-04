alter table public.students
  add column if not exists last_active_at timestamptz;

create or replace function public.record_student_activity()
returns timestamptz
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_id uuid := auth.uid();
  v_last_active timestamptz;
begin
  if v_id is null then raise exception 'Authentication required.' using errcode='42501'; end if;

  update public.students s
  set last_active_at=now()
  where s.id=v_id
    and (s.last_active_at is null or s.last_active_at < now() - interval '1 minute')
  returning s.last_active_at into v_last_active;

  if v_last_active is null then
    select s.last_active_at into v_last_active
    from public.students s
    where s.id=v_id;
  end if;
  if v_last_active is null then raise exception 'Student profile not found.'; end if;
  return v_last_active;
end;
$function$;

revoke all on function public.record_student_activity() from public, anon, authenticated;
grant execute on function public.record_student_activity() to authenticated;

drop function if exists public.get_admin_student_directory();
create function public.get_admin_student_directory()
returns table(
  id uuid,
  name text,
  class_name text,
  class_key text,
  is_admin boolean,
  has_password boolean,
  level integer,
  total_xp integer,
  created_at timestamptz,
  updated_at timestamptz,
  last_active_at timestamptz
)
language sql
security definer
set search_path = public
as $function$
  select s.id, s.name, s.class_name, s.class_key, s.is_admin, s.has_password,
         s.level, s.total_xp, s.created_at, s.updated_at, s.last_active_at
  from public.students s
  where exists (
    select 1 from public.students me
    where me.id = (select auth.uid())
      and me.is_admin = true
  )
  order by s.class_key, s.level asc, s.total_xp asc, lower(s.name) asc, s.created_at asc;
$function$;

revoke all on function public.get_admin_student_directory() from public, anon, authenticated;
grant execute on function public.get_admin_student_directory() to authenticated;
