-- Mistake tracker: per-turn detections persisted for aggregation + reminders.

create table if not exists public.user_mistakes (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    session_id uuid references public.sessions(id) on delete set null,
    rule_id text not null,
    category text not null,
    snippet text not null,
    suggestion text,
    source text not null check (source in ('lt', 'llm')),
    created_at timestamptz not null default now()
);

create index if not exists idx_user_mistakes_user_time
    on public.user_mistakes (user_id, created_at desc);

create index if not exists idx_user_mistakes_category
    on public.user_mistakes (user_id, category);

-- Top-N category aggregation used by reminder_service.
create or replace function public.top_mistake_categories(
    p_user uuid, p_days int
)
returns table(category text, n int)
language sql stable as $$
    select category, count(*)::int as n
    from public.user_mistakes
    where user_id = p_user
      and created_at > now() - (p_days || ' days')::interval
    group by category
    order by count(*) desc
    limit 3;
$$;

-- Reminder schedule lives on user_settings.
alter table public.user_settings
    add column if not exists reminder_hour smallint default 19,
    add column if not exists reminder_timezone text default 'UTC',
    add column if not exists last_reminder_sent_date date;
