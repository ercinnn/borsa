-- Borsa Takip: watchlist ve notifications tabloları.
-- Supabase Dashboard > SQL Editor'de bir kez çalıştırın.
-- Kolon adları proxy_server/lib/store.dart ve monthly_low_checker.dart'taki
-- JSON alan adlarıyla birebir eşleşiyor (createdAt tırnaklı, camelCase).

create table if not exists watchlist (
  symbol text primary key
);

create table if not exists notifications (
  id text primary key,
  symbol text not null,
  price double precision not null,
  currency text not null default '',
  date text not null,
  "createdAt" text not null,
  message text not null
);

create index if not exists notifications_symbol_date_idx
  on notifications (symbol, date);
create index if not exists notifications_created_at_idx
  on notifications ("createdAt" desc);

-- RLS açık, hiç politika yok: yalnızca service_role anahtarı (proxy_server)
-- erişebilir, anon/public anahtarla hiçbir satır okunamaz/yazılamaz.
alter table watchlist enable row level security;
alter table notifications enable row level security;
