create or replace function public.get_class_leaderboard()
returns table(id uuid,name text,class_name text,total_xp integer,level integer)
language plpgsql
security definer
set search_path=public
as $function$
declare
  v_class_key text;
begin
  if auth.uid() is null then raise exception 'Authentication required.'; end if;
  select s.class_key into v_class_key
  from public.students s
  where s.id=auth.uid();
  if v_class_key is null then raise exception 'Student profile not found.'; end if;

  return query
  select s.id,s.name,s.class_name,s.total_xp,s.level
  from public.students s
  where s.class_key=v_class_key and s.is_admin=false
  order by s.total_xp desc,s.level desc,lower(s.name) asc,s.created_at asc;
end;
$function$;

revoke all on function public.get_class_leaderboard() from public;
grant execute on function public.get_class_leaderboard() to authenticated;

