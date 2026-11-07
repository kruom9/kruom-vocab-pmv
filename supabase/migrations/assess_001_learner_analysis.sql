-- assess_001_learner_analysis.sql
-- Learner-analysis module for โรงเรียนปิยมิตรวิทยา.
-- EVERY object created here is named assess_* (tables, indexes, policies, functions, sequences).
-- This file does not read, write, drop, or rename vocab_*, vocab__bak*, or exam-gym objects
-- (grades, subjects, strands, items, exam_sets, profiles, teacher_scopes, attempts, answers,
--  sections, teacher_section_scopes, roster_*, legacy_*).
-- Safe to apply once inside a transaction. A second apply stops at the guard below.
-- Demo accounts: every assess_users password is demo. Only a bcrypt hash is inserted; plaintext is not stored.
-- Sample students are fictional (names contain ตัวอย่าง, codes PMW-*). Do not import vocab_students or national IDs.
-- Access pattern matches vocab_*: RLS on, no anon table grants, session token checked inside security-definer RPCs.

do $assess_roles$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    raise exception 'assess_001 expects Supabase role anon';
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    raise exception 'assess_001 expects Supabase role authenticated';
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    raise exception 'assess_001 expects Supabase role service_role';
  end if;
end
$assess_roles$;

do $assess_guard$
begin
  if to_regclass('public.assess_users') is not null then
    raise exception 'assess_001 already applied';
  end if;
end
$assess_guard$;

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------------
-- Tables (assess_* only)
-- ---------------------------------------------------------------------------

create table public.assess_users (
  id uuid primary key default gen_random_uuid(),
  username text not null unique check (username ~ '^[a-z0-9-]{3,32}$'),
  password_hash text not null check (password_hash ~ '^\$2[ab]\$'),
  role text not null check (role in ('admin', 'teacher', 'counselor', 'parent', 'student')),
  display_name text not null,
  created_at timestamptz not null default now()
);
comment on table public.assess_users is 'assess_* only. Learner-analysis accounts. password_hash is bcrypt. Not vocab_*.';

create table public.assess_sessions (
  token_hash text primary key,
  user_id uuid not null references public.assess_users (id) on delete cascade,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);
comment on table public.assess_sessions is 'assess_* only. SHA-256 of session tokens. Raw tokens are not stored.';

create table public.assess_login_failures (
  id bigint generated always as identity primary key,
  username text not null,
  at timestamptz not null default now()
);
comment on table public.assess_login_failures is 'assess_* only. Failed assess_login attempts. No passwords.';

create table public.assess_students (
  id text primary key,
  sort_no integer not null unique,
  code text not null unique,
  name text not null,
  display_name text not null,
  grade text not null,
  band text not null check (band in ('early_primary', 'late_primary', 'lower_secondary', 'upper_secondary')),
  gender text,
  status text not null check (status in ('started', 'incomplete', 'pending', 'approved')),
  teacher_note text,
  seed jsonb not null default '{}'::jsonb,
  fictional boolean not null default true,
  created_at timestamptz not null default now()
);
comment on table public.assess_students is 'assess_* only. Fictional sample learners. Not vocab_students. No national IDs.';

create table public.assess_user_students (
  user_id uuid not null references public.assess_users (id) on delete cascade,
  student_id text not null references public.assess_students (id) on delete cascade,
  primary key (user_id, student_id)
);
comment on table public.assess_user_students is 'assess_* only. Which fictional students a parent or student account may open.';

create table public.assess_catalog (
  id smallint primary key check (id = 1),
  doc jsonb not null,
  updated_at timestamptz not null default now()
);
comment on table public.assess_catalog is 'assess_* only. Original Thai instrument text (not a trademarked test).';

create table public.assess_items (
  item_id text primary key,
  kind text not null check (kind in ('aptitude', 'work', 'ability', 'psych', 'exercises', 'personality', 'parent', 'rubric')),
  domain text,
  band text,
  sort_no integer not null,
  body jsonb not null
);
comment on table public.assess_items is 'assess_* only. One row per original assessment item, expanded from assess_catalog.';

create table public.assess_responses (
  student_id text not null references public.assess_students (id) on delete cascade,
  item_id text not null references public.assess_items (item_id),
  value_num numeric check (value_num is null or (value_num >= 1 and value_num <= 5)),
  value_text text check (value_text is null or char_length(value_text) <= 2000),
  updated_by uuid references public.assess_users (id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key (student_id, item_id),
  check (value_num is not null or value_text is not null)
);
comment on table public.assess_responses is 'assess_* only. Item answers, exercise text, parent questionnaire, rubric, personality notes.';

create table public.assess_progress (
  student_id text not null references public.assess_students (id) on delete cascade,
  module text not null check (module in ('aptitude', 'ability', 'psych', 'work', 'exercises', 'personality')),
  done boolean not null default false,
  pct integer not null check (pct >= 0 and pct <= 100),
  updated_at timestamptz not null default now(),
  primary key (student_id, module)
);
comment on table public.assess_progress is 'assess_* only. Per-module completion for a fictional student.';

create table public.assess_reports (
  student_id text primary key references public.assess_students (id) on delete cascade,
  status text not null check (status in ('pending', 'approved')),
  summary text not null,
  report jsonb not null,
  approved_by uuid references public.assess_users (id) on delete set null,
  approved_at timestamptz,
  updated_at timestamptz not null default now()
);
comment on table public.assess_reports is 'assess_* only. 3-pillar analysis, teacher-edited summary, and approval state.';

create table public.assess_pathways (
  id bigint generated always as identity primary key,
  student_id text not null references public.assess_students (id) on delete cascade,
  ord integer not null check (ord >= 1 and ord <= 3),
  title text not null,
  reason text,
  path_type text,
  unique (student_id, ord)
);
comment on table public.assess_pathways is 'assess_* only. Two or three individual pathways stored with each report.';

create index assess_sessions_user_idx on public.assess_sessions (user_id);
create index assess_sessions_expires_idx on public.assess_sessions (expires_at);
create index assess_login_failures_user_idx on public.assess_login_failures (username, at);
create index assess_user_students_student_idx on public.assess_user_students (student_id);
create index assess_items_kind_idx on public.assess_items (kind, domain);
create index assess_items_band_idx on public.assess_items (band);
create index assess_responses_student_idx on public.assess_responses (student_id);
create index assess_pathways_student_idx on public.assess_pathways (student_id, ord);

-- RLS on, deny anon/authenticated. Table owner bypasses RLS so security-definer RPCs can read.
-- Do not FORCE row security: that would hide rows from the function owner and break the RPCs.
-- This matches vocab_* (RLS enabled, relforcerowsecurity false, access only through token RPCs).

alter table public.assess_users enable row level security;
alter table public.assess_sessions enable row level security;
alter table public.assess_login_failures enable row level security;
alter table public.assess_students enable row level security;
alter table public.assess_user_students enable row level security;
alter table public.assess_catalog enable row level security;
alter table public.assess_items enable row level security;
alter table public.assess_responses enable row level security;
alter table public.assess_progress enable row level security;
alter table public.assess_reports enable row level security;
alter table public.assess_pathways enable row level security;

create policy assess_users_deny_api on public.assess_users for all to anon, authenticated using (false) with check (false);
create policy assess_sessions_deny_api on public.assess_sessions for all to anon, authenticated using (false) with check (false);
create policy assess_login_failures_deny_api on public.assess_login_failures for all to anon, authenticated using (false) with check (false);
create policy assess_students_deny_api on public.assess_students for all to anon, authenticated using (false) with check (false);
create policy assess_user_students_deny_api on public.assess_user_students for all to anon, authenticated using (false) with check (false);
create policy assess_catalog_deny_api on public.assess_catalog for all to anon, authenticated using (false) with check (false);
create policy assess_items_deny_api on public.assess_items for all to anon, authenticated using (false) with check (false);
create policy assess_responses_deny_api on public.assess_responses for all to anon, authenticated using (false) with check (false);
create policy assess_progress_deny_api on public.assess_progress for all to anon, authenticated using (false) with check (false);
create policy assess_reports_deny_api on public.assess_reports for all to anon, authenticated using (false) with check (false);
create policy assess_pathways_deny_api on public.assess_pathways for all to anon, authenticated using (false) with check (false);

revoke all on table public.assess_users from public, anon, authenticated;
revoke all on table public.assess_sessions from public, anon, authenticated;
revoke all on table public.assess_login_failures from public, anon, authenticated;
revoke all on table public.assess_students from public, anon, authenticated;
revoke all on table public.assess_user_students from public, anon, authenticated;
revoke all on table public.assess_catalog from public, anon, authenticated;
revoke all on table public.assess_items from public, anon, authenticated;
revoke all on table public.assess_responses from public, anon, authenticated;
revoke all on table public.assess_progress from public, anon, authenticated;
revoke all on table public.assess_reports from public, anon, authenticated;
revoke all on table public.assess_pathways from public, anon, authenticated;

revoke all on sequence public.assess_login_failures_id_seq from public, anon, authenticated;
revoke all on sequence public.assess_pathways_id_seq from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Helpers. Not granted to anon/authenticated. Called only from assess_* RPCs.
-- ---------------------------------------------------------------------------

create function public.assess__hash(p text)
returns text
language sql
immutable
set search_path = public, extensions
as $fn$
  select encode(extensions.digest(coalesce(p, ''), 'sha256'), 'hex');
$fn$;
comment on function public.assess__hash(text) is 'assess_* only. Internal token hash. Not an API.';

create function public.assess__new_token()
returns text
language sql
volatile
set search_path = public, extensions
as $fn$
  select encode(extensions.gen_random_bytes(32), 'hex');
$fn$;
comment on function public.assess__new_token() is 'assess_* only. Internal session token. Not an API.';

create function public.assess__user(p_token text)
returns public.assess_users
language plpgsql
stable
security definer
set search_path = public, extensions
as $fn$
declare
  rec public.assess_users;
begin
  select u.* into rec
  from public.assess_sessions s
  join public.assess_users u on u.id = s.user_id
  where s.token_hash = public.assess__hash(coalesce(p_token, ''))
    and s.expires_at > now();
  if not found then
    raise exception 'NO_SESSION';
  end if;
  return rec;
end
$fn$;
comment on function public.assess__user(text) is 'assess_* only. Resolve a live session or raise NO_SESSION. Not granted to anon.';

create function public.assess__can_see(p_user uuid, p_role text, p_student text)
returns boolean
language sql
stable
set search_path = public
as $fn$
  select p_role in ('admin', 'teacher', 'counselor')
      or exists (
        select 1 from public.assess_user_students us
        where us.user_id = p_user and us.student_id = p_student
      );
$fn$;
comment on function public.assess__can_see(uuid, text, text) is 'assess_* only. Internal visibility check. Not an API.';

create function public.assess__require_student(p_user uuid, p_role text, p_student text)
returns void
language plpgsql
stable
set search_path = public
as $fn$
begin
  if p_student is null or p_student = '' or not exists (
    select 1 from public.assess_students s where s.id = p_student
  ) then
    raise exception 'NO_STUDENT';
  end if;
  if not public.assess__can_see(p_user, p_role, p_student) then
    raise exception 'FORBIDDEN';
  end if;
end
$fn$;
comment on function public.assess__require_student(uuid, text, text) is 'assess_* only. Internal. Not an API.';

create function public.assess__reject_banned(p_text text)
returns void
language plpgsql
immutable
set search_path = public
as $fn$
begin
  if p_text is null then
    return;
  end if;
  if p_text ~ 'ศักยภาพต่ำ' or p_text ~ 'ไอคิว' then
    raise exception 'BAD_CONTENT';
  end if;
  if p_text ~* '(WISC|Stanford[- ]?Binet|\mRaven\M|\mMBTI\M|Holland|\mSDS\M|EQ-i|Big Five|พหุปัญญา)' then
    raise exception 'BAD_CONTENT';
  end if;
  if p_text ~* '\mIQ\M' then
    raise exception 'BAD_CONTENT';
  end if;
end
$fn$;
comment on function public.assess__reject_banned(text) is 'assess_* only. Blocks fixed-IQ wording and trademarked instrument names. Not an API.';

create function public.assess__answers(p_student text, p_include_psych boolean)
returns jsonb
language sql
stable
set search_path = public
as $fn$
  select jsonb_strip_nulls(jsonb_build_object(
    'aptitude', (
      select jsonb_object_agg(s.domain, s.items)
      from (
        select i.domain, jsonb_object_agg(i.item_id, r.value_num) as items
        from public.assess_responses r
        join public.assess_items i on i.item_id = r.item_id
        where r.student_id = p_student and i.kind = 'aptitude' and r.value_num is not null
        group by i.domain
      ) s
    ),
    'work', (
      select jsonb_object_agg(s.domain, s.items)
      from (
        select i.domain, jsonb_object_agg(i.item_id, r.value_num) as items
        from public.assess_responses r
        join public.assess_items i on i.item_id = r.item_id
        where r.student_id = p_student and i.kind = 'work' and r.value_num is not null
        group by i.domain
      ) s
    ),
    'ability', (
      select jsonb_object_agg(i.item_id, r.value_num)
      from public.assess_responses r
      join public.assess_items i on i.item_id = r.item_id
      where r.student_id = p_student and i.kind = 'ability' and r.value_num is not null
    ),
    'exercises', (
      select jsonb_object_agg(i.item_id, r.value_text)
      from public.assess_responses r
      join public.assess_items i on i.item_id = r.item_id
      where r.student_id = p_student and i.kind = 'exercises' and r.value_text is not null
    ),
    'psych', case when p_include_psych then (
      select jsonb_object_agg(s.domain, s.items)
      from (
        select i.domain, jsonb_object_agg(i.item_id, r.value_num) as items
        from public.assess_responses r
        join public.assess_items i on i.item_id = r.item_id
        where r.student_id = p_student and i.kind = 'psych' and r.value_num is not null
        group by i.domain
      ) s
    ) else null end
  ));
$fn$;
comment on function public.assess__answers(text, boolean) is 'assess_* only. Rebuild the prototype answer shape. Not an API.';

create function public.assess__form(p_student text, p_kind text)
returns jsonb
language sql
stable
set search_path = public
as $fn$
  select coalesce((
    select jsonb_object_agg(
      i.item_id,
      case
        when r.value_text is not null and r.value_num is null then to_jsonb(r.value_text)
        else to_jsonb(r.value_num)
      end
    )
    from public.assess_responses r
    join public.assess_items i on i.item_id = r.item_id
    where r.student_id = p_student and i.kind = p_kind
  ), '{}'::jsonb);
$fn$;
comment on function public.assess__form(text, text) is 'assess_* only. Parent, rubric, or personality answers. Not an API.';

create function public.assess__progress(p_student text)
returns jsonb
language sql
stable
set search_path = public
as $fn$
  select coalesce((
    select jsonb_object_agg(module, jsonb_build_object('done', done, 'pct', pct))
    from public.assess_progress
    where student_id = p_student
  ), '{}'::jsonb);
$fn$;
comment on function public.assess__progress(text) is 'assess_* only. Module progress object. Not an API.';

create function public.assess__visible_report(
  p_role text,
  p_status text,
  p_report jsonb,
  p_approved_by text,
  p_approved_at timestamptz
)
returns jsonb
language plpgsql
immutable
set search_path = public
as $fn$
begin
  if p_report is null then
    return jsonb_build_object('status', p_status);
  end if;
  if p_role = 'admin' then
    return jsonb_build_object('status', p_status);
  end if;
  if p_role in ('parent', 'student') and p_status is distinct from 'approved' then
    return jsonb_build_object('status', p_status);
  end if;
  if p_role in ('parent', 'student') then
    return (p_report - 'psych') || jsonb_build_object(
      'status', p_status,
      'approvedBy', p_approved_by,
      'approvedAt', p_approved_at
    );
  end if;
  if p_role = 'teacher' then
    return p_report || jsonb_build_object(
      'status', p_status,
      'approvedBy', p_approved_by,
      'approvedAt', p_approved_at,
      'psych', jsonb_build_object(
        'motivation', coalesce(p_report #> '{psych,motivation}', 'null'::jsonb),
        'note', 'เพื่อแนะแนว ไม่ใช่เพื่อวินิจฉัยโรค'
      )
    );
  end if;
  if p_role = 'counselor' then
    return p_report || jsonb_build_object(
      'status', p_status,
      'approvedBy', p_approved_by,
      'approvedAt', p_approved_at
    );
  end if;
  return jsonb_build_object('status', p_status);
end
$fn$;
comment on function public.assess__visible_report(text, text, jsonb, text, timestamptz) is 'assess_* only. Strip psychology and unapproved text by role. Not an API.';

-- ---------------------------------------------------------------------------
-- Public RPCs. anon may execute these only. Each one checks the session token.
-- ---------------------------------------------------------------------------

create function public.assess_login(p_username text, p_password text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, extensions
as $fn$
declare
  v_name text := lower(btrim(coalesce(p_username, '')));
  u public.assess_users;
  fails integer;
  tok text;
begin
  delete from public.assess_login_failures where at < now() - interval '1 day';
  delete from public.assess_sessions where expires_at < now() - interval '1 day';
  if v_name !~ '^[a-z0-9-]{3,32}$'
     or p_password is null
     or char_length(p_password) < 1
     or char_length(p_password) > 200 then
    return jsonb_build_object('error', 'BAD_LOGIN');
  end if;
  select count(*) into fails
  from public.assess_login_failures
  where username = v_name and at > now() - interval '10 minutes';
  if fails >= 10 then
    return jsonb_build_object('error', 'LOCKED');
  end if;
  select * into u from public.assess_users where username = v_name;
  if not found or u.password_hash is distinct from extensions.crypt(p_password, u.password_hash) then
    insert into public.assess_login_failures (username) values (v_name);
    return jsonb_build_object('error', 'BAD_LOGIN');
  end if;
  delete from public.assess_login_failures where username = v_name;
  tok := public.assess__new_token();
  insert into public.assess_sessions (token_hash, user_id, expires_at)
  values (public.assess__hash(tok), u.id, now() + interval '12 hours');
  return jsonb_build_object(
    'token', tok,
    'name', u.display_name,
    'role', u.role,
    'username', u.username
  );
end
$fn$;
comment on function public.assess_login(text, text) is 'assess_* only. Verify bcrypt password and return a session token. No plaintext is stored.';

create function public.assess_logout(p_token text)
returns boolean
language plpgsql
volatile
security definer
set search_path = public, extensions
as $fn$
begin
  delete from public.assess_sessions
  where token_hash = public.assess__hash(coalesce(p_token, ''));
  return true;
end
$fn$;
comment on function public.assess_logout(text) is 'assess_* only. Drop one session token.';

create function public.assess_bootstrap(p_token text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, extensions
as $fn$
declare
  u public.assess_users;
  rec record;
  v_students jsonb;
  v_answers jsonb := '{}'::jsonb;
  v_progress jsonb := '{}'::jsonb;
  v_reports jsonb := '{}'::jsonb;
  v_notes jsonb := '{}'::jsonb;
  v_home jsonb := '{}'::jsonb;
  v_pers jsonb := '{}'::jsonb;
  v_status text;
  v_rep jsonb;
  v_by text;
  v_at timestamptz;
  v_psych boolean;
  v_with_answers boolean;
begin
  u := public.assess__user(p_token);
  v_psych := u.role in ('student', 'teacher', 'counselor');
  v_with_answers := u.role in ('student', 'teacher', 'counselor');
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', s.id,
      'code', s.code,
      'name', s.name,
      'display', s.display_name,
      'grade', s.grade,
      'band', s.band,
      'gender', s.gender,
      'status', s.status,
      'fictional', s.fictional,
      'teacherNote', case when u.role in ('teacher', 'counselor') then s.teacher_note else null end,
      'seed', case when u.role in ('teacher', 'counselor', 'student') then s.seed else null end
    ) order by s.sort_no
  ), '[]'::jsonb)
  into v_students
  from public.assess_students s
  where public.assess__can_see(u.id, u.role, s.id);

  for rec in
    select s.id
    from public.assess_students s
    where public.assess__can_see(u.id, u.role, s.id)
    order by s.sort_no
  loop
    if v_with_answers then
      v_answers := v_answers || jsonb_build_object(rec.id, public.assess__answers(rec.id, v_psych));
    end if;
    v_progress := v_progress || jsonb_build_object(rec.id, public.assess__progress(rec.id));
    v_status := null;
    v_rep := null;
    v_by := null;
    v_at := null;
    select r.status, r.report, au.display_name, r.approved_at
      into v_status, v_rep, v_by, v_at
    from public.assess_reports r
    left join public.assess_users au on au.id = r.approved_by
    where r.student_id = rec.id;
    if found then
      v_reports := v_reports || jsonb_build_object(
        rec.id,
        public.assess__visible_report(u.role, v_status, v_rep, v_by, v_at)
      );
    end if;
    if u.role in ('teacher', 'counselor') then
      v_notes := v_notes || jsonb_build_object(rec.id, public.assess__form(rec.id, 'rubric'));
    end if;
    if u.role in ('parent', 'teacher', 'counselor') then
      v_home := v_home || jsonb_build_object(rec.id, public.assess__form(rec.id, 'parent'));
    end if;
    if u.role in ('student', 'teacher', 'counselor') then
      v_pers := v_pers || jsonb_build_object(rec.id, public.assess__form(rec.id, 'personality'));
    end if;
  end loop;

  return jsonb_build_object(
    'user', jsonb_build_object('username', u.username, 'role', u.role, 'name', u.display_name),
    'students', v_students,
    'catalog', (select doc from public.assess_catalog where id = 1),
    'store', jsonb_build_object(
      'answers', v_answers,
      'progress', v_progress,
      'reports', v_reports,
      'teacherNotes', v_notes,
      'parentHome', v_home,
      'personality', v_pers
    )
  );
end
$fn$;
comment on function public.assess_bootstrap(text) is 'assess_* only. Role-filtered students, catalog, answers, reports. Hides individual psychology from admin and unapproved text from parents.';

create function public.assess_save_module(
  p_token text,
  p_student text,
  p_module text,
  p_answers jsonb,
  p_done boolean,
  p_pct integer
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, extensions
as $fn$
declare
  u public.assess_users;
  v_student text := btrim(coalesce(p_student, ''));
  v_done boolean;
  v_band text;
begin
  u := public.assess__user(p_token);
  if u.role not in ('student', 'teacher', 'counselor') then
    raise exception 'FORBIDDEN';
  end if;
  if p_module not in ('aptitude', 'work', 'ability', 'psych', 'exercises') then
    raise exception 'BAD_MODULE';
  end if;
  if p_pct is null or p_pct < 0 or p_pct > 100 then
    raise exception 'BAD_PCT';
  end if;
  if p_answers is null or jsonb_typeof(p_answers) <> 'object' then
    raise exception 'BAD_ANSWERS';
  end if;
  perform public.assess__require_student(u.id, u.role, v_student);
  select band into v_band from public.assess_students where id = v_student;
  if p_module = 'work' and v_band <> 'upper_secondary' then
    raise exception 'BAD_MODULE';
  end if;
  v_done := coalesce(p_done, false) or p_pct = 100;

  delete from public.assess_responses r
  using public.assess_items i
  where r.item_id = i.item_id
    and r.student_id = v_student
    and i.kind = p_module;

  if p_module in ('aptitude', 'work', 'psych') then
    insert into public.assess_responses (student_id, item_id, value_num, updated_by, updated_at)
    select v_student, i.item_id, v.val::numeric, u.id, now()
    from jsonb_each(p_answers) as dom(key, value)
    cross join lateral jsonb_each_text(dom.value) as v(key, val)
    join public.assess_items i
      on i.item_id = v.key
     and i.kind = p_module
     and i.domain = dom.key
    where jsonb_typeof(dom.value) = 'object'
      and v.val ~ '^[1-5]$';
  elsif p_module = 'ability' then
    insert into public.assess_responses (student_id, item_id, value_num, updated_by, updated_at)
    select v_student, i.item_id, v.val::numeric, u.id, now()
    from jsonb_each_text(p_answers) as v(key, val)
    join public.assess_items i
      on i.item_id = v.key
     and i.kind = 'ability'
     and i.band = v_band
    where v.val ~ '^[1-4]$';
  elsif p_module = 'exercises' then
    insert into public.assess_responses (student_id, item_id, value_text, updated_by, updated_at)
    select v_student, i.item_id, left(btrim(v.val), 500), u.id, now()
    from jsonb_each_text(p_answers) as v(key, val)
    join public.assess_items i
      on i.item_id = v.key
     and i.kind = 'exercises'
     and i.band = v_band
    where char_length(btrim(v.val)) > 0;
  end if;

  insert into public.assess_progress (student_id, module, done, pct)
  values (v_student, p_module, v_done, p_pct)
  on conflict (student_id, module) do update
  set done = excluded.done, pct = excluded.pct, updated_at = now();

  return jsonb_build_object('ok', true, 'module', p_module, 'done', v_done, 'pct', p_pct);
end
$fn$;
comment on function public.assess_save_module(text, text, text, jsonb, boolean, integer) is 'assess_* only. Save aptitude, work, ability, guidance, or exercise answers for a visible student.';

create function public.assess_save_form(
  p_token text,
  p_student text,
  p_form text,
  p_values jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, extensions
as $fn$
declare
  u public.assess_users;
  v_student text := btrim(coalesce(p_student, ''));
begin
  u := public.assess__user(p_token);
  if p_form = 'parent' and u.role <> 'parent' then
    raise exception 'FORBIDDEN';
  elsif p_form = 'rubric' and u.role not in ('teacher', 'counselor') then
    raise exception 'FORBIDDEN';
  elsif p_form = 'personality' and u.role not in ('student', 'teacher', 'counselor') then
    raise exception 'FORBIDDEN';
  elsif p_form not in ('parent', 'rubric', 'personality') then
    raise exception 'BAD_FORM';
  end if;
  if p_values is null or jsonb_typeof(p_values) <> 'object' then
    raise exception 'BAD_ANSWERS';
  end if;
  perform public.assess__require_student(u.id, u.role, v_student);

  delete from public.assess_responses r
  using public.assess_items i
  where r.item_id = i.item_id
    and r.student_id = v_student
    and i.kind = p_form;

  insert into public.assess_responses (student_id, item_id, value_num, value_text, updated_by, updated_at)
  select v_student,
         i.item_id,
         case when i.body->>'type' = 'text' then null else v.val::numeric end,
         case when i.body->>'type' = 'text' then left(v.val, 2000) else null end,
         u.id,
         now()
  from jsonb_each_text(p_values) as v(key, val)
  join public.assess_items i on i.item_id = v.key and i.kind = p_form
  where (
    i.body->>'type' = 'text' and char_length(v.val) <= 2000
  ) or (
    coalesce(i.body->>'type', '') <> 'text'
    and exists (
      select 1 from jsonb_array_elements(coalesce(i.body->'options', '[]'::jsonb)) o
      where o->>'v' = v.val
    )
  );

  if p_form = 'personality' then
    insert into public.assess_progress (student_id, module, done, pct)
    values (v_student, 'personality', true, 100)
    on conflict (student_id, module) do update
    set done = true, pct = 100, updated_at = now();
  end if;
  return jsonb_build_object('ok', true, 'form', p_form);
end
$fn$;
comment on function public.assess_save_form(text, text, text, jsonb) is 'assess_* only. Parent questionnaire, teacher rubric, or personality module.';

create function public.assess_save_report(p_token text, p_student text, p_report jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, extensions
as $fn$
declare
  u public.assess_users;
  v_student text := btrim(coalesce(p_student, ''));
  v_report jsonb;
  v_summary text;
begin
  u := public.assess__user(p_token);
  if u.role not in ('student', 'teacher', 'counselor') then
    raise exception 'FORBIDDEN';
  end if;
  if p_report is null or jsonb_typeof(p_report) <> 'object' then
    raise exception 'BAD_REPORT';
  end if;
  if octet_length(p_report::text) > 120000 then
    raise exception 'BAD_REPORT';
  end if;
  perform public.assess__reject_banned(p_report::text);
  v_summary := btrim(coalesce(p_report->>'summary', ''));
  if char_length(v_summary) < 1 or char_length(v_summary) > 4000 then
    raise exception 'BAD_SUMMARY';
  end if;
  perform public.assess__reject_banned(v_summary);
  if jsonb_typeof(p_report->'aptitude') <> 'object'
     or jsonb_typeof(p_report->'ability') <> 'object'
     or jsonb_typeof(p_report->'pathways') <> 'array'
     or jsonb_array_length(p_report->'pathways') < 2
     or jsonb_array_length(p_report->'pathways') > 3
     or jsonb_typeof(p_report->'strengths') <> 'array'
     or jsonb_typeof(p_report->'promote') <> 'array'
     or coalesce(p_report->>'potentialSentence', '') = ''
     or jsonb_typeof(p_report->'plan') <> 'object'
     or jsonb_typeof(p_report->'plan'->'month') <> 'array'
     or jsonb_typeof(p_report->'plan'->'term') <> 'array'
     or jsonb_typeof(p_report->'schoolDoes') <> 'array'
     or jsonb_typeof(p_report->'homeDoes') <> 'array'
     or jsonb_typeof(p_report->'confidence') <> 'object'
     or coalesce(p_report->'confidence'->>'label', '') = '' then
    raise exception 'BAD_REPORT';
  end if;
  perform public.assess__require_student(u.id, u.role, v_student);
  v_report := p_report - 'status' - 'approvedBy' - 'approvedAt';
  v_report := jsonb_set(v_report, '{summary}', to_jsonb(v_summary), true);

  insert into public.assess_reports (student_id, status, summary, report, approved_by, approved_at, updated_at)
  values (v_student, 'pending', v_summary, v_report, null, null, now())
  on conflict (student_id) do update
  set status = 'pending',
      summary = excluded.summary,
      report = excluded.report,
      approved_by = null,
      approved_at = null,
      updated_at = now();

  delete from public.assess_pathways where student_id = v_student;
  insert into public.assess_pathways (student_id, ord, title, reason, path_type)
  select v_student,
         t.ord::integer,
         left(t.p->>'title', 400),
         left(coalesce(t.p->>'reason', ''), 800),
         left(coalesce(t.p->>'type', ''), 80)
  from jsonb_array_elements(v_report->'pathways') with ordinality as t(p, ord)
  where t.ord <= 3 and coalesce(t.p->>'title', '') <> '';

  return jsonb_build_object('ok', true, 'status', 'pending');
end
$fn$;
comment on function public.assess_save_report(text, text, jsonb) is 'assess_* only. Store a draft analysis. Always pending until assess_approve_report.';

create function public.assess_approve_report(p_token text, p_student text, p_summary text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, extensions
as $fn$
declare
  u public.assess_users;
  v_student text := btrim(coalesce(p_student, ''));
  v_summary text := btrim(coalesce(p_summary, ''));
begin
  u := public.assess__user(p_token);
  if u.role not in ('teacher', 'counselor') then
    raise exception 'FORBIDDEN';
  end if;
  if char_length(v_summary) < 1 or char_length(v_summary) > 4000 then
    raise exception 'BAD_SUMMARY';
  end if;
  perform public.assess__reject_banned(v_summary);
  perform public.assess__require_student(u.id, u.role, v_student);
  if not exists (select 1 from public.assess_reports r where r.student_id = v_student) then
    raise exception 'NO_REPORT';
  end if;
  update public.assess_reports
  set status = 'approved',
      summary = v_summary,
      report = jsonb_set(report, '{summary}', to_jsonb(v_summary), true),
      approved_by = u.id,
      approved_at = now(),
      updated_at = now()
  where student_id = v_student;
  return jsonb_build_object('ok', true, 'status', 'approved', 'approvedBy', u.display_name);
end
$fn$;
comment on function public.assess_approve_report(text, text, text) is 'assess_* only. Teacher or counselor edits the summary and approves it for the parent.';

revoke all on function public.assess__hash(text) from public, anon, authenticated;
revoke all on function public.assess__new_token() from public, anon, authenticated;
revoke all on function public.assess__user(text) from public, anon, authenticated;
revoke all on function public.assess__can_see(uuid, text, text) from public, anon, authenticated;
revoke all on function public.assess__require_student(uuid, text, text) from public, anon, authenticated;
revoke all on function public.assess__reject_banned(text) from public, anon, authenticated;
revoke all on function public.assess__answers(text, boolean) from public, anon, authenticated;
revoke all on function public.assess__form(text, text) from public, anon, authenticated;
revoke all on function public.assess__progress(text) from public, anon, authenticated;
revoke all on function public.assess__visible_report(text, text, jsonb, text, timestamptz) from public, anon, authenticated;

revoke all on function public.assess_login(text, text) from public;
revoke all on function public.assess_logout(text) from public;
revoke all on function public.assess_bootstrap(text) from public;
revoke all on function public.assess_save_module(text, text, text, jsonb, boolean, integer) from public;
revoke all on function public.assess_save_form(text, text, text, jsonb) from public;
revoke all on function public.assess_save_report(text, text, jsonb) from public;
revoke all on function public.assess_approve_report(text, text, text) from public;

grant execute on function public.assess_login(text, text) to anon, authenticated, service_role;
grant execute on function public.assess_logout(text) to anon, authenticated, service_role;
grant execute on function public.assess_bootstrap(text) to anon, authenticated, service_role;
grant execute on function public.assess_save_module(text, text, text, jsonb, boolean, integer) to anon, authenticated, service_role;
grant execute on function public.assess_save_form(text, text, text, jsonb) to anon, authenticated, service_role;
grant execute on function public.assess_save_report(text, text, jsonb) to anon, authenticated, service_role;
grant execute on function public.assess_approve_report(text, text, text) to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Seed: fictional sample only. Password hashes are bcrypt of the shared demo password.
-- ---------------------------------------------------------------------------

insert into public.assess_catalog (id, doc)
values (1, $assess_catalog_doc${"aptitudes":[{"id":"lang","name":"ภาษา"},{"id":"logic","name":"ตรรกะและคณิตศาสตร์"},{"id":"science","name":"วิทยาศาสตร์และการสืบเสาะ"},{"id":"spatial","name":"มิติสัมพันธ์และมิติภาพ"},{"id":"body","name":"ร่างกายและการเคลื่อนไหว"},{"id":"music","name":"ดนตรีและจังหวะ"},{"id":"art","name":"ศิลปะและการสร้างสรรค์"},{"id":"social","name":"มนุษยสัมพันธ์และการทำงานร่วมกัน"},{"id":"self","name":"การเข้าใจตนเองและการจัดการตนเอง"},{"id":"nature","name":"ธรรมชาติและสิ่งแวดล้อม"}],"workGroups":[{"id":"things","name":"ทำงานกับสิ่งของ/เครื่องมือ"},{"id":"data","name":"วิเคราะห์ข้อมูล"},{"id":"create","name":"สร้างสรรค์"},{"id":"help","name":"ช่วยเหลือผู้อื่น"},{"id":"lead","name":"นำทีม/ธุรกิจ"},{"id":"system","name":"ทำงานตามระบบ"}],"aptitudeBank":{"lang":[{"id":"lang_1","text":"ฟังเรื่องสั้นแล้วเล่าใจความสำคัญได้ด้วยคำของตนเอง","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"lang_2","text":"เขียนข้อความสั้นอธิบายสิ่งที่เห็นหรือความรู้สึกได้ชัดเจน","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"lang_3","text":"สนทนาตามสถานการณ์ เช่น ทักทาย อธิบาย หรือขอความช่วยเหลือ","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"lang_4","text":"เลือกคำที่เหมาะสมกับบริบท (สุภาพ / เป็นกันเอง)","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"lang_5","text":"อ่านข้อความสั้นแล้วตอบคำถามความเข้าใจได้","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]}],"logic":[{"id":"logic_1","text":"เรียงรูปหรือตัวเลขตามกฎที่กำหนดได้","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"logic_2","text":"แก้โจทย์สถานการณ์สั้นที่ต้องคิดเป็นขั้น","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"logic_3","text":"หาความสัมพันธ์ของชุดข้อมูลหรือรูปแบบที่ซ้ำ","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"logic_4","text":"ประมาณค่าและตรวจสอบความสมเหตุสมผลของคำตอบ","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"logic_5","text":"แยกแยะข้อมูลที่จำเป็นกับข้อมูลที่ไม่จำเป็นในโจทย์","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]}],"science":[{"id":"science_1","text":"ตั้งคำถามที่ทดลองหรือสังเกตได้จากสถานการณ์รอบตัว","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"science_2","text":"บันทึกการสังเกตอย่างเป็นระบบ (ก่อน–ระหว่าง–หลัง)","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"science_3","text":"อธิบายผลจากหลักฐาน ไม่เดาโดยไม่มีเหตุผล","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"science_4","text":"ออกแบบการทดลองง่าย ๆ เพื่อทดสอบสมมติฐาน","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"science_5","text":"แยกแยะข้อเท็จจริงกับความคิดเห็นในข้อความวิทยาศาสตร์","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]}],"spatial":[{"id":"spatial_1","text":"อ่านแผนผังง่าย ๆ แล้วบอกทิศทางได้","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"spatial_2","text":"จินตนาการว่ารูปทรงจะหน้าตาเป็นอย่างไรเมื่อหมุนหรือพับ","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"spatial_3","text":"ประกอบชิ้นงานตามภาพหรือคำแนะนำได้","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"spatial_4","text":"วาดมุมมองหรือแผนผังจากสิ่งที่เห็นจริง","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"spatial_5","text":"จัดวางของในพื้นที่ให้พอดีและใช้งานสะดวก","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]}],"body":[{"id":"body_1","text":"ควบคุมการเคลื่อนไหวตามจังหวะหรือคำสั่งได้","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"body_2","text":"ทำวงจรสถานีเคลื่อนไหวสั้น ๆ ได้ตามลำดับ","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"body_3","text":"ใช้ทักษะกีฬาง่าย ๆ เช่น โยน–รับ หรือทรงตัว","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"body_4","text":"แสดงออกด้วยท่าทางหรือนาฏกรรมสั้นได้","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"body_5","text":"ทำงานที่ต้องใช้มือละเอียด เช่น พับ ตัด ประกอบ","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]}],"music":[{"id":"music_1","text":"เคาะจังหวะตามทำนองหรือจังหวะที่ฟังได้","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"music_2","text":"แยกแยะเสียงสูง–ต่ำ หรือเร็ว–ช้าได้","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"music_3","text":"สร้างทำนองสั้น ๆ ด้วยเสียงหรือเครื่องง่าย ๆ","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"music_4","text":"จดจำและทำตามจังหวะที่ครูเคาะให้","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"music_5","text":"เลือกเพลงหรือจังหวะที่เหมาะกับอารมณ์ของเรื่อง","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]}],"art":[{"id":"art_1","text":"วาดหรือออกแบบตามโจทย์สั้น ๆ ได้ตามจินตนาการ","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"art_2","text":"ใช้สี รูปทรง หรือวัสดุเพื่อสื่อความหมาย","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"art_3","text":"ประดิษฐ์ชิ้นงานสั้นจากวัสดุที่กำหนด","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"art_4","text":"ปรับแก้ผลงานหลังได้รับคำแนะนำ","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"art_5","text":"อธิบายแนวคิดของผลงานตนเองได้สั้น ๆ","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]}],"social":[{"id":"social_1","text":"ทำงานกลุ่มโดยแบ่งหน้าที่และรับผิดชอบส่วนของตน","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"social_2","text":"ฟังความคิดเห็นเพื่อนแล้วตอบอย่างสุภาพ","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"social_3","text":"ช่วยแก้ปัญหาความขัดแย้งเล็กน้อยในกลุ่ม","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"social_4","text":"ชวนเพื่อนที่เงียบให้มีส่วนร่วม","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"social_5","text":"สะท้อนสิ่งที่กลุ่มทำได้ดีและสิ่งที่ควรปรับ","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]}],"self":[{"id":"self_1","text":"บอกจุดแข็งและจุดที่อยากพัฒนาของตนเองได้","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"self_2","text":"ตั้งเป้าหมายสั้น ๆ ที่ทำได้จริงในสัปดาห์นี้","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"self_3","text":"จัดการอารมณ์เมื่อผิดหวังหรือกดดันได้พอสมควร","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"self_4","text":"ติดตามความคืบหน้าของเป้าหมายที่ตั้งไว้","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"self_5","text":"ขอความช่วยเหลือเมื่อติดปัญหาแทนการยอมแพ้ทันที","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]}],"nature":[{"id":"nature_1","text":"สังเกตสิ่งมีชีวิตหรือสภาพแวดล้อมรอบโรงเรียนได้ละเอียด","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"nature_2","text":"จำแนกสิ่งมีชีวิตหรือสิ่งแวดล้อมตามลักษณะที่สังเกต","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"nature_3","text":"สนใจดูแลต้นไม้ สัตว์ หรือความสะอาดของพื้นที่","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"nature_4","text":"เสนอแนวทางลดขยะหรือดูแลสิ่งแวดล้อมสั้น ๆ","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"nature_5","text":"เชื่อมโยงสิ่งที่เห็นในธรรมชาติกับความรู้ที่ได้เรียน","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]}]},"workBank":{"things":[{"id":"things_1","text":"ชอบประกอบหรือซ่อมสิ่งของให้ใช้งานได้","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"things_2","text":"ทดลองใช้อุปกรณ์หรือเครื่องมืออย่างระมัดระวัง","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"things_3","text":"ทำโครงงานช่างหรือชิ้นงานที่จับต้องได้","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"things_4","text":"สนใจวิธีทำงานของเครื่องจักรหรืออุปกรณ์","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]}],"data":[{"id":"data_1","text":"อ่านกราฟหรือตารางแล้วสรุปใจความได้","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"data_2","text":"วางแผนเก็บข้อมูลเพื่อตอบคำถาม","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"data_3","text":"ตรวจความถูกต้องของตัวเลขหรือขั้นตอน","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"data_4","text":"สรุปหลักฐานก่อนตัดสินใจ","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]}],"create":[{"id":"create_1","text":"ออกแบบสื่อ เรื่อง หรือชิ้นงานใหม่จากโจทย์","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"create_2","text":"เขียนหรือผลิตเนื้อหาที่สื่อสารไอเดียได้","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"create_3","text":"ปรับไอเดียให้เหมาะกับผู้รับสาร","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"create_4","text":"สนุกกับการทดลองรูปแบบใหม่ ๆ","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]}],"help":[{"id":"help_1","text":"สอนหรืออธิบายให้เพื่อนเข้าใจได้","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"help_2","text":"สนใจงานจิตอาสาหรือช่วยเหลือผู้อื่น","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"help_3","text":"ฟังปัญหาของผู้อื่นแล้วให้คำแนะนำเบื้องต้น","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"help_4","text":"ใส่ใจความรู้สึกของคนรอบข้าง","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]}],"lead":[{"id":"lead_1","text":"วางแผนโครงการกลุ่มและแบ่งงานได้","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"lead_2","text":"นำกลุ่มให้ไปถึงเป้าหมายโดยไม่กดดันเกิน","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"lead_3","text":"สนใจจำลองร้านค้าหรือกิจกรรมธุรกิจสั้น","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"lead_4","text":"ตัดสินใจเมื่อกลุ่มเห็นไม่ตรงกัน","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]}],"system":[{"id":"system_1","text":"ทำตามขั้นตอนอย่างเป็นระบบและครบถ้วน","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"system_2","text":"ตรวจคุณภาพงานก่อนส่ง","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"system_3","text":"จัดระเบียนข้อมูลหรือเอกสารให้หาได้ง่าย","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]},{"id":"system_4","text":"ชอบงานที่ชัดเจนเรื่องกฎและมาตรฐาน","type":"choice","options":[{"v":1,"l":"ยังไม่ค่อยถนัด / ทำได้น้อย"},{"v":2,"l":"ทำได้บ้าง ต้องอาศัยคำแนะนำ"},{"v":3,"l":"ทำได้ดีเมื่อมีเวลาฝึก"},{"v":4,"l":"ทำได้ดีและชอบทำ"},{"v":5,"l":"ทำได้ดีมาก และช่วยเพื่อนได้"}]}]},"abilityByBand":{"early_primary":[{"id":"ab_early_primary_อ่านเขียนพื้นฐาน_1","subject":"อ่านเขียนพื้นฐาน","text":"[อ่านเขียนพื้นฐาน] อ่านคำ/ประโยคสั้นแล้วเลือกความหมายที่ถูก (ข้อ 1 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_early_primary_อ่านเขียนพื้นฐาน_2","subject":"อ่านเขียนพื้นฐาน","text":"[อ่านเขียนพื้นฐาน] อ่านคำ/ประโยคสั้นแล้วเลือกความหมายที่ถูก (ข้อ 2 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_early_primary_อ่านเขียนพื้นฐาน_3","subject":"อ่านเขียนพื้นฐาน","text":"[อ่านเขียนพื้นฐาน] อ่านคำ/ประโยคสั้นแล้วเลือกความหมายที่ถูก (ข้อ 3 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_early_primary_อ่านเขียนพื้นฐาน_4","subject":"อ่านเขียนพื้นฐาน","text":"[อ่านเขียนพื้นฐาน] อ่านคำ/ประโยคสั้นแล้วเลือกความหมายที่ถูก (ข้อ 4 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_early_primary_ความเข้าใจจำนวน_1","subject":"ความเข้าใจจำนวน","text":"[ความเข้าใจจำนวน] นับและเปรียบเทียบจำนวนในสถานการณ์สั้น (ข้อ 1 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_early_primary_ความเข้าใจจำนวน_2","subject":"ความเข้าใจจำนวน","text":"[ความเข้าใจจำนวน] นับและเปรียบเทียบจำนวนในสถานการณ์สั้น (ข้อ 2 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_early_primary_ความเข้าใจจำนวน_3","subject":"ความเข้าใจจำนวน","text":"[ความเข้าใจจำนวน] นับและเปรียบเทียบจำนวนในสถานการณ์สั้น (ข้อ 3 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_early_primary_ความเข้าใจจำนวน_4","subject":"ความเข้าใจจำนวน","text":"[ความเข้าใจจำนวน] นับและเปรียบเทียบจำนวนในสถานการณ์สั้น (ข้อ 4 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_early_primary_การอยู่ร่วมกัน_1","subject":"การอยู่ร่วมกัน","text":"[การอยู่ร่วมกัน] เลือกพฤติกรรมที่เหมาะสมเมื่อเล่นกับเพื่อน (ข้อ 1 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_early_primary_การอยู่ร่วมกัน_2","subject":"การอยู่ร่วมกัน","text":"[การอยู่ร่วมกัน] เลือกพฤติกรรมที่เหมาะสมเมื่อเล่นกับเพื่อน (ข้อ 2 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_early_primary_การอยู่ร่วมกัน_3","subject":"การอยู่ร่วมกัน","text":"[การอยู่ร่วมกัน] เลือกพฤติกรรมที่เหมาะสมเมื่อเล่นกับเพื่อน (ข้อ 3 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_early_primary_การอยู่ร่วมกัน_4","subject":"การอยู่ร่วมกัน","text":"[การอยู่ร่วมกัน] เลือกพฤติกรรมที่เหมาะสมเมื่อเล่นกับเพื่อน (ข้อ 4 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]}],"late_primary":[{"id":"ab_late_primary_คณิตศาสตร์_1","subject":"คณิตศาสตร์","text":"[คณิตศาสตร์] โจทย์สถานการณ์จำนวนและการดำเนินการ (ข้อ 1 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_late_primary_คณิตศาสตร์_2","subject":"คณิตศาสตร์","text":"[คณิตศาสตร์] โจทย์สถานการณ์จำนวนและการดำเนินการ (ข้อ 2 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_late_primary_คณิตศาสตร์_3","subject":"คณิตศาสตร์","text":"[คณิตศาสตร์] โจทย์สถานการณ์จำนวนและการดำเนินการ (ข้อ 3 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_late_primary_คณิตศาสตร์_4","subject":"คณิตศาสตร์","text":"[คณิตศาสตร์] โจทย์สถานการณ์จำนวนและการดำเนินการ (ข้อ 4 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_late_primary_ภาษาไทย_1","subject":"ภาษาไทย","text":"[ภาษาไทย] อ่านข้อความสั้นแล้วจับใจความ (ข้อ 1 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_late_primary_ภาษาไทย_2","subject":"ภาษาไทย","text":"[ภาษาไทย] อ่านข้อความสั้นแล้วจับใจความ (ข้อ 2 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_late_primary_ภาษาไทย_3","subject":"ภาษาไทย","text":"[ภาษาไทย] อ่านข้อความสั้นแล้วจับใจความ (ข้อ 3 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_late_primary_ภาษาไทย_4","subject":"ภาษาไทย","text":"[ภาษาไทย] อ่านข้อความสั้นแล้วจับใจความ (ข้อ 4 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_late_primary_วิทยาศาสตร์_1","subject":"วิทยาศาสตร์","text":"[วิทยาศาสตร์] สังเกตและอธิบายปรากฏการณ์ง่าย ๆ (ข้อ 1 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_late_primary_วิทยาศาสตร์_2","subject":"วิทยาศาสตร์","text":"[วิทยาศาสตร์] สังเกตและอธิบายปรากฏการณ์ง่าย ๆ (ข้อ 2 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_late_primary_วิทยาศาสตร์_3","subject":"วิทยาศาสตร์","text":"[วิทยาศาสตร์] สังเกตและอธิบายปรากฏการณ์ง่าย ๆ (ข้อ 3 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_late_primary_วิทยาศาสตร์_4","subject":"วิทยาศาสตร์","text":"[วิทยาศาสตร์] สังเกตและอธิบายปรากฏการณ์ง่าย ๆ (ข้อ 4 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_late_primary_สังคมศึกษา_1","subject":"สังคมศึกษา","text":"[สังคมศึกษา] เข้าใจกฎและบทบาทในชุมชน (ข้อ 1 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_late_primary_สังคมศึกษา_2","subject":"สังคมศึกษา","text":"[สังคมศึกษา] เข้าใจกฎและบทบาทในชุมชน (ข้อ 2 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_late_primary_สังคมศึกษา_3","subject":"สังคมศึกษา","text":"[สังคมศึกษา] เข้าใจกฎและบทบาทในชุมชน (ข้อ 3 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_late_primary_สังคมศึกษา_4","subject":"สังคมศึกษา","text":"[สังคมศึกษา] เข้าใจกฎและบทบาทในชุมชน (ข้อ 4 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_late_primary_ภาษาอังกฤษ_1","subject":"ภาษาอังกฤษ","text":"[ภาษาอังกฤษ] เข้าใจคำและประโยคพื้นฐาน (ข้อ 1 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_late_primary_ภาษาอังกฤษ_2","subject":"ภาษาอังกฤษ","text":"[ภาษาอังกฤษ] เข้าใจคำและประโยคพื้นฐาน (ข้อ 2 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_late_primary_ภาษาอังกฤษ_3","subject":"ภาษาอังกฤษ","text":"[ภาษาอังกฤษ] เข้าใจคำและประโยคพื้นฐาน (ข้อ 3 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_late_primary_ภาษาอังกฤษ_4","subject":"ภาษาอังกฤษ","text":"[ภาษาอังกฤษ] เข้าใจคำและประโยคพื้นฐาน (ข้อ 4 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]}],"lower_secondary":[{"id":"ab_lower_secondary_วิทยาศาสตร์_1","subject":"วิทยาศาสตร์","text":"[วิทยาศาสตร์] อธิบายปรากฏการณ์ด้วยหลักการสั้น ๆ (ข้อ 1 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_lower_secondary_วิทยาศาสตร์_2","subject":"วิทยาศาสตร์","text":"[วิทยาศาสตร์] อธิบายปรากฏการณ์ด้วยหลักการสั้น ๆ (ข้อ 2 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_lower_secondary_วิทยาศาสตร์_3","subject":"วิทยาศาสตร์","text":"[วิทยาศาสตร์] อธิบายปรากฏการณ์ด้วยหลักการสั้น ๆ (ข้อ 3 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_lower_secondary_วิทยาศาสตร์_4","subject":"วิทยาศาสตร์","text":"[วิทยาศาสตร์] อธิบายปรากฏการณ์ด้วยหลักการสั้น ๆ (ข้อ 4 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_lower_secondary_คณิตศาสตร์_1","subject":"คณิตศาสตร์","text":"[คณิตศาสตร์] แก้โจทย์หลายขั้นตอน (ข้อ 1 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_lower_secondary_คณิตศาสตร์_2","subject":"คณิตศาสตร์","text":"[คณิตศาสตร์] แก้โจทย์หลายขั้นตอน (ข้อ 2 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_lower_secondary_คณิตศาสตร์_3","subject":"คณิตศาสตร์","text":"[คณิตศาสตร์] แก้โจทย์หลายขั้นตอน (ข้อ 3 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_lower_secondary_คณิตศาสตร์_4","subject":"คณิตศาสตร์","text":"[คณิตศาสตร์] แก้โจทย์หลายขั้นตอน (ข้อ 4 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_lower_secondary_ภาษาไทย_1","subject":"ภาษาไทย","text":"[ภาษาไทย] วิเคราะห์ข้อความและสรุปประเด็น (ข้อ 1 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_lower_secondary_ภาษาไทย_2","subject":"ภาษาไทย","text":"[ภาษาไทย] วิเคราะห์ข้อความและสรุปประเด็น (ข้อ 2 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_lower_secondary_ภาษาไทย_3","subject":"ภาษาไทย","text":"[ภาษาไทย] วิเคราะห์ข้อความและสรุปประเด็น (ข้อ 3 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_lower_secondary_ภาษาไทย_4","subject":"ภาษาไทย","text":"[ภาษาไทย] วิเคราะห์ข้อความและสรุปประเด็น (ข้อ 4 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_lower_secondary_ภาษาอังกฤษ_1","subject":"ภาษาอังกฤษ","text":"[ภาษาอังกฤษ] อ่านและตอบคำถามจากข้อความสั้น (ข้อ 1 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_lower_secondary_ภาษาอังกฤษ_2","subject":"ภาษาอังกฤษ","text":"[ภาษาอังกฤษ] อ่านและตอบคำถามจากข้อความสั้น (ข้อ 2 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_lower_secondary_ภาษาอังกฤษ_3","subject":"ภาษาอังกฤษ","text":"[ภาษาอังกฤษ] อ่านและตอบคำถามจากข้อความสั้น (ข้อ 3 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_lower_secondary_ภาษาอังกฤษ_4","subject":"ภาษาอังกฤษ","text":"[ภาษาอังกฤษ] อ่านและตอบคำถามจากข้อความสั้น (ข้อ 4 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_lower_secondary_สังคมศึกษา_1","subject":"สังคมศึกษา","text":"[สังคมศึกษา] เชื่อมโยงเหตุการณ์กับแนวคิดสังคม (ข้อ 1 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_lower_secondary_สังคมศึกษา_2","subject":"สังคมศึกษา","text":"[สังคมศึกษา] เชื่อมโยงเหตุการณ์กับแนวคิดสังคม (ข้อ 2 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_lower_secondary_สังคมศึกษา_3","subject":"สังคมศึกษา","text":"[สังคมศึกษา] เชื่อมโยงเหตุการณ์กับแนวคิดสังคม (ข้อ 3 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_lower_secondary_สังคมศึกษา_4","subject":"สังคมศึกษา","text":"[สังคมศึกษา] เชื่อมโยงเหตุการณ์กับแนวคิดสังคม (ข้อ 4 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]}],"upper_secondary":[{"id":"ab_upper_secondary_คณิตศาสตร์_1","subject":"คณิตศาสตร์","text":"[คณิตศาสตร์] แก้โจทย์วิเคราะห์และประยุกต์ (ข้อ 1 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_upper_secondary_คณิตศาสตร์_2","subject":"คณิตศาสตร์","text":"[คณิตศาสตร์] แก้โจทย์วิเคราะห์และประยุกต์ (ข้อ 2 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_upper_secondary_คณิตศาสตร์_3","subject":"คณิตศาสตร์","text":"[คณิตศาสตร์] แก้โจทย์วิเคราะห์และประยุกต์ (ข้อ 3 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_upper_secondary_คณิตศาสตร์_4","subject":"คณิตศาสตร์","text":"[คณิตศาสตร์] แก้โจทย์วิเคราะห์และประยุกต์ (ข้อ 4 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_upper_secondary_ฟิสิกส์_1","subject":"ฟิสิกส์","text":"[ฟิสิกส์] ใช้แนวคิดแรง งาน พลังงานในสถานการณ์ (ข้อ 1 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_upper_secondary_ฟิสิกส์_2","subject":"ฟิสิกส์","text":"[ฟิสิกส์] ใช้แนวคิดแรง งาน พลังงานในสถานการณ์ (ข้อ 2 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_upper_secondary_ฟิสิกส์_3","subject":"ฟิสิกส์","text":"[ฟิสิกส์] ใช้แนวคิดแรง งาน พลังงานในสถานการณ์ (ข้อ 3 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_upper_secondary_ฟิสิกส์_4","subject":"ฟิสิกส์","text":"[ฟิสิกส์] ใช้แนวคิดแรง งาน พลังงานในสถานการณ์ (ข้อ 4 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_upper_secondary_เคมี_1","subject":"เคมี","text":"[เคมี] เชื่อมโยงปริมาณสารสัมพันธ์และสมบัติสาร (ข้อ 1 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_upper_secondary_เคมี_2","subject":"เคมี","text":"[เคมี] เชื่อมโยงปริมาณสารสัมพันธ์และสมบัติสาร (ข้อ 2 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_upper_secondary_เคมี_3","subject":"เคมี","text":"[เคมี] เชื่อมโยงปริมาณสารสัมพันธ์และสมบัติสาร (ข้อ 3 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_upper_secondary_เคมี_4","subject":"เคมี","text":"[เคมี] เชื่อมโยงปริมาณสารสัมพันธ์และสมบัติสาร (ข้อ 4 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_upper_secondary_ชีววิทยา_1","subject":"ชีววิทยา","text":"[ชีววิทยา] อธิบายระบบสิ่งมีชีวิตและกระบวนการ (ข้อ 1 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_upper_secondary_ชีววิทยา_2","subject":"ชีววิทยา","text":"[ชีววิทยา] อธิบายระบบสิ่งมีชีวิตและกระบวนการ (ข้อ 2 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_upper_secondary_ชีววิทยา_3","subject":"ชีววิทยา","text":"[ชีววิทยา] อธิบายระบบสิ่งมีชีวิตและกระบวนการ (ข้อ 3 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_upper_secondary_ชีววิทยา_4","subject":"ชีววิทยา","text":"[ชีววิทยา] อธิบายระบบสิ่งมีชีวิตและกระบวนการ (ข้อ 4 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_upper_secondary_ภาษาไทย_1","subject":"ภาษาไทย","text":"[ภาษาไทย] วิเคราะห์และเรียบเรียงข้อเขียนสั้น (ข้อ 1 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_upper_secondary_ภาษาไทย_2","subject":"ภาษาไทย","text":"[ภาษาไทย] วิเคราะห์และเรียบเรียงข้อเขียนสั้น (ข้อ 2 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_upper_secondary_ภาษาไทย_3","subject":"ภาษาไทย","text":"[ภาษาไทย] วิเคราะห์และเรียบเรียงข้อเขียนสั้น (ข้อ 3 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_upper_secondary_ภาษาไทย_4","subject":"ภาษาไทย","text":"[ภาษาไทย] วิเคราะห์และเรียบเรียงข้อเขียนสั้น (ข้อ 4 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_upper_secondary_ภาษาอังกฤษ_1","subject":"ภาษาอังกฤษ","text":"[ภาษาอังกฤษ] อ่านเชิงวิเคราะห์และสรุป (ข้อ 1 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_upper_secondary_ภาษาอังกฤษ_2","subject":"ภาษาอังกฤษ","text":"[ภาษาอังกฤษ] อ่านเชิงวิเคราะห์และสรุป (ข้อ 2 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_upper_secondary_ภาษาอังกฤษ_3","subject":"ภาษาอังกฤษ","text":"[ภาษาอังกฤษ] อ่านเชิงวิเคราะห์และสรุป (ข้อ 3 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_upper_secondary_ภาษาอังกฤษ_4","subject":"ภาษาอังกฤษ","text":"[ภาษาอังกฤษ] อ่านเชิงวิเคราะห์และสรุป (ข้อ 4 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_upper_secondary_สังคมศึกษา_1","subject":"สังคมศึกษา","text":"[สังคมศึกษา] วิเคราะห์ประเด็นสังคม/เศรษฐกิจสั้น (ข้อ 1 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_upper_secondary_สังคมศึกษา_2","subject":"สังคมศึกษา","text":"[สังคมศึกษา] วิเคราะห์ประเด็นสังคม/เศรษฐกิจสั้น (ข้อ 2 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_upper_secondary_สังคมศึกษา_3","subject":"สังคมศึกษา","text":"[สังคมศึกษา] วิเคราะห์ประเด็นสังคม/เศรษฐกิจสั้น (ข้อ 3 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]},{"id":"ab_upper_secondary_สังคมศึกษา_4","subject":"สังคมศึกษา","text":"[สังคมศึกษา] วิเคราะห์ประเด็นสังคม/เศรษฐกิจสั้น (ข้อ 4 — ข้อเสนอต้นแบบ)","type":"choice","options":[{"v":1,"l":"ยังทำไม่ได้"},{"v":2,"l":"ทำได้บางส่วน"},{"v":3,"l":"ทำได้ตามเกณฑ์ชั้น"},{"v":4,"l":"ทำได้ดีเกินเกณฑ์ชั้น"}]}]},"psych":{"motivation":[{"id":"mot_1","text":"ฉันตั้งใจเรียนแม้ไม่มีใครดู","type":"likert","options":[{"v":1,"l":"ไม่จริงเลย"},{"v":2,"l":"ค่อนข้างไม่จริง"},{"v":3,"l":"ปานกลาง"},{"v":4,"l":"ค่อนข้างจริง"},{"v":5,"l":"จริงมาก"}]},{"id":"mot_2","text":"ฉันอยากรู้มากกว่าที่ครูสอนในห้อง","type":"likert","options":[{"v":1,"l":"ไม่จริงเลย"},{"v":2,"l":"ค่อนข้างไม่จริง"},{"v":3,"l":"ปานกลาง"},{"v":4,"l":"ค่อนข้างจริง"},{"v":5,"l":"จริงมาก"}]},{"id":"mot_3","text":"เมื่อสอบได้คะแนนน้อย ฉันวางแผนแก้ให้ดีขึ้น","type":"likert","options":[{"v":1,"l":"ไม่จริงเลย"},{"v":2,"l":"ค่อนข้างไม่จริง"},{"v":3,"l":"ปานกลาง"},{"v":4,"l":"ค่อนข้างจริง"},{"v":5,"l":"จริงมาก"}]},{"id":"mot_4","text":"ฉันเลือกงานท้าทายมากกว่างานง่ายเสมอ","type":"likert","options":[{"v":1,"l":"ไม่จริงเลย"},{"v":2,"l":"ค่อนข้างไม่จริง"},{"v":3,"l":"ปานกลาง"},{"v":4,"l":"ค่อนข้างจริง"},{"v":5,"l":"จริงมาก"}]},{"id":"mot_5","text":"ฉันรู้สึกภูมิใจเมื่อพัฒนาขึ้นแม้ยังไม่เก่งที่สุด","type":"likert","options":[{"v":1,"l":"ไม่จริงเลย"},{"v":2,"l":"ค่อนข้างไม่จริง"},{"v":3,"l":"ปานกลาง"},{"v":4,"l":"ค่อนข้างจริง"},{"v":5,"l":"จริงมาก"}]},{"id":"mot_6","text":"ฉันจัดการเวลาทำการบ้านได้สม่ำเสมอ","type":"likert","options":[{"v":1,"l":"ไม่จริงเลย"},{"v":2,"l":"ค่อนข้างไม่จริง"},{"v":3,"l":"ปานกลาง"},{"v":4,"l":"ค่อนข้างจริง"},{"v":5,"l":"จริงมาก"}]},{"id":"mot_7","text":"ฉันถามเมื่อไม่เข้าใจแทนการปล่อยผ่าน","type":"likert","options":[{"v":1,"l":"ไม่จริงเลย"},{"v":2,"l":"ค่อนข้างไม่จริง"},{"v":3,"l":"ปานกลาง"},{"v":4,"l":"ค่อนข้างจริง"},{"v":5,"l":"จริงมาก"}]},{"id":"mot_8","text":"ฉันเชื่อมโยงสิ่งที่เรียนกับเป้าหมายของตนเอง","type":"likert","options":[{"v":1,"l":"ไม่จริงเลย"},{"v":2,"l":"ค่อนข้างไม่จริง"},{"v":3,"l":"ปานกลาง"},{"v":4,"l":"ค่อนข้างจริง"},{"v":5,"l":"จริงมาก"}]}],"learning_style":[{"id":"ls_1","text":"ฉันเข้าใจดีขึ้นเมื่อได้อ่านและจดด้วยตนเอง","type":"likert","options":[{"v":1,"l":"ไม่จริงเลย"},{"v":2,"l":"ค่อนข้างไม่จริง"},{"v":3,"l":"ปานกลาง"},{"v":4,"l":"ค่อนข้างจริง"},{"v":5,"l":"จริงมาก"}]},{"id":"ls_2","text":"ฉันเข้าใจดีขึ้นเมื่อได้อธิบายให้เพื่อนฟัง","type":"likert","options":[{"v":1,"l":"ไม่จริงเลย"},{"v":2,"l":"ค่อนข้างไม่จริง"},{"v":3,"l":"ปานกลาง"},{"v":4,"l":"ค่อนข้างจริง"},{"v":5,"l":"จริงมาก"}]},{"id":"ls_3","text":"ฉันเข้าใจดีขึ้นเมื่อได้ลงมือทำหรือทดลอง","type":"likert","options":[{"v":1,"l":"ไม่จริงเลย"},{"v":2,"l":"ค่อนข้างไม่จริง"},{"v":3,"l":"ปานกลาง"},{"v":4,"l":"ค่อนข้างจริง"},{"v":5,"l":"จริงมาก"}]},{"id":"ls_4","text":"ฉันชอบดูภาพ แผนผัง หรือวิดีโอประกอบ","type":"likert","options":[{"v":1,"l":"ไม่จริงเลย"},{"v":2,"l":"ค่อนข้างไม่จริง"},{"v":3,"l":"ปานกลาง"},{"v":4,"l":"ค่อนข้างจริง"},{"v":5,"l":"จริงมาก"}]},{"id":"ls_5","text":"ฉันชอบเรียนเป็นกลุ่มมากกว่าเรียนคนเดียว","type":"likert","options":[{"v":1,"l":"ไม่จริงเลย"},{"v":2,"l":"ค่อนข้างไม่จริง"},{"v":3,"l":"ปานกลาง"},{"v":4,"l":"ค่อนข้างจริง"},{"v":5,"l":"จริงมาก"}]},{"id":"ls_6","text":"ฉันต้องการความเงียบเพื่อสมาธิ","type":"likert","options":[{"v":1,"l":"ไม่จริงเลย"},{"v":2,"l":"ค่อนข้างไม่จริง"},{"v":3,"l":"ปานกลาง"},{"v":4,"l":"ค่อนข้างจริง"},{"v":5,"l":"จริงมาก"}]},{"id":"ls_7","text":"ฉันทบทวนด้วยการทำแบบฝึกหัดซ้ำ","type":"likert","options":[{"v":1,"l":"ไม่จริงเลย"},{"v":2,"l":"ค่อนข้างไม่จริง"},{"v":3,"l":"ปานกลาง"},{"v":4,"l":"ค่อนข้างจริง"},{"v":5,"l":"จริงมาก"}]},{"id":"ls_8","text":"ฉันจำได้ดีเมื่อเชื่อมกับเรื่องราวหรือตัวอย่างจริง","type":"likert","options":[{"v":1,"l":"ไม่จริงเลย"},{"v":2,"l":"ค่อนข้างไม่จริง"},{"v":3,"l":"ปานกลาง"},{"v":4,"l":"ค่อนข้างจริง"},{"v":5,"l":"จริงมาก"}]}],"personality":[{"id":"pe_1","text":"ฉันเป็นคนรับผิดชอบงานที่รับปากไว้","type":"likert","options":[{"v":1,"l":"ไม่จริงเลย"},{"v":2,"l":"ค่อนข้างไม่จริง"},{"v":3,"l":"ปานกลาง"},{"v":4,"l":"ค่อนข้างจริง"},{"v":5,"l":"จริงมาก"}]},{"id":"pe_2","text":"ฉันเปิดใจลองวิธีใหม่เมื่อวิธีเดิมไม่สำเร็จ","type":"likert","options":[{"v":1,"l":"ไม่จริงเลย"},{"v":2,"l":"ค่อนข้างไม่จริง"},{"v":3,"l":"ปานกลาง"},{"v":4,"l":"ค่อนข้างจริง"},{"v":5,"l":"จริงมาก"}]},{"id":"pe_3","text":"ฉันใจเย็นเมื่อเผชิญความกดดัน","type":"likert","options":[{"v":1,"l":"ไม่จริงเลย"},{"v":2,"l":"ค่อนข้างไม่จริง"},{"v":3,"l":"ปานกลาง"},{"v":4,"l":"ค่อนข้างจริง"},{"v":5,"l":"จริงมาก"}]},{"id":"pe_4","text":"ฉันให้ความร่วมมือกับเพื่อนแม้ความคิดต่าง","type":"likert","options":[{"v":1,"l":"ไม่จริงเลย"},{"v":2,"l":"ค่อนข้างไม่จริง"},{"v":3,"l":"ปานกลาง"},{"v":4,"l":"ค่อนข้างจริง"},{"v":5,"l":"จริงมาก"}]},{"id":"pe_5","text":"ฉันพูดความจริงอย่างสุภาพ","type":"likert","options":[{"v":1,"l":"ไม่จริงเลย"},{"v":2,"l":"ค่อนข้างไม่จริง"},{"v":3,"l":"ปานกลาง"},{"v":4,"l":"ค่อนข้างจริง"},{"v":5,"l":"จริงมาก"}]},{"id":"pe_6","text":"ฉันจัดระเบียบงานและของใช้ได้ดี","type":"likert","options":[{"v":1,"l":"ไม่จริงเลย"},{"v":2,"l":"ค่อนข้างไม่จริง"},{"v":3,"l":"ปานกลาง"},{"v":4,"l":"ค่อนข้างจริง"},{"v":5,"l":"จริงมาก"}]},{"id":"pe_7","text":"ฉันสนใจความรู้สึกของผู้อื่น","type":"likert","options":[{"v":1,"l":"ไม่จริงเลย"},{"v":2,"l":"ค่อนข้างไม่จริง"},{"v":3,"l":"ปานกลาง"},{"v":4,"l":"ค่อนข้างจริง"},{"v":5,"l":"จริงมาก"}]},{"id":"pe_8","text":"ฉันยืนหยัดทำสิ่งที่ถูกต้องแม้ยาก","type":"likert","options":[{"v":1,"l":"ไม่จริงเลย"},{"v":2,"l":"ค่อนข้างไม่จริง"},{"v":3,"l":"ปานกลาง"},{"v":4,"l":"ค่อนข้างจริง"},{"v":5,"l":"จริงมาก"}]}]},"personalityActs":[{"id":"pa1","title":"ตั้งเป้าหมายสัปดาห์นี้","prompt":"เขียนเป้าหมาย 1 ข้อที่ทำได้จริงภายใน 7 วัน และวิธีวัดความสำเร็จ","type":"text"},{"id":"pa2","title":"สะท้อนตนเอง","prompt":"วันนี้ฉันทำได้ดีเรื่องใด และอยากปรับเรื่องใด","type":"text"},{"id":"pa3","title":"สถานการณ์อยู่ร่วมกับผู้อื่น","prompt":"เพื่อนในกลุ่มไม่ช่วยงาน คุณจะพูดและทำอย่างไร","type":"choice","options":[{"v":1,"l":"ทำงานคนเดียวเงียบ ๆ"},{"v":2,"l":"บ่นกับเพื่อนคนอื่น"},{"v":3,"l":"คุยตรง ๆ อย่างสุภาพและแบ่งงานใหม่"},{"v":4,"l":"บอกครูทันทีโดยไม่คุยกับเพื่อน"}]},{"id":"pa4","title":"จัดการอารมณ์เมื่อผิดหวัง","prompt":"เมื่อได้คะแนนต่ำกว่าที่คาด คุณจะทำอะไรเป็นลำดับแรก","type":"choice","options":[{"v":1,"l":"เลิกสนใจวิชานั้น"},{"v":2,"l":"โทษผู้อื่น"},{"v":3,"l":"พักสั้น ๆ แล้ววางแผนทบทวน"},{"v":4,"l":"เปรียบเทียบกับเพื่อนทันที"}]},{"id":"pa5","title":"ขอความช่วยเหลืออย่างสร้างสรรค์","prompt":"เขียนประโยคที่คุณจะใช้ขอความช่วยเหลือจากครูหรือเพื่อน","type":"text"},{"id":"pa6","title":"ขอบคุณและให้กำลังใจ","prompt":"เขียนข้อความสั้นให้กำลังใจเพื่อน 1 คน (ไม่ระบุชื่อจริง)","type":"text"}],"exercises":{"early_primary":[{"id":"ex_ep1","title":"ฝึกนับและเปรียบเทียบ","domain":"logic","prompt":"มีแอปเปิล 7 ผล กินไป 3 ผล เหลือกี่ผล","answer":"4","hint":"7 ลบ 3"},{"id":"ex_ep2","title":"ฟังแล้วเลือกใจความ","domain":"lang","prompt":"เรื่องสั้น: แมวตัวเล็กหาที่ซ่อนฝน มันวิ่งเข้าใต้โต๊ะ — แมวทำอะไร","answer":"หาที่หลบฝน / เข้าใต้โต๊ะ","hint":"อ่านประโยคสุดท้าย"}],"late_primary":[{"id":"ex_lp1","title":"โจทย์เศษส่วนสั้น","domain":"logic","prompt":"มีเค้ก 1 ก้อน แบ่งเท่า ๆ กัน 4 ชิ้น กินไป 1 ชิ้น เหลือกี่ส่วนของเค้ก","answer":"3/4","hint":"เหลือ 3 จาก 4"},{"id":"ex_lp2","title":"จับใจความ","domain":"lang","prompt":"พืชต้องการแสงเพื่อสร้างอาหาร ข้อใดสรุปได้","answer":"แสงสำคัญต่อการสร้างอาหารของพืช","hint":"ดูคำว่าเพื่อ"}],"lower_secondary":[{"id":"ex_ls1","title":"สมการเชิงเส้นสั้น","domain":"logic","prompt":"หาค่า x จาก 2x+3=11","answer":"4","hint":"ย้าย 3 ไปลบ"},{"id":"ex_ls2","title":"การทดลองสั้น","domain":"science","prompt":"ถ้าต้องการทดสอบว่าแสงมีผลต่อการงอกของพืช ควรควบคุมตัวแปรใดให้คงที่","answer":"น้ำ ดิน อุณหภูมิ ชนิดเมล็ด ฯลฯ (ยกเว้นแสง)","hint":"เปลี่ยนเฉพาะแสง"}],"upper_secondary":[{"id":"ex_us1","title":"ปริมาณสารสัมพันธ์สั้น","domain":"science","prompt":"ถ้า 1 โมลแก๊สที่ STP มีปริมาตรประมาณเท่าใด (ลิตร) — ข้อเสนอทบทวน","answer":"22.4","hint":"ค่ามาตรฐาน STP"},{"id":"ex_us2","title":"อ่านกราฟความเร็ว","domain":"logic","prompt":"วัตถุเคลื่อนที่ความเร็วคงที่ กราฟความเร็ว-เวลาเป็นเส้นแบบใด","answer":"เส้นตรงขนานแกนเวลา / ความชันเป็นศูนย์","hint":"ความเร็วไม่เปลี่ยน"}]},"parentHome":[{"id":"ph1","text":"บุตรหลานสนใจอ่านหรือฟังเรื่องราวที่บ้าน","type":"likert","options":[{"v":1,"l":"ไม่เคย"},{"v":2,"l":"นาน ๆ ครั้ง"},{"v":3,"l":"บางครั้ง"},{"v":4,"l":"บ่อย"},{"v":5,"l":"เกือบทุกวัน"}]},{"id":"ph2","text":"บุตรหลานช่วยงานบ้านหรือดูแลของใช้ส่วนตัวได้","type":"likert","options":[{"v":1,"l":"ไม่เคย"},{"v":2,"l":"นาน ๆ ครั้ง"},{"v":3,"l":"บางครั้ง"},{"v":4,"l":"บ่อย"},{"v":5,"l":"เกือบทุกวัน"}]},{"id":"ph3","text":"บุตรหลานเล่นกับพี่น้อง/เพื่อนอย่างเหมาะสม","type":"likert","options":[{"v":1,"l":"ไม่เคย"},{"v":2,"l":"นาน ๆ ครั้ง"},{"v":3,"l":"บางครั้ง"},{"v":4,"l":"บ่อย"},{"v":5,"l":"เกือบทุกวัน"}]},{"id":"ph4","text":"บุตรหลานบอกความรู้สึกเมื่อโกรธหรือเสียใจได้","type":"likert","options":[{"v":1,"l":"ไม่เคย"},{"v":2,"l":"นาน ๆ ครั้ง"},{"v":3,"l":"บางครั้ง"},{"v":4,"l":"บ่อย"},{"v":5,"l":"เกือบทุกวัน"}]},{"id":"ph5","text":"บุตรหลานสนใจธรรมชาติ สัตว์ หรือต้นไม้","type":"likert","options":[{"v":1,"l":"ไม่เคย"},{"v":2,"l":"นาน ๆ ครั้ง"},{"v":3,"l":"บางครั้ง"},{"v":4,"l":"บ่อย"},{"v":5,"l":"เกือบทุกวัน"}]},{"id":"ph6","text":"บุตรหลานตั้งใจทำการบ้านโดยไม่ต้องเตือนบ่อย","type":"likert","options":[{"v":1,"l":"ไม่เคย"},{"v":2,"l":"นาน ๆ ครั้ง"},{"v":3,"l":"บางครั้ง"},{"v":4,"l":"บ่อย"},{"v":5,"l":"เกือบทุกวัน"}]}],"teacherRubric":[{"id":"tr1","text":"มีส่วนร่วมในชั้นเรียน","type":"rubric","options":[{"v":1,"l":"น้อย"},{"v":2,"l":"ปานกลาง"},{"v":3,"l":"ดี"},{"v":4,"l":"ดีมาก"}]},{"id":"tr2","text":"ส่งงานตรงเวลาและครบ","type":"rubric","options":[{"v":1,"l":"น้อย"},{"v":2,"l":"ปานกลาง"},{"v":3,"l":"ดี"},{"v":4,"l":"ดีมาก"}]},{"id":"tr3","text":"ทำงานร่วมกับเพื่อน","type":"rubric","options":[{"v":1,"l":"น้อย"},{"v":2,"l":"ปานกลาง"},{"v":3,"l":"ดี"},{"v":4,"l":"ดีมาก"}]},{"id":"tr4","text":"พัฒนาขึ้นเมื่อได้รับความช่วยเหลือ","type":"rubric","options":[{"v":1,"l":"น้อย"},{"v":2,"l":"ปานกลาง"},{"v":3,"l":"ดี"},{"v":4,"l":"ดีมาก"}]},{"id":"tr5","text":"บันทึกสังเกตสั้น ๆ","type":"text"}],"weights":{"aptitude":{"activity":0.4,"observeParent":0.35,"portfolio":0.25,"label":"ข้อเสนอ: กิจกรรม 40% / สังเกต+ผู้ปกครอง 35% / แฟ้มผลงาน 25%"},"ability":{"test":0.6,"portfolio":0.4,"label":"ข้อเสนอ: แบบทดสอบ 60% / แฟ้ม+งานชิ้น 40%"},"potential":{"growth":0.35,"gap":0.3,"motivation":0.2,"response":0.15,"label":"ข้อเสนอ: อัตราพัฒนา 35% / ช่องว่าง 30% / แรงจูงใจ 20% / การตอบสนอง 15%"}},"tracks":{"lower_secondary":["วิทย์-คณิต","ศิลป์-คำนวณ","ศิลป์-ภาษา"],"note":"ชื่อสายเป็นข้อเสนอ รอยืนยันชื่อสายจริงของโรงเรียน"},"bandLabels":{"early_primary":"ประถมต้น (ป.1–ป.3)","late_primary":"ประถมปลาย (ป.4–ป.6)","lower_secondary":"มัธยมต้น (ม.1–ม.3)","upper_secondary":"มัธยมปลาย (ม.4–ม.6)"}}$assess_catalog_doc$::jsonb);

insert into public.assess_items (item_id, kind, domain, band, sort_no, body)
select item->>'id', 'aptitude', dom.key, null, t.ord::integer, item
from public.assess_catalog c
cross join lateral jsonb_each(c.doc->'aptitudeBank') as dom(key, value)
cross join lateral jsonb_array_elements(dom.value) with ordinality as t(item, ord)
where c.id = 1;

insert into public.assess_items (item_id, kind, domain, band, sort_no, body)
select item->>'id', 'work', dom.key, 'upper_secondary', t.ord::integer, item
from public.assess_catalog c
cross join lateral jsonb_each(c.doc->'workBank') as dom(key, value)
cross join lateral jsonb_array_elements(dom.value) with ordinality as t(item, ord)
where c.id = 1;

insert into public.assess_items (item_id, kind, domain, band, sort_no, body)
select item->>'id', 'ability', item->>'subject', band.key, t.ord::integer, item
from public.assess_catalog c
cross join lateral jsonb_each(c.doc->'abilityByBand') as band(key, value)
cross join lateral jsonb_array_elements(band.value) with ordinality as t(item, ord)
where c.id = 1;

insert into public.assess_items (item_id, kind, domain, band, sort_no, body)
select item->>'id', 'psych', sec.key, null, t.ord::integer, item
from public.assess_catalog c
cross join lateral jsonb_each(c.doc->'psych') as sec(key, value)
cross join lateral jsonb_array_elements(sec.value) with ordinality as t(item, ord)
where c.id = 1;

insert into public.assess_items (item_id, kind, domain, band, sort_no, body)
select item->>'id', 'exercises', item->>'domain', band.key, t.ord::integer, item
from public.assess_catalog c
cross join lateral jsonb_each(c.doc->'exercises') as band(key, value)
cross join lateral jsonb_array_elements(band.value) with ordinality as t(item, ord)
where c.id = 1;

insert into public.assess_items (item_id, kind, domain, band, sort_no, body)
select item->>'id', 'personality', null, null, t.ord::integer, item
from public.assess_catalog c
cross join lateral jsonb_array_elements(c.doc->'personalityActs') with ordinality as t(item, ord)
where c.id = 1;

insert into public.assess_items (item_id, kind, domain, band, sort_no, body)
select item->>'id', 'parent', null, null, t.ord::integer, item
from public.assess_catalog c
cross join lateral jsonb_array_elements(c.doc->'parentHome') with ordinality as t(item, ord)
where c.id = 1;

insert into public.assess_items (item_id, kind, domain, band, sort_no, body)
select item->>'id', 'rubric', null, null, t.ord::integer, item
from public.assess_catalog c
cross join lateral jsonb_array_elements(c.doc->'teacherRubric') with ordinality as t(item, ord)
where c.id = 1;

insert into public.assess_users (username, password_hash, role, display_name) values
  ('admin', '$2a$06$ZGf8B2K1PELK4CjPM8Xt3eQdgNcCtByoc/KIplRMexcJhPNapjl02', 'admin', 'ผู้บริหารตัวอย่าง'),
  ('teacher', '$2a$06$tcLf0cllXfoUFxjWgXr4duP/xxo5GILCdNp1LEx7janqzVxh5XeLa', 'teacher', 'ครูที่ปรึกษาตัวอย่าง'),
  ('counselor', '$2a$06$cnJ./XWr4DCNE6fOkGdNGu1PJEgTo69rMO3peOqLaKKYIjyE1mabm', 'counselor', 'ครูแนะแนวตัวอย่าง'),
  ('parent-a', '$2a$06$xBNIS81.lNqdAXxTBMUCGufmaaX1yxzOKJ6PsaRrakMG0tVdvs2Lu', 'parent', 'ผู้ปกครองของด.ช.ตัวอย่าง ก.'),
  ('parent-b', '$2a$06$Hpe1W8chlLOPZnVwO5tskuaTnfK5Y7w8dByz7NyK1ThQdEms5Bzla', 'parent', 'ผู้ปกครองของด.ญ.ตัวอย่าง ข.'),
  ('parent-c', '$2a$06$MxRF5RxpkIo2JkDMMPm1meZ8L7rxlHkfPLAHC.sF.ECd2pX0DJI9q', 'parent', 'ผู้ปกครองของด.ช.ตัวอย่าง ค.'),
  ('parent-d', '$2a$06$IeAdDkAJ1IL2SfrJ9fXwxu3wV7CCBDz9rATrcuDvfWIhF2J8Fdhw6', 'parent', 'ผู้ปกครองของด.ญ.ตัวอย่าง ง.'),
  ('parent-e', '$2a$06$.iP/g5UdwFeh0lSTH0D5HOYTW4RNAvHCd7cb3jVEUJxG10JBmNM2S', 'parent', 'ผู้ปกครองของด.ช.ตัวอย่าง จ.'),
  ('parent-f', '$2a$06$gPsAzoq5l6ScsVeQh826FOHibb8QwkAoXvQ1AmGcNH1UIfsx/hKbO', 'parent', 'ผู้ปกครองของด.ญ.ตัวอย่าง ฉ.'),
  ('parent-g', '$2a$06$RsPfm55EYGpsVTyYAlifbOe9Ybfqu6tJ7kTl0nx1JOBVFLoZIedpO', 'parent', 'ผู้ปกครองของนายตัวอย่าง ช.'),
  ('parent-h', '$2a$06$ewHxeeli0oczG2F2pJ.o1OAvXES76Bj/OCQJ7imvJn8mQMxu6u7B6', 'parent', 'ผู้ปกครองของนางสาวตัวอย่าง ซ.'),
  ('student-a', '$2a$06$JQiP8CE4CqGJbeYMciE6nOKpIylxjoBw1V1oLHbYcncTkg6d0fK/C', 'student', 'ด.ช.ตัวอย่าง ก.'),
  ('student-b', '$2a$06$/0bn03k7JOd2PyGOqRLhfOfNhIl.ijHMplozwX/LsfJc470/Bj.bS', 'student', 'ด.ญ.ตัวอย่าง ข.'),
  ('student-c', '$2a$06$MCspA6l/Ef1u3ygOt4cPteGSV3my74OsLmQqASLHvILcF64b3q.VG', 'student', 'ด.ช.ตัวอย่าง ค.'),
  ('student-d', '$2a$06$ox553/vy5AViGdKzYViT0eF8kzi67bGlSosYL7vHuK/xJbKLWFPbq', 'student', 'ด.ญ.ตัวอย่าง ง.'),
  ('student-e', '$2a$06$LGmbFrw9019B4MTOG0eeRe.2G2RP7HZpByo3vPmoZVgzhPesHwiKu', 'student', 'ด.ช.ตัวอย่าง จ.'),
  ('student-f', '$2a$06$.HvgmibaxX2FXFWJrqfHCe13LdiHueVVLSsjWONoxiuXdLXZzI/12', 'student', 'ด.ญ.ตัวอย่าง ฉ.'),
  ('student-g', '$2a$06$/GJxrXkP2KTlFzZ8YNhC1.Zwzn.lLcwLorfQkIrSdcZSKrypnmWE2', 'student', 'นายตัวอย่าง ช.'),
  ('student-h', '$2a$06$2bApeRiRzx9crWo2nTfqt.CJagD4SIlQkLkRk5Pal.J6W2OkFohwG', 'student', 'นางสาวตัวอย่าง ซ.');

insert into public.assess_students (
  id, sort_no, code, name, display_name, grade, band, gender, status, teacher_note, seed, fictional
)
select s->>'id', t.ord::integer, s->>'code', s->>'name', s->>'display', s->>'grade', s->>'band',
       s->>'gender', s->>'status', s->>'teacherNote', coalesce(s->'seed', '{}'::jsonb), true
from jsonb_array_elements($assess_students_doc$[{"id":"stu-a","code":"PMW-M3-001","name":"ด.ช.ตัวอย่าง ก.","display":"เด็กชาย ก. (ด.ช.ตัวอย่าง ก.)","grade":"ม.3","band":"lower_secondary","gender":"ชาย","status":"approved","parentId":"parent-a","teacherNote":"สนใจวิทย์และทำงานกลุ่มได้ดี","seed":{"apt":{"lang":4,"logic":5,"science":5,"spatial":3,"body":3,"music":2,"art":3,"social":4,"self":4,"nature":3},"ability":{"วิทยาศาสตร์":3,"คณิตศาสตร์":4,"ภาษาไทย":3,"ภาษาอังกฤษ":3,"สังคมศึกษา":3},"growth":0.72,"motivation":4.2,"response":4,"portfolio":3.5,"observe":4}},{"id":"stu-b","code":"PMW-M2-002","name":"ด.ญ.ตัวอย่าง ข.","display":"ด.ญ.ตัวอย่าง ข.","grade":"ม.2","band":"lower_secondary","gender":"หญิง","status":"pending","parentId":"parent-b","teacherNote":"ถนัดภาษาและศิลปะ","seed":{"apt":{"lang":5,"logic":3,"science":3,"spatial":4,"body":3,"music":4,"art":5,"social":4,"self":3,"nature":3},"ability":{"วิทยาศาสตร์":3,"คณิตศาสตร์":2,"ภาษาไทย":4,"ภาษาอังกฤษ":4,"สังคมศึกษา":3},"growth":0.55,"motivation":3.6,"response":3.5,"portfolio":4.2,"observe":3.8}},{"id":"stu-c","code":"PMW-P2-003","name":"ด.ช.ตัวอย่าง ค.","display":"ด.ช.ตัวอย่าง ค.","grade":"ป.2","band":"early_primary","gender":"ชาย","status":"pending","parentId":"parent-c","teacherNote":"ชอบเคลื่อนไหวและดนตรี","seed":{"apt":{"lang":3,"logic":3,"science":3,"spatial":3,"body":5,"music":4,"art":3,"social":3,"self":2,"nature":4},"ability":{"อ่านเขียนพื้นฐาน":2,"ความเข้าใจจำนวน":3,"การอยู่ร่วมกัน":3},"growth":0.6,"motivation":3.5,"response":3.8,"portfolio":3,"observe":3.5}},{"id":"stu-d","code":"PMW-P3-004","name":"ด.ญ.ตัวอย่าง ง.","display":"ด.ญ.ตัวอย่าง ง.","grade":"ป.3","band":"early_primary","gender":"หญิง","status":"started","parentId":"parent-d","teacherNote":"เพิ่งเริ่มทำแบบวัด","seed":{"apt":{"lang":3,"logic":2,"science":2,"spatial":3,"body":3,"music":3,"art":4,"social":4,"self":3,"nature":3},"ability":{"อ่านเขียนพื้นฐาน":3,"ความเข้าใจจำนวน":2,"การอยู่ร่วมกัน":4},"growth":0.4,"motivation":3,"response":3.2,"portfolio":2.5,"observe":3}},{"id":"stu-e","code":"PMW-P5-005","name":"ด.ช.ตัวอย่าง จ.","display":"ด.ช.ตัวอย่าง จ.","grade":"ป.5","band":"late_primary","gender":"ชาย","status":"incomplete","parentId":"parent-e","teacherNote":"ทำค้างบางโมดูล","seed":{"apt":{"lang":3,"logic":4,"science":4,"spatial":4,"body":3,"music":2,"art":2,"social":3,"self":3,"nature":4},"ability":{"คณิตศาสตร์":3,"ภาษาไทย":3,"วิทยาศาสตร์":4,"สังคมศึกษา":3,"ภาษาอังกฤษ":2},"growth":0.5,"motivation":3.4,"response":3.3,"portfolio":3.2,"observe":3.4}},{"id":"stu-f","code":"PMW-P6-006","name":"ด.ญ.ตัวอย่าง ฉ.","display":"ด.ญ.ตัวอย่าง ฉ.","grade":"ป.6","band":"late_primary","gender":"หญิง","status":"approved","parentId":"parent-f","teacherNote":"สำรวจความสนใจได้ดี","seed":{"apt":{"lang":4,"logic":3,"science":3,"spatial":3,"body":3,"music":4,"art":4,"social":5,"self":4,"nature":3},"ability":{"คณิตศาสตร์":3,"ภาษาไทย":4,"วิทยาศาสตร์":3,"สังคมศึกษา":4,"ภาษาอังกฤษ":3},"growth":0.65,"motivation":4,"response":4.1,"portfolio":4,"observe":4.2}},{"id":"stu-g","code":"PMW-M5-007","name":"นายตัวอย่าง ช.","display":"นายตัวอย่าง ช.","grade":"ม.5","band":"upper_secondary","gender":"ชาย","status":"approved","parentId":"parent-g","teacherNote":"สนใจวิเคราะห์ข้อมูลและวิทย์","seed":{"apt":{"lang":3,"logic":5,"science":5,"spatial":4,"body":2,"music":2,"art":2,"social":3,"self":4,"nature":3},"work":{"things":3,"data":5,"create":2,"help":3,"lead":3,"system":4},"ability":{"คณิตศาสตร์":4,"ฟิสิกส์":4,"เคมี":4,"ชีววิทยา":3,"ภาษาไทย":3,"ภาษาอังกฤษ":3,"สังคมศึกษา":3},"growth":0.7,"motivation":4.3,"response":3.9,"portfolio":3.8,"observe":4}},{"id":"stu-h","code":"PMW-M4-008","name":"นางสาวตัวอย่าง ซ.","display":"นางสาวตัวอย่าง ซ.","grade":"ม.4","band":"upper_secondary","gender":"หญิง","status":"incomplete","parentId":"parent-h","teacherNote":"สนใจช่วยเหลือผู้อื่นและภาษา","seed":{"apt":{"lang":5,"logic":3,"science":3,"spatial":3,"body":3,"music":3,"art":4,"social":5,"self":4,"nature":3},"work":{"things":2,"data":3,"create":4,"help":5,"lead":4,"system":3},"ability":{"คณิตศาสตร์":3,"ฟิสิกส์":2,"เคมี":2,"ชีววิทยา":3,"ภาษาไทย":4,"ภาษาอังกฤษ":4,"สังคมศึกษา":4},"growth":0.58,"motivation":3.9,"response":4.2,"portfolio":4.1,"observe":3.9}}]$assess_students_doc$::jsonb)
  with ordinality as t(s, ord);

insert into public.assess_user_students (user_id, student_id)
select u.id, x.sid
from jsonb_each($assess_links_doc${"admin":[],"teacher":["stu-a","stu-b","stu-c","stu-d","stu-e","stu-f","stu-g","stu-h"],"counselor":["stu-a","stu-b","stu-c","stu-d","stu-e","stu-f","stu-g","stu-h"],"parent-a":["stu-a"],"parent-b":["stu-b"],"parent-c":["stu-c"],"parent-d":["stu-d"],"parent-e":["stu-e"],"parent-f":["stu-f"],"parent-g":["stu-g"],"parent-h":["stu-h"],"student-a":["stu-a"],"student-b":["stu-b"],"student-c":["stu-c"],"student-d":["stu-d"],"student-e":["stu-e"],"student-f":["stu-f"],"student-g":["stu-g"],"student-h":["stu-h"]}$assess_links_doc$::jsonb) e
cross join lateral jsonb_array_elements_text(e.value) as x(sid)
join public.assess_users u on u.username = e.key;

insert into public.assess_progress (student_id, module, done, pct)
select stu.key, mod.key, (mod.value->>'done')::boolean, (mod.value->>'pct')::integer
from jsonb_each($assess_progress_doc${"stu-a":{"aptitude":{"done":true,"pct":100},"ability":{"done":true,"pct":100},"psych":{"done":true,"pct":100},"work":{"done":false,"pct":0},"exercises":{"done":false,"pct":0},"personality":{"done":false,"pct":0}},"stu-b":{"aptitude":{"done":true,"pct":100},"ability":{"done":true,"pct":100},"psych":{"done":true,"pct":100},"work":{"done":false,"pct":0},"exercises":{"done":false,"pct":0},"personality":{"done":false,"pct":0}},"stu-c":{"aptitude":{"done":true,"pct":100},"ability":{"done":true,"pct":100},"psych":{"done":true,"pct":100},"work":{"done":false,"pct":0},"exercises":{"done":false,"pct":0},"personality":{"done":false,"pct":0}},"stu-d":{"aptitude":{"done":false,"pct":10},"ability":{"done":false,"pct":0},"psych":{"done":false,"pct":0},"work":{"done":false,"pct":0},"exercises":{"done":false,"pct":0},"personality":{"done":false,"pct":0}},"stu-e":{"aptitude":{"done":false,"pct":45},"ability":{"done":false,"pct":20},"psych":{"done":false,"pct":0},"work":{"done":false,"pct":0},"exercises":{"done":false,"pct":0},"personality":{"done":false,"pct":0}},"stu-f":{"aptitude":{"done":true,"pct":100},"ability":{"done":true,"pct":100},"psych":{"done":true,"pct":100},"work":{"done":false,"pct":0},"exercises":{"done":false,"pct":0},"personality":{"done":false,"pct":0}},"stu-g":{"aptitude":{"done":true,"pct":100},"ability":{"done":true,"pct":100},"psych":{"done":true,"pct":100},"work":{"done":true,"pct":100},"exercises":{"done":false,"pct":0},"personality":{"done":false,"pct":0}},"stu-h":{"aptitude":{"done":false,"pct":45},"ability":{"done":false,"pct":20},"psych":{"done":false,"pct":0},"work":{"done":false,"pct":0},"exercises":{"done":false,"pct":0},"personality":{"done":false,"pct":0}}}$assess_progress_doc$::jsonb) stu
cross join lateral jsonb_each(stu.value) mod;

insert into public.assess_reports (student_id, status, summary, report, approved_by, approved_at)
select rep.key,
       rep.value->>'status',
       rep.value->>'summary',
       (rep.value - 'status'),
       case when rep.value->>'status' = 'approved'
         then (select id from public.assess_users where username = 'teacher')
         else null end,
       case when rep.value->>'status' = 'approved'
         then timestamptz '2026-11-05 10:00:00+07'
         else null end
from jsonb_each($assess_reports_doc${"stu-a":{"studentId":"stu-a","generatedAt":"2026-11-05T03:00:00.000Z","summary":"เด็กชาย ก. (ด.ช.ตัวอย่าง ก.) มีจุดเด่นด้านตรรกะและคณิตศาสตร์, วิทยาศาสตร์และการสืบเสาะ, ภาษา ความสามารถปัจจุบันอยู่ในระดับที่ส่งเสริมต่อได้ และช่วงกลาง–สูง ที่ส่งเสริมตรงจุดแล้วจะเห็นการเติบโตชัด","strengths":["ตรรกะและคณิตศาสตร์ — เห็นแนวโน้มจากกิจกรรมและการสังเกต (ข้อมูลจำลอง)","วิทยาศาสตร์และการสืบเสาะ — เห็นแนวโน้มจากกิจกรรมและการสังเกต (ข้อมูลจำลอง)","ภาษา — เห็นแนวโน้มจากกิจกรรมและการสังเกต (ข้อมูลจำลอง)"],"promote":["ดนตรีและจังหวะ — ส่งเสริมเพิ่มด้วยกิจกรรมสั้นและแบบฝึก (ไม่ใช่ป้ายว่าไม่ถนัด)","มิติสัมพันธ์และมิติภาพ — ส่งเสริมเพิ่มด้วยกิจกรรมสั้นและแบบฝึก (ไม่ใช่ป้ายว่าไม่ถนัด)"],"potentialSentence":"ช่วงกลาง–สูง ที่ส่งเสริมตรงจุดแล้วจะเห็นการเติบโตชัด","aptitude":{"lang":{"name":"ภาษา","score":3.875,"activity":4},"logic":{"name":"ตรรกะและคณิตศาสตร์","score":4.275,"activity":5},"science":{"name":"วิทยาศาสตร์และการสืบเสาะ","score":4.275,"activity":5},"spatial":{"name":"มิติสัมพันธ์และมิติภาพ","score":3.475,"activity":3},"body":{"name":"ร่างกายและการเคลื่อนไหว","score":3.475,"activity":3},"music":{"name":"ดนตรีและจังหวะ","score":3.075,"activity":2},"art":{"name":"ศิลปะและการสร้างสรรค์","score":3.475,"activity":3},"social":{"name":"มนุษยสัมพันธ์และการทำงานร่วมกัน","score":3.875,"activity":4},"self":{"name":"การเข้าใจตนเองและการจัดการตนเอง","score":3.875,"activity":4},"nature":{"name":"ธรรมชาติและสิ่งแวดล้อม","score":3.475,"activity":3}},"ability":{"วิทยาศาสตร์":{"score":2.92,"level":{"key":"developing","label":"กำลังพัฒนา"}},"คณิตศาสตร์":{"score":3.52,"level":{"key":"met","label":"ถึงระดับ"}},"ภาษาไทย":{"score":2.92,"level":{"key":"developing","label":"กำลังพัฒนา"}},"ภาษาอังกฤษ":{"score":2.92,"level":{"key":"developing","label":"กำลังพัฒนา"}},"สังคมศึกษา":{"score":2.92,"level":{"key":"developing","label":"กำลังพัฒนา"}}},"psych":{"motivation":4.2,"learningStyle":3.5,"personality":3.5,"note":"เพื่อแนะแนว ไม่ใช่เพื่อวินิจฉัยโรค"},"work":null,"potential":{"score":3.5745,"band":"ช่วงกลาง–สูง ที่ส่งเสริมตรงจุดแล้วจะเห็นการเติบโตชัด","aptAvg":3.715,"abilAvg":3.04,"growthLabel":"อัตราพัฒนา (ข้อมูลจำลอง)","weightsLabel":"ข้อเสนอ: อัตราพัฒนา 35% / ช่องว่าง 30% / แรงจูงใจ 20% / การตอบสนอง 15%"},"pathways":[{"title":"แนวเลือกสาย ม.ปลาย: วิทย์-คณิต (ข้อเสนอ รอยืนยันชื่อสายจริง)","reason":"เด่นด้านวิทยาศาสตร์/ตรรกะจากแบบวัดและความสามารถ","type":"สาย ม.ปลาย"},{"title":"แนวเลือกสาย ม.ปลาย: ศิลป์-คำนวณ (ข้อเสนอ รอยืนยันชื่อสายจริง)","reason":"สมดุลตรรกะกับภาษา เหมาะสายคำนวณ","type":"สาย ม.ปลาย"},{"title":"แนวเลือกสาย ม.ปลาย: ศิลป์-ภาษา (ข้อเสนอ รอยืนยันชื่อสายจริง)","reason":"เด่นด้านภาษา/สร้างสรรค์","type":"สาย ม.ปลาย"}],"plan":{"month":["ทบทวนวิชาหลักสัปดาห์ละ 3 ชุดสั้น","โมดูลบุคลิกภาพ/เป้าหมาย 1 ครั้ง","พูดคุยแนวสาย ม.ปลายกับครูที่ปรึกษา"],"term":["สรุปเส้นทาง 2–3 ทางก่อนเลือกสาย (โดยเฉพาะ ม.3)","นัดสามฝ่าย","ยืนยันชื่อสายจริงของโรงเรียน"]},"confidence":{"key":"enough","label":"ข้อมูลเพียงพอ (ข้อเสนอ)"},"schoolDoes":["จัดกิจกรรมส่งเสริมตามจุดเด่นในชมรม/ชั่วโมงแนะแนว","ครูที่ปรึกษาติดตามแผนรายเดือน","วัดซ้ำเพื่อดูอัตราพัฒนา (ในต้นแบบใช้ข้อมูลจำลอง)"],"homeDoes":["ช่วยจัดเวลาทบทวน","พูดคุยเป้าหมายโดยไม่กดดัน","สนับสนุนการพักผ่อนและสุขภาพ"],"status":"approved"},"stu-b":{"studentId":"stu-b","generatedAt":"2026-11-05T03:00:00.000Z","summary":"ด.ญ.ตัวอย่าง ข. มีจุดเด่นด้านภาษา, ศิลปะและการสร้างสรรค์, มิติสัมพันธ์และมิติภาพ ความสามารถปัจจุบันอยู่ในระดับที่ส่งเสริมต่อได้ และช่วงกลาง–สูง ที่ส่งเสริมตรงจุดแล้วจะเห็นการเติบโตชัด","strengths":["ภาษา — เห็นแนวโน้มจากกิจกรรมและการสังเกต (ข้อมูลจำลอง)","ศิลปะและการสร้างสรรค์ — เห็นแนวโน้มจากกิจกรรมและการสังเกต (ข้อมูลจำลอง)","มิติสัมพันธ์และมิติภาพ — เห็นแนวโน้มจากกิจกรรมและการสังเกต (ข้อมูลจำลอง)"],"promote":["ตรรกะและคณิตศาสตร์ — ส่งเสริมเพิ่มด้วยกิจกรรมสั้นและแบบฝึก (ไม่ใช่ป้ายว่าไม่ถนัด)","วิทยาศาสตร์และการสืบเสาะ — ส่งเสริมเพิ่มด้วยกิจกรรมสั้นและแบบฝึก (ไม่ใช่ป้ายว่าไม่ถนัด)"],"potentialSentence":"ช่วงกลาง–สูง ที่ส่งเสริมตรงจุดแล้วจะเห็นการเติบโตชัด","aptitude":{"lang":{"name":"ภาษา","score":4.38,"activity":5},"logic":{"name":"ตรรกะและคณิตศาสตร์","score":3.58,"activity":3},"science":{"name":"วิทยาศาสตร์และการสืบเสาะ","score":3.58,"activity":3},"spatial":{"name":"มิติสัมพันธ์และมิติภาพ","score":3.9799999999999995,"activity":4},"body":{"name":"ร่างกายและการเคลื่อนไหว","score":3.58,"activity":3},"music":{"name":"ดนตรีและจังหวะ","score":3.9799999999999995,"activity":4},"art":{"name":"ศิลปะและการสร้างสรรค์","score":4.38,"activity":5},"social":{"name":"มนุษยสัมพันธ์และการทำงานร่วมกัน","score":3.9799999999999995,"activity":4},"self":{"name":"การเข้าใจตนเองและการจัดการตนเอง","score":3.58,"activity":3},"nature":{"name":"ธรรมชาติและสิ่งแวดล้อม","score":3.58,"activity":3}},"ability":{"วิทยาศาสตร์":{"score":3.144,"level":{"key":"developing","label":"กำลังพัฒนา"}},"คณิตศาสตร์":{"score":2.5440000000000005,"level":{"key":"developing","label":"กำลังพัฒนา"}},"ภาษาไทย":{"score":3.744,"level":{"key":"met","label":"ถึงระดับ"}},"ภาษาอังกฤษ":{"score":3.744,"level":{"key":"met","label":"ถึงระดับ"}},"สังคมศึกษา":{"score":3.144,"level":{"key":"developing","label":"กำลังพัฒนา"}}},"psych":{"motivation":3.6,"learningStyle":3.5,"personality":3.5,"note":"เพื่อแนะแนว ไม่ใช่เพื่อวินิจฉัยโรค"},"work":null,"potential":{"score":3.0415,"band":"ช่วงกลาง–สูง ที่ส่งเสริมตรงจุดแล้วจะเห็นการเติบโตชัด","aptAvg":3.8600000000000003,"abilAvg":3.2640000000000002,"growthLabel":"อัตราพัฒนา (ข้อมูลจำลอง)","weightsLabel":"ข้อเสนอ: อัตราพัฒนา 35% / ช่องว่าง 30% / แรงจูงใจ 20% / การตอบสนอง 15%"},"pathways":[{"title":"แนวเลือกสาย ม.ปลาย: ศิลป์-ภาษา (ข้อเสนอ รอยืนยันชื่อสายจริง)","reason":"เด่นด้านภาษา/สร้างสรรค์","type":"สาย ม.ปลาย"},{"title":"แนวเลือกสาย ม.ปลาย: ศิลป์-คำนวณ (ข้อเสนอ รอยืนยันชื่อสายจริง)","reason":"สมดุลตรรกะกับภาษา เหมาะสายคำนวณ","type":"สาย ม.ปลาย"},{"title":"แนวเลือกสาย ม.ปลาย: วิทย์-คณิต (ข้อเสนอ รอยืนยันชื่อสายจริง)","reason":"เด่นด้านวิทยาศาสตร์/ตรรกะจากแบบวัดและความสามารถ","type":"สาย ม.ปลาย"}],"plan":{"month":["ทบทวนวิชาหลักสัปดาห์ละ 3 ชุดสั้น","โมดูลบุคลิกภาพ/เป้าหมาย 1 ครั้ง","พูดคุยแนวสาย ม.ปลายกับครูที่ปรึกษา"],"term":["สรุปเส้นทาง 2–3 ทางก่อนเลือกสาย (โดยเฉพาะ ม.3)","นัดสามฝ่าย","ยืนยันชื่อสายจริงของโรงเรียน"]},"confidence":{"key":"enough","label":"ข้อมูลเพียงพอ (ข้อเสนอ)"},"schoolDoes":["จัดกิจกรรมส่งเสริมตามจุดเด่นในชมรม/ชั่วโมงแนะแนว","ครูที่ปรึกษาติดตามแผนรายเดือน","วัดซ้ำเพื่อดูอัตราพัฒนา (ในต้นแบบใช้ข้อมูลจำลอง)"],"homeDoes":["ช่วยจัดเวลาทบทวน","พูดคุยเป้าหมายโดยไม่กดดัน","สนับสนุนการพักผ่อนและสุขภาพ"],"status":"pending"},"stu-c":{"studentId":"stu-c","generatedAt":"2026-11-05T03:00:00.000Z","summary":"ด.ช.ตัวอย่าง ค. มีจุดเด่นด้านร่างกายและการเคลื่อนไหว, ดนตรีและจังหวะ, ธรรมชาติและสิ่งแวดล้อม ความสามารถปัจจุบันอยู่ในระดับที่ส่งเสริมต่อได้ และช่วงกลาง–สูง ที่ส่งเสริมตรงจุดแล้วจะเห็นการเติบโตชัด","strengths":["ร่างกายและการเคลื่อนไหว — เห็นแนวโน้มจากกิจกรรมและการสังเกต (ข้อมูลจำลอง)","ดนตรีและจังหวะ — เห็นแนวโน้มจากกิจกรรมและการสังเกต (ข้อมูลจำลอง)","ธรรมชาติและสิ่งแวดล้อม — เห็นแนวโน้มจากกิจกรรมและการสังเกต (ข้อมูลจำลอง)"],"promote":["การเข้าใจตนเองและการจัดการตนเอง — ส่งเสริมเพิ่มด้วยกิจกรรมสั้นและแบบฝึก (ไม่ใช่ป้ายว่าไม่ถนัด)","ภาษา — ส่งเสริมเพิ่มด้วยกิจกรรมสั้นและแบบฝึก (ไม่ใช่ป้ายว่าไม่ถนัด)"],"potentialSentence":"ช่วงกลาง–สูง ที่ส่งเสริมตรงจุดแล้วจะเห็นการเติบโตชัด","aptitude":{"lang":{"name":"ภาษา","score":3.175,"activity":3},"logic":{"name":"ตรรกะและคณิตศาสตร์","score":3.175,"activity":3},"science":{"name":"วิทยาศาสตร์และการสืบเสาะ","score":3.175,"activity":3},"spatial":{"name":"มิติสัมพันธ์และมิติภาพ","score":3.175,"activity":3},"body":{"name":"ร่างกายและการเคลื่อนไหว","score":3.9749999999999996,"activity":5},"music":{"name":"ดนตรีและจังหวะ","score":3.575,"activity":4},"art":{"name":"ศิลปะและการสร้างสรรค์","score":3.175,"activity":3},"social":{"name":"มนุษยสัมพันธ์และการทำงานร่วมกัน","score":3.175,"activity":3},"self":{"name":"การเข้าใจตนเองและการจัดการตนเอง","score":2.775,"activity":2},"nature":{"name":"ธรรมชาติและสิ่งแวดล้อม","score":3.575,"activity":4}},"ability":{"อ่านเขียนพื้นฐาน":{"score":2.16,"level":{"key":"support","label":"ต้องเสริม"}},"ความเข้าใจจำนวน":{"score":2.76,"level":{"key":"developing","label":"กำลังพัฒนา"}},"การอยู่ร่วมกัน":{"score":2.76,"level":{"key":"developing","label":"กำลังพัฒนา"}}},"psych":{"motivation":3.5,"learningStyle":3.5,"personality":3.5,"note":"เพื่อแนะแนว ไม่ใช่เพื่อวินิจฉัยโรค"},"work":null,"potential":{"score":3.2484999999999995,"band":"ช่วงกลาง–สูง ที่ส่งเสริมตรงจุดแล้วจะเห็นการเติบโตชัด","aptAvg":3.2949999999999995,"abilAvg":2.56,"growthLabel":"อัตราพัฒนา (ข้อมูลจำลอง)","weightsLabel":"ข้อเสนอ: อัตราพัฒนา 35% / ช่องว่าง 30% / แรงจูงใจ 20% / การตอบสนอง 15%"},"pathways":[{"title":"แนวส่งเสริมพัฒนาการด้านร่างกายและการเคลื่อนไหว","reason":"เห็นจุดเด่นจากการเล่นมีโครงสร้างและการสังเกต — ไม่ล็อกอาชีพ","type":"พัฒนาการ"},{"title":"แนวส่งเสริมการอยู่ร่วมกันและการสื่อสาร","reason":"สร้างพื้นฐานการเรียนและการเข้าสังคมช่วงต้น","type":"พัฒนาการ"},{"title":"แนวสำรวจความสนใจผ่านกิจกรรมสั้น","reason":"ให้เด็กได้ลองหลายด้านอย่างปลอดภัย","type":"สำรวจ"}],"plan":{"month":["กิจกรรมเล่นมีโครงสร้างด้านร่างกายและการเคลื่อนไหว สัปดาห์ละ 2 ครั้ง","อ่าน/เล่าเรื่องสั้นกับผู้ปกครอง 10 นาที/วัน","ครูสังเกตการอยู่ร่วมกันในกลุ่ม"],"term":["ทบทวนรูบริกอ่านเขียนและจำนวน","ส่งต่อสิ่งที่บ้านช่วยได้ในรายงานสั้น","ประสานฝ่ายประถมก่อนขยายผล (ข้อเสนอ)"]},"confidence":{"key":"enough","label":"ข้อมูลเพียงพอ (ข้อเสนอ)"},"schoolDoes":["จัดกิจกรรมส่งเสริมตามจุดเด่นในชมรม/ชั่วโมงแนะแนว","ครูที่ปรึกษาติดตามแผนรายเดือน","วัดซ้ำเพื่อดูอัตราพัฒนา (ในต้นแบบใช้ข้อมูลจำลอง)"],"homeDoes":["อ่าน/คุยกับลูกสั้น ๆ ทุกวัน","ชมเมื่อพยายาม ไม่เทียบกับคนอื่น","ตอบแบบสอบถามพฤติกรรมที่บ้าน"],"status":"pending"},"stu-f":{"studentId":"stu-f","generatedAt":"2026-11-05T03:00:00.000Z","summary":"ด.ญ.ตัวอย่าง ฉ. มีจุดเด่นด้านมนุษยสัมพันธ์และการทำงานร่วมกัน, ภาษา, ดนตรีและจังหวะ ความสามารถปัจจุบันอยู่ในระดับที่ส่งเสริมต่อได้ และช่วงกลาง–สูง ที่ส่งเสริมตรงจุดแล้วจะเห็นการเติบโตชัด","strengths":["มนุษยสัมพันธ์และการทำงานร่วมกัน — เห็นแนวโน้มจากกิจกรรมและการสังเกต (ข้อมูลจำลอง)","ภาษา — เห็นแนวโน้มจากกิจกรรมและการสังเกต (ข้อมูลจำลอง)","ดนตรีและจังหวะ — เห็นแนวโน้มจากกิจกรรมและการสังเกต (ข้อมูลจำลอง)"],"promote":["ตรรกะและคณิตศาสตร์ — ส่งเสริมเพิ่มด้วยกิจกรรมสั้นและแบบฝึก (ไม่ใช่ป้ายว่าไม่ถนัด)","วิทยาศาสตร์และการสืบเสาะ — ส่งเสริมเพิ่มด้วยกิจกรรมสั้นและแบบฝึก (ไม่ใช่ป้ายว่าไม่ถนัด)"],"potentialSentence":"ช่วงกลาง–สูง ที่ส่งเสริมตรงจุดแล้วจะเห็นการเติบโตชัด","aptitude":{"lang":{"name":"ภาษา","score":4.07,"activity":4},"logic":{"name":"ตรรกะและคณิตศาสตร์","score":3.67,"activity":3},"science":{"name":"วิทยาศาสตร์และการสืบเสาะ","score":3.67,"activity":3},"spatial":{"name":"มิติสัมพันธ์และมิติภาพ","score":3.67,"activity":3},"body":{"name":"ร่างกายและการเคลื่อนไหว","score":3.67,"activity":3},"music":{"name":"ดนตรีและจังหวะ","score":4.07,"activity":4},"art":{"name":"ศิลปะและการสร้างสรรค์","score":4.07,"activity":4},"social":{"name":"มนุษยสัมพันธ์และการทำงานร่วมกัน","score":4.47,"activity":5},"self":{"name":"การเข้าใจตนเองและการจัดการตนเอง","score":4.07,"activity":4},"nature":{"name":"ธรรมชาติและสิ่งแวดล้อม","score":3.67,"activity":3}},"ability":{"คณิตศาสตร์":{"score":3.08,"level":{"key":"developing","label":"กำลังพัฒนา"}},"ภาษาไทย":{"score":3.68,"level":{"key":"met","label":"ถึงระดับ"}},"วิทยาศาสตร์":{"score":3.08,"level":{"key":"developing","label":"กำลังพัฒนา"}},"สังคมศึกษา":{"score":3.68,"level":{"key":"met","label":"ถึงระดับ"}},"ภาษาอังกฤษ":{"score":3.08,"level":{"key":"developing","label":"กำลังพัฒนา"}}},"psych":{"motivation":4,"learningStyle":3.5,"personality":3.5,"note":"เพื่อแนะแนว ไม่ใช่เพื่อวินิจฉัยโรค"},"work":null,"potential":{"score":3.3805,"band":"ช่วงกลาง–สูง ที่ส่งเสริมตรงจุดแล้วจะเห็นการเติบโตชัด","aptAvg":3.91,"abilAvg":3.3200000000000003,"growthLabel":"อัตราพัฒนา (ข้อมูลจำลอง)","weightsLabel":"ข้อเสนอ: อัตราพัฒนา 35% / ช่องว่าง 30% / แรงจูงใจ 20% / การตอบสนอง 15%"},"pathways":[{"title":"สำรวจความสนใจด้านมนุษยสัมพันธ์และการทำงานร่วมกัน และ ภาษา","reason":"จุดเด่นจากการทำกิจกรรม — ไม่ล็อกอาชีพ","type":"สำรวจ"},{"title":"เสริมทักษะพื้นฐานวิชาการควบคู่ความสนใจ","reason":"เตรียมความพร้อมช่วงเปลี่ยนระดับโดยไม่บีบทางเดียว","type":"สำรวจ"},{"title":"เส้นทางชมรม/ค่ายตามความสนใจ (ทางเลือก)","reason":"ให้ลองกิจกรรมนอกห้องเรียน","type":"ทางเลือก"}],"plan":{"month":["แบบฝึกสั้นด้านมนุษยสัมพันธ์และการทำงานร่วมกัน","สำรวจชมรมที่เกี่ยวกับภาษา","ทบทวนวิชาหลักที่ยังกำลังพัฒนา"],"term":["วัดซ้ำอัตราพัฒนา (ข้อมูลจำลองในต้นแบบ)","รายงานสำรวจความสนใจโดยไม่ล็อกอาชีพ","นัดคุยผู้ปกครอง 1 ครั้ง"]},"confidence":{"key":"enough","label":"ข้อมูลเพียงพอ (ข้อเสนอ)"},"schoolDoes":["จัดกิจกรรมส่งเสริมตามจุดเด่นในชมรม/ชั่วโมงแนะแนว","ครูที่ปรึกษาติดตามแผนรายเดือน","วัดซ้ำเพื่อดูอัตราพัฒนา (ในต้นแบบใช้ข้อมูลจำลอง)"],"homeDoes":["อ่าน/คุยกับลูกสั้น ๆ ทุกวัน","ชมเมื่อพยายาม ไม่เทียบกับคนอื่น","ตอบแบบสอบถามพฤติกรรมที่บ้าน"],"status":"approved"},"stu-g":{"studentId":"stu-g","generatedAt":"2026-11-05T03:00:00.000Z","summary":"นายตัวอย่าง ช. มีจุดเด่นด้านตรรกะและคณิตศาสตร์, วิทยาศาสตร์และการสืบเสาะ, มิติสัมพันธ์และมิติภาพ ความสามารถปัจจุบันอยู่ในระดับที่ส่งเสริมต่อได้ และช่วงกลาง–สูง ที่ส่งเสริมตรงจุดแล้วจะเห็นการเติบโตชัด","strengths":["ตรรกะและคณิตศาสตร์ — เห็นแนวโน้มจากกิจกรรมและการสังเกต (ข้อมูลจำลอง)","วิทยาศาสตร์และการสืบเสาะ — เห็นแนวโน้มจากกิจกรรมและการสังเกต (ข้อมูลจำลอง)","มิติสัมพันธ์และมิติภาพ — เห็นแนวโน้มจากกิจกรรมและการสังเกต (ข้อมูลจำลอง)"],"promote":["ร่างกายและการเคลื่อนไหว — ส่งเสริมเพิ่มด้วยกิจกรรมสั้นและแบบฝึก (ไม่ใช่ป้ายว่าไม่ถนัด)","ดนตรีและจังหวะ — ส่งเสริมเพิ่มด้วยกิจกรรมสั้นและแบบฝึก (ไม่ใช่ป้ายว่าไม่ถนัด)"],"potentialSentence":"ช่วงกลาง–สูง ที่ส่งเสริมตรงจุดแล้วจะเห็นการเติบโตชัด","aptitude":{"lang":{"name":"ภาษา","score":3.55,"activity":3},"logic":{"name":"ตรรกะและคณิตศาสตร์","score":4.35,"activity":5},"science":{"name":"วิทยาศาสตร์และการสืบเสาะ","score":4.35,"activity":5},"spatial":{"name":"มิติสัมพันธ์และมิติภาพ","score":3.95,"activity":4},"body":{"name":"ร่างกายและการเคลื่อนไหว","score":3.1500000000000004,"activity":2},"music":{"name":"ดนตรีและจังหวะ","score":3.1500000000000004,"activity":2},"art":{"name":"ศิลปะและการสร้างสรรค์","score":3.1500000000000004,"activity":2},"social":{"name":"มนุษยสัมพันธ์และการทำงานร่วมกัน","score":3.55,"activity":3},"self":{"name":"การเข้าใจตนเองและการจัดการตนเอง","score":3.95,"activity":4},"nature":{"name":"ธรรมชาติและสิ่งแวดล้อม","score":3.55,"activity":3}},"ability":{"คณิตศาสตร์":{"score":3.616,"level":{"key":"met","label":"ถึงระดับ"}},"ฟิสิกส์":{"score":3.616,"level":{"key":"met","label":"ถึงระดับ"}},"เคมี":{"score":3.616,"level":{"key":"met","label":"ถึงระดับ"}},"ชีววิทยา":{"score":3.016,"level":{"key":"developing","label":"กำลังพัฒนา"}},"ภาษาไทย":{"score":3.016,"level":{"key":"developing","label":"กำลังพัฒนา"}},"ภาษาอังกฤษ":{"score":3.016,"level":{"key":"developing","label":"กำลังพัฒนา"}},"สังคมศึกษา":{"score":3.016,"level":{"key":"developing","label":"กำลังพัฒนา"}}},"psych":{"motivation":4.3,"learningStyle":3.5,"personality":3.5,"note":"เพื่อแนะแนว ไม่ใช่เพื่อวินิจฉัยโรค"},"work":{"things":{"name":"ทำงานกับสิ่งของ/เครื่องมือ","score":3},"data":{"name":"วิเคราะห์ข้อมูล","score":5},"create":{"name":"สร้างสรรค์","score":2},"help":{"name":"ช่วยเหลือผู้อื่น","score":3},"lead":{"name":"นำทีม/ธุรกิจ","score":3},"system":{"name":"ทำงานตามระบบ","score":4}},"potential":{"score":3.443571428571428,"band":"ช่วงกลาง–สูง ที่ส่งเสริมตรงจุดแล้วจะเห็นการเติบโตชัด","aptAvg":3.6699999999999995,"abilAvg":3.273142857142857,"growthLabel":"อัตราพัฒนา (ข้อมูลจำลอง)","weightsLabel":"ข้อเสนอ: อัตราพัฒนา 35% / ช่องว่าง 30% / แรงจูงใจ 20% / การตอบสนอง 15%"},"pathways":[{"title":"แนวคณะ/ลักษณะงาน: วิเคราะห์ข้อมูล (ข้อเสนอ)","reason":"สอดคล้องกลุ่มลักษณะงานและจุดเด่นความถนัด","type":"คณะ/งาน"},{"title":"แผน TCAS แบบข้อเสนอ (รอปฏิทินจริง)","reason":"เตรียมวิชาแกนตามเป้าหมาย + เส้นทบทวนรายภาค","type":"TCAS"},{"title":"เส้นทางสำรอง: ทำงานตามระบบ","reason":"เผื่อปรับเป้าหมายโดยไม่ทิ้งจุดแข็ง","type":"สำรอง"}],"plan":{"month":["แผนทบทวนรายวิชาเป้าหมายสัปดาห์ละ 4 ชุด","ติดตามกลุ่มลักษณะงานที่สนใจ","จำลองตารางเตรียมสอบ (ข้อเสนอรอปฏิทิน TCAS จริง)"],"term":["ทบทวนช่องว่างความรู้รายวิชา","อัปเดตเส้นทางสำรอง","นัดครูแนะแนวก่อนรอบสมัคร"]},"confidence":{"key":"enough","label":"ข้อมูลเพียงพอ (ข้อเสนอ)"},"schoolDoes":["จัดกิจกรรมส่งเสริมตามจุดเด่นในชมรม/ชั่วโมงแนะแนว","ครูที่ปรึกษาติดตามแผนรายเดือน","วัดซ้ำเพื่อดูอัตราพัฒนา (ในต้นแบบใช้ข้อมูลจำลอง)"],"homeDoes":["ช่วยจัดเวลาทบทวน","พูดคุยเป้าหมายโดยไม่กดดัน","สนับสนุนการพักผ่อนและสุขภาพ"],"status":"approved"}}$assess_reports_doc$::jsonb) rep;

insert into public.assess_pathways (student_id, ord, title, reason, path_type)
select r.student_id, t.ord::integer, t.p->>'title', t.p->>'reason', t.p->>'type'
from public.assess_reports r
cross join lateral jsonb_array_elements(r.report->'pathways') with ordinality as t(p, ord);

do $assess_check$
declare
  n integer;
begin
  if (select count(*) from public.assess_users) <> 19 then
    raise exception 'assess user count';
  end if;
  if (select count(*) from public.assess_students) <> 8 then
    raise exception 'assess student count';
  end if;
  if (select count(*) from public.assess_user_students) <> 32 then
    raise exception 'assess link count';
  end if;
  select count(*) into n from public.assess_items;
  if n <> 203 then
    raise exception 'assess item count %', n;
  end if;
  if (select count(*) from public.assess_progress) <> 48 then
    raise exception 'assess progress count';
  end if;
  if (select count(*) from public.assess_reports) <> 5 then
    raise exception 'assess report count';
  end if;
  if (select count(*) from public.assess_pathways) <> 15 then
    raise exception 'assess pathway count';
  end if;
  if exists (select 1 from public.assess_users where password_hash !~ '^\$2[ab]\$' or position('demo' in password_hash) > 0) then
    raise exception 'assess password hash';
  end if;
  if exists (select 1 from public.assess_students where position('ตัวอย่าง' in name) = 0 or fictional is distinct from true) then
    raise exception 'assess sample students';
  end if;
  if exists (select 1 from public.assess_students where code !~ '^PMW-[A-Z0-9-]+$') then
    raise exception 'assess sample codes';
  end if;
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name like 'assess\_%'
      and column_name ~* 'nid|national|citizen|passport'
  ) then
    raise exception 'assess unexpected id column';
  end if;
  if exists (
    select 1 from pg_class c
    join pg_namespace ns on ns.oid = c.relnamespace
    where ns.nspname = 'public' and c.relkind = 'r' and c.relname like 'assess\_%'
      and c.relrowsecurity is not true
  ) then
    raise exception 'assess rls';
  end if;
end
$assess_check$;

notify pgrst, 'reload schema';
