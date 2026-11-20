// Supabase URL ve anon key gizli değildir (RLS ile korunur), bu yüzden
// API_BASE_URL gibi doğrudan gömülü tutuluyor. Gerekirse
// --dart-define=SUPABASE_URL=... / SUPABASE_ANON_KEY=... ile geçersiz
// kılınabilir (ör. farklı bir Supabase projesiyle test için).
const supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://ccaxmemcetlgmofvhhgh.supabase.co',
);

const supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: 'sb_publishable_naZNul0A6WAeK4b-bmMIWg_hVKsSzJk',
);
