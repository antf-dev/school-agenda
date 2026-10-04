create or replace function public.admin_list_student_image_paths(p_student_id uuid)
returns setof text
language plpgsql
security definer
set search_path = public, storage
as $function$
begin
  if auth.uid() is null or not exists (
    select 1 from public.students me where me.id=auth.uid() and me.is_admin=true
  ) then
    raise exception 'Administrator access required.' using errcode='42501';
  end if;
  if p_student_id is null then raise exception 'Choose a student.'; end if;
  if exists(select 1 from public.students s where s.id=p_student_id and s.is_admin=true) then
    raise exception 'Administrator accounts cannot be removed from the student directory.' using errcode='42501';
  end if;

  return query
  select o.name
  from storage.objects o
  where o.bucket_id='class-agenda-images'
    and (o.owner_id=p_student_id::text or o.owner=p_student_id);
end;
$function$;

revoke all on function public.admin_list_student_image_paths(uuid) from public, anon, authenticated;
grant execute on function public.admin_list_student_image_paths(uuid) to authenticated;
