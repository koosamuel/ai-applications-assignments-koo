create table if not exists public.assignment_editors (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.assignment_sections (
  assignment_key text primary key
    check (assignment_key in ('task1', 'task3', 'task4', 'task5', 'task6')),
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

insert into public.assignment_sections
  (assignment_key, title, status_label, summary, headline_metric, published)
values
  ('task1', '초개인화 금융상품 추천', '로컬 검증 완료', '개인정보 외부 전송 없이 추천 기준선을 비교했습니다.', '20/20 개선 규칙 일치', true),
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
