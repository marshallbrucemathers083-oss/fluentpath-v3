export const config = {
  supabaseUrl: 'https://grlwwmkjwhbxsnnfrovv.supabase.co',
  supabaseAnonKey: 'sb_publishable_i0EMY0ZFhv-hH4a72uP-ig_rZXPC_x9'
};

export const supabaseConfigured = Boolean(
  config.supabaseUrl && config.supabaseAnonKey && !config.supabaseAnonKey.includes('replace-me')
);
