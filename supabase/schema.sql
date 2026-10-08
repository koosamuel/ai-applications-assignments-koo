create table if not exists public.assignment_editors (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.assignment_sections (
  assignment_key text primary key
    check (assignment_key in ('task1', 'team', 'task3', 'task4', 'task5', 'task6')),
  title text not null,
  status_label text not null,
  summary text not null,
  headline_metric text,
  published boolean not null default false,
  updated_at timestamptz not null default now()
);

alter table public.assignment_editors enable row level security;
alter table public.assignment_sections enable row level security;
alter table public.assignment_sections replica identity full;

revoke all on public.assignment_editors from anon, authenticated;
revoke all on public.assignment_sections from anon, authenticated;
grant select on public.assignment_sections to anon, authenticated;
grant insert, update, delete on public.assignment_sections to authenticated;
grant select on public.assignment_editors to authenticated;

drop policy if exists "Editors can read their own row" on public.assignment_editors;
create policy "Editors can read their own row"
on public.assignment_editors for select
to authenticated
using (auth.uid() is not null and auth.uid() = user_id);

drop policy if exists "Anyone can read published assignment sections" on public.assignment_sections;
create policy "Anyone can read published assignment sections"
on public.assignment_sections for select
to anon, authenticated
using (published = true);

drop policy if exists "Editors can insert assignment sections" on public.assignment_sections;
create policy "Editors can insert assignment sections"
on public.assignment_sections for insert
to authenticated
with check (
  auth.uid() is not null
  and exists (
    select 1 from public.assignment_editors
    where assignment_editors.user_id = auth.uid()
  )
);

drop policy if exists "Editors can update assignment sections" on public.assignment_sections;
create policy "Editors can update assignment sections"
on public.assignment_sections for update
to authenticated
using (
  auth.uid() is not null
  and exists (
    select 1 from public.assignment_editors
    where assignment_editors.user_id = auth.uid()
  )
)
with check (
  auth.uid() is not null
  and exists (
    select 1 from public.assignment_editors
    where assignment_editors.user_id = auth.uid()
  )
);

drop policy if exists "Editors can delete assignment sections" on public.assignment_sections;
create policy "Editors can delete assignment sections"
on public.assignment_sections for delete
to authenticated
using (
  auth.uid() is not null
  and exists (
    select 1 from public.assignment_editors
    where assignment_editors.user_id = auth.uid()
  )
);

create or replace function public.touch_assignment_section()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists touch_assignment_section on public.assignment_sections;
create trigger touch_assignment_section
before update on public.assignment_sections
for each row execute function public.touch_assignment_section();

-- Server-only API usage ledger. Prompts, responses, names and API keys are never stored.
create table if not exists public.api_usage_daily (
  usage_date date primary key,
  daily_limit_microusd bigint not null check (daily_limit_microusd > 0),
  spent_microusd bigint not null default 0 check (spent_microusd >= 0),
  reserved_microusd bigint not null default 0 check (reserved_microusd >= 0),
  request_count bigint not null default 0 check (request_count >= 0),
  input_tokens bigint not null default 0 check (input_tokens >= 0),
  output_tokens bigint not null default 0 check (output_tokens >= 0),
  cache_creation_input_tokens bigint not null default 0
    check (cache_creation_input_tokens >= 0),
  cache_read_input_tokens bigint not null default 0
    check (cache_read_input_tokens >= 0),
  updated_at timestamptz not null default now()
);

create table if not exists public.api_usage_events (
  event_id uuid primary key,
  usage_date date not null references public.api_usage_daily(usage_date) on delete restrict,
  source text not null,
  model text not null,
  status text not null check (status in ('reserved', 'completed', 'upstream_error')),
  estimated_microusd bigint not null check (estimated_microusd > 0),
  actual_microusd bigint not null default 0 check (actual_microusd >= 0),
  input_tokens bigint not null default 0 check (input_tokens >= 0),
  output_tokens bigint not null default 0 check (output_tokens >= 0),
  cache_creation_input_tokens bigint not null default 0
    check (cache_creation_input_tokens >= 0),
  cache_read_input_tokens bigint not null default 0
    check (cache_read_input_tokens >= 0),
  created_at timestamptz not null default now(),
  settled_at timestamptz
);

alter table public.api_usage_events
drop constraint if exists api_usage_events_status_check;
alter table public.api_usage_events
add constraint api_usage_events_status_check
check (status in ('reserved', 'completed', 'upstream_error'));

-- Per-client abuse guard. Only a salted one-way hash is stored; raw IP addresses
-- and user-agent strings are never written to the database.
create table if not exists public.api_rate_limit_windows (
  window_start timestamptz not null,
  client_hash text not null check (client_hash ~ '^[0-9a-f]{64}$'),
  request_count integer not null default 0 check (request_count >= 0),
  updated_at timestamptz not null default now(),
  primary key (window_start, client_hash)
);

create index if not exists api_usage_events_usage_date_idx
on public.api_usage_events (usage_date, created_at);

alter table public.api_usage_daily enable row level security;
alter table public.api_usage_events enable row level security;
alter table public.api_rate_limit_windows enable row level security;
revoke all on public.api_usage_daily from anon, authenticated;
revoke all on public.api_usage_events from anon, authenticated;
revoke all on public.api_rate_limit_windows from anon, authenticated;
grant select, insert, update on public.api_usage_daily to service_role;
grant select, insert, update on public.api_usage_events to service_role;
grant select, insert, update, delete on public.api_rate_limit_windows to service_role;

create or replace function public.consume_api_rate_limit(
  p_client_hash text,
  p_window_start timestamptz,
  p_request_limit integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_window_start timestamptz;
  v_request_count integer;
begin
  if p_client_hash !~ '^[0-9a-f]{64}$'
    or p_window_start is null
    or p_request_limit < 1
    or p_request_limit > 60 then
    raise exception 'invalid rate-limit request';
  end if;

  v_window_start := date_trunc('minute', p_window_start);

  insert into public.api_rate_limit_windows (
    window_start,
    client_hash,
    request_count
  ) values (
    v_window_start,
    p_client_hash,
    1
  )
  on conflict (window_start, client_hash) do update
  set
    request_count = public.api_rate_limit_windows.request_count + 1,
    updated_at = now()
  returning request_count into v_request_count;

  delete from public.api_rate_limit_windows
  where window_start < now() - interval '2 days';

  return jsonb_build_object(
    'allowed', v_request_count <= p_request_limit,
    'request_count', v_request_count,
    'request_limit', p_request_limit
  );
end;
$$;

create or replace function public.expire_stale_api_reservations(
  p_stale_before timestamptz
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event record;
  v_expired bigint := 0;
begin
  if p_stale_before is null or p_stale_before > now() then
    raise exception 'invalid stale reservation cutoff';
  end if;

  for v_event in
    select event_id, usage_date, estimated_microusd
    from public.api_usage_events
    where status = 'reserved'
      and created_at < p_stale_before
    order by created_at
    limit 100
    for update skip locked
  loop
    update public.api_usage_daily
    set
      reserved_microusd = greatest(
        0,
        reserved_microusd - v_event.estimated_microusd
      ),
      spent_microusd = spent_microusd + v_event.estimated_microusd,
      updated_at = now()
    where usage_date = v_event.usage_date;

    update public.api_usage_events
    set
      status = 'upstream_error',
      actual_microusd = estimated_microusd,
      settled_at = now()
    where event_id = v_event.event_id;

    v_expired := v_expired + 1;
  end loop;

  return v_expired;
end;
$$;

create or replace function public.reserve_api_daily_budget(
  p_event_id uuid,
  p_usage_date date,
  p_source text,
  p_model text,
  p_estimated_microusd bigint,
  p_daily_limit_microusd bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_spent bigint;
  v_reserved bigint;
begin
  if p_event_id is null
    or p_usage_date is null
    or coalesce(length(trim(p_source)), 0) = 0
    or coalesce(length(trim(p_model)), 0) = 0
    or p_estimated_microusd <= 0
    or p_daily_limit_microusd <= 0 then
    raise exception 'invalid budget reservation';
  end if;

  perform public.expire_stale_api_reservations(
    now() - interval '15 minutes'
  );

  insert into public.api_usage_daily (usage_date, daily_limit_microusd)
  values (p_usage_date, p_daily_limit_microusd)
  on conflict (usage_date) do update
  set daily_limit_microusd = least(
    public.api_usage_daily.daily_limit_microusd,
    excluded.daily_limit_microusd
  );

  select spent_microusd, reserved_microusd
  into v_spent, v_reserved
  from public.api_usage_daily
  where usage_date = p_usage_date
  for update;

  if exists (
    select 1 from public.api_usage_events where event_id = p_event_id
  ) then
    raise exception 'duplicate budget event';
  end if;

  if v_spent + v_reserved + p_estimated_microusd > p_daily_limit_microusd then
    return jsonb_build_object(
      'allowed', false,
      'spent_microusd', v_spent,
      'reserved_microusd', v_reserved,
      'daily_limit_microusd', p_daily_limit_microusd
    );
  end if;

  insert into public.api_usage_events (
    event_id,
    usage_date,
    source,
    model,
    status,
    estimated_microusd
  ) values (
    p_event_id,
    p_usage_date,
    trim(p_source),
    trim(p_model),
    'reserved',
    p_estimated_microusd
  );

  update public.api_usage_daily
  set
    reserved_microusd = reserved_microusd + p_estimated_microusd,
    request_count = request_count + 1,
    updated_at = now()
  where usage_date = p_usage_date;

  return jsonb_build_object(
    'allowed', true,
    'spent_microusd', v_spent,
    'reserved_microusd', v_reserved + p_estimated_microusd,
    'daily_limit_microusd', p_daily_limit_microusd
  );
end;
$$;

create or replace function public.finalize_api_daily_usage(
  p_event_id uuid,
  p_actual_microusd bigint,
  p_input_tokens bigint,
  p_output_tokens bigint,
  p_cache_creation_input_tokens bigint,
  p_cache_read_input_tokens bigint,
  p_status text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_usage_date date;
  v_estimated_microusd bigint;
  v_status text;
begin
  if p_actual_microusd < 0
    or p_input_tokens < 0
    or p_output_tokens < 0
    or p_cache_creation_input_tokens < 0
    or p_cache_read_input_tokens < 0
    or p_status not in ('completed', 'upstream_error') then
    raise exception 'invalid budget settlement';
  end if;

  select usage_date, estimated_microusd, status
  into v_usage_date, v_estimated_microusd, v_status
  from public.api_usage_events
  where event_id = p_event_id
  for update;

  if not found then
    return false;
  end if;
  if v_status <> 'reserved' then
    return true;
  end if;

  update public.api_usage_daily
  set
    reserved_microusd = greatest(0, reserved_microusd - v_estimated_microusd),
    spent_microusd = spent_microusd + p_actual_microusd,
    input_tokens = input_tokens + p_input_tokens,
    output_tokens = output_tokens + p_output_tokens,
    cache_creation_input_tokens = cache_creation_input_tokens
      + p_cache_creation_input_tokens,
    cache_read_input_tokens = cache_read_input_tokens + p_cache_read_input_tokens,
    updated_at = now()
  where usage_date = v_usage_date;

  update public.api_usage_events
  set
    status = p_status,
    actual_microusd = p_actual_microusd,
    input_tokens = p_input_tokens,
    output_tokens = p_output_tokens,
    cache_creation_input_tokens = p_cache_creation_input_tokens,
    cache_read_input_tokens = p_cache_read_input_tokens,
    settled_at = now()
  where event_id = p_event_id;

  return true;
end;
$$;

revoke all on function public.reserve_api_daily_budget(
  uuid, date, text, text, bigint, bigint
) from public, anon, authenticated;
revoke all on function public.finalize_api_daily_usage(
  uuid, bigint, bigint, bigint, bigint, bigint, text
) from public, anon, authenticated;
revoke all on function public.consume_api_rate_limit(
  text, timestamptz, integer
) from public, anon, authenticated;
revoke all on function public.expire_stale_api_reservations(
  timestamptz
) from public, anon, authenticated;
grant execute on function public.reserve_api_daily_budget(
  uuid, date, text, text, bigint, bigint
) to service_role;
grant execute on function public.finalize_api_daily_usage(
  uuid, bigint, bigint, bigint, bigint, bigint, text
) to service_role;
grant execute on function public.consume_api_rate_limit(
  text, timestamptz, integer
) to service_role;
grant execute on function public.expire_stale_api_reservations(
  timestamptz
) to service_role;

insert into public.assignment_sections
  (assignment_key, title, status_label, summary, headline_metric, published)
values
  ('task1', '초개인화 금융상품 추천', '로컬 검증 완료', '개인정보 외부 전송 없이 추천 기준선을 비교했습니다.', '20/20 개선 규칙 일치', true),
  ('team', 'StepUp English 회화 챗봇', '실제 팀 검증 대기', 'CEFR 적응형 회화 흐름과 B2→C1 합성 시나리오를 구현했습니다.', '합성 시나리오 3개', true),
  ('task3', '그림·감정 기반 이야기 생성', 'API 실행 완료', '그림 4장과 행복 감정으로 민들레 이야기를 생성했습니다.', '캡션 4개·이야기 1편', true),
  ('task4', '역사적 인물 챗봇', '3턴 검증 완료', '아인슈타인 페르소나와 사실 경계를 적용했습니다.', '대화 3턴', true),
  ('task5', '텍스트 쿼리 이미지 검색', '검색 검증 완료', '세 질의 모두 정답 이미지를 1위로 반환했습니다.', 'Top-1 3/3', true),
  ('task6', '논문 유사도 기반 군집화', '군집화 완료', '금융 논문 9편을 세 군집으로 분류했습니다.', 'k=3·실루엣 0.145', true)
on conflict (assignment_key) do update
set
  title = excluded.title,
  status_label = excluded.status_label,
  summary = excluded.summary,
  headline_metric = excluded.headline_metric,
  published = excluded.published;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'assignment_sections'
  ) then
    alter publication supabase_realtime add table public.assignment_sections;
  end if;
end
$$;
