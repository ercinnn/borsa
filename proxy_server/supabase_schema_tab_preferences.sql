-- Kullanıcının alt gezinme çubuğunda hangi sekmeleri gizlediği (Ayarlar
-- sekmesi). supabase_schema.sql, supabase_schema_auth.sql ve
-- supabase_schema_favorites.sql'den SONRA, Supabase SQL Editor'de bir kez
-- çalıştırılır. tracked_symbol ile aynı desen: kullanıcı başına tek satır,
-- upsert (resolution=merge-duplicates) ile yazılır, geçmiş tutulmaz.
-- hidden_tabs boşsa (varsayılan) tüm sekmeler görünür demektir; Ayarlar
-- sekmesinin kendisi bu listeye hiç girmez (frontend'de kapatılamaz).

create table if not exists tab_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  hidden_tabs jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now()
);

alter table tab_preferences enable row level security;

drop policy if exists "select own tab_preferences" on tab_preferences;
create policy "select own tab_preferences" on tab_preferences
  for select using (auth.uid() = user_id);

drop policy if exists "insert own tab_preferences" on tab_preferences;
create policy "insert own tab_preferences" on tab_preferences
  for insert with check (auth.uid() = user_id);

drop policy if exists "update own tab_preferences" on tab_preferences;
create policy "update own tab_preferences" on tab_preferences
  for update using (auth.uid() = user_id);
