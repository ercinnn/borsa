// Supabase URL ve anon key gizli değildir (RLS ile korunur), bu yüzden
// API_BASE_URL gibi doğrudan gömülü tutuluyor. Gerekirse
// --dart-define=SUPABASE_URL=... / SUPABASE_ANON_KEY=... ile geçersiz
// kılınabilir (ör. farklı bir Supabase projesiyle test için).
const supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://riugphrucjbiaomuylqh.supabase.co',
);

const supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: 'sb_publishable_gqaLnPySeqU-Y_e8_O0zRw_k5_kB9VV',
);
