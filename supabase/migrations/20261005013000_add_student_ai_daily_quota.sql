create table if not exists public.student_ai_usage (
  student_id uuid not null references auth.users(id) on delete cascade,
  usage_date date not null default current_date,
  request_count integer not null default 0 check(request_count between 0 and 30),
  primary key(student_id,usage_date)
);
alter table public.student_ai_usage enable row level security;
drop policy if exists student_ai_usage_read_self on public.student_ai_usage;
create policy student_ai_usage_read_self on public.student_ai_usage for select to authenticated using(student_id=auth.uid());
grant select on public.student_ai_usage to authenticated;

create or replace function public.consume_student_ai_request()
returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare n integer;
begin
 if auth.uid() is null then raise exception 'Authentication required.'; end if;
 if not exists(select 1 from public.students where id=auth.uid()) then raise exception 'Student profile not found.'; end if;
 insert into public.student_ai_usage(student_id,usage_date,request_count) values(auth.uid(),current_date,1)
 on conflict(student_id,usage_date) do update set request_count=public.student_ai_usage.request_count+1
 where public.student_ai_usage.request_count<30
 returning request_count into n;
 if n is null then raise exception 'Daily study assistant limit reached. Try again tomorrow.'; end if;
 return n;
end $$;
revoke all on function public.consume_student_ai_request() from public, anon;
grant execute on function public.consume_student_ai_request() to authenticated;