import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';
import { config, supabaseConfigured } from './config.js';

export const supabase = supabaseConfigured
  ? createClient(config.supabaseUrl, config.supabaseAnonKey, {
      auth: { autoRefreshToken: true, persistSession: true, detectSessionInUrl: true }
    })
  : null;

export function backendMessage(error) {
  if (!supabase) return 'Supabase is not configured. Set the project URL and publishable key in js/config.js.';
  return error?.message || 'Something went wrong. Please try again.';
}
