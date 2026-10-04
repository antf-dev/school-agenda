-- Keep student class assignments authoritative in the database after onboarding.
create or replace function public.register_student(p_name text, p_class_name text)
returns students
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_id uuid := auth.uid();
  v_name text := left(regexp_replace(trim(coalesce(p_name,'')), '[[:space:]]+', ' '), 40);
  v_class text := left(regexp_replace(trim(coalesce(p_class_name,'')), '[[:space:]]+', ' '), 40);
  v_key text := public.normalize_class_name(v_class);
  v_row public.students;
begin
  if v_id is null then raise exception 'Not authenticated'; end if;
  if v_name='' or v_class='' or v_key='' then raise exception 'Name and class are required'; end if;
  if not public.is_allowed_class_key(v_key) then raise exception 'Please choose a valid class.'; end if;

  insert into public.students(id,name,class_name,class_key,is_admin)
  values(v_id,v_name,v_class,v_key,false)
  on conflict(id) do update
  set name=excluded.name,
      class_name=case when public.is_current_user_admin() then excluded.class_name else public.students.class_name end,
      class_key=case when public.is_current_user_admin() then excluded.class_key else public.students.class_key end,
      updated_at=now()
  where public.students.name is distinct from excluded.name
     or (public.is_current_user_admin() and
         (public.students.class_name is distinct from excluded.class_name
          or public.students.class_key is distinct from excluded.class_key))
  returning * into v_row;
  if v_row.id is null then
    select * into v_row from public.students where id=v_id;
  end if;
  return v_row;
end;
$function$;

create or replace function public.register_student_and_get_current_class_agenda(p_name text, p_class_name text)
returns setof public.class_agenda_posts
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_id uuid := auth.uid();
  v_name text := left(regexp_replace(trim(coalesce(p_name,'')), '[[:space:]]+', ' '), 40);
  v_class text := left(regexp_replace(trim(coalesce(p_class_name,'')), '[[:space:]]+', ' '), 40);
  v_key text := public.normalize_class_name(v_class);
begin
  if v_id is null then raise exception 'Not authenticated'; end if;
  if v_name='' or v_class='' or v_key='' then raise exception 'Name and class are required'; end if;
  if not public.is_allowed_class_key(v_key) then raise exception 'Please choose a valid class.'; end if;

  insert into public.students(id,name,class_name,class_key,is_admin)
  values(v_id,v_name,v_class,v_key,false)
  on conflict(id) do update
  set name=excluded.name,
      class_name=case when public.is_current_user_admin() then excluded.class_name else public.students.class_name end,
      class_key=case when public.is_current_user_admin() then excluded.class_key else public.students.class_key end,
      updated_at=now()
  where public.students.name is distinct from excluded.name
     or (public.is_current_user_admin() and
         (public.students.class_name is distinct from excluded.class_name
          or public.students.class_key is distinct from excluded.class_key));

  select s.class_name,s.class_key into v_class,v_key
  from public.students s
  where s.id=v_id;
  if v_key is null then raise exception 'Student profile not found.'; end if;

  return query
  select p.* from public.class_agenda_posts p
  where public.normalize_class_name(coalesce(p.class_name,''))=v_key or p.class_key=v_key
  order by p.due_date asc nulls last,p.due_time asc nulls last,p.created_at asc;
end;
$function$;

create or replace function public.admin_set_student_class(p_student_id uuid, p_class_name text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_uid uuid := auth.uid();
  v_class text := left(regexp_replace(trim(coalesce(p_class_name,'')), '[[:space:]]+', ' '), 40);
  v_key text := public.normalize_class_name(v_class);
  v_row public.students;
begin
  if v_uid is null or not exists (
    select 1 from public.students s where s.id=v_uid and s.is_admin=true
  ) then
    raise exception 'Administrator access required.' using errcode='42501';
  end if;
  if p_student_id is null then raise exception 'Choose a student.'; end if;
  if v_class='' or v_key='' or not public.is_allowed_class_key(v_key) then
    raise exception 'Please choose a valid class.';
  end if;

  update public.students s
  set class_name=v_class,class_key=v_key,updated_at=now()
  where s.id=p_student_id
  returning s.* into v_row;
  if v_row.id is null then raise exception 'Student profile not found.'; end if;

  return jsonb_build_object(
    'id',v_row.id,'name',v_row.name,
    'class_name',v_row.class_name,'class_key',v_row.class_key
  );
end;
$function$;

revoke all on function public.admin_set_student_class(uuid,text) from public, anon, authenticated;
grant execute on function public.admin_set_student_class(uuid,text) to authenticated;

