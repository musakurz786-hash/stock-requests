// Stock Requests — configuration
// Fill these in, then commit. The Supabase key is meant to be embedded in client-side code
// (protected by RLS policies) — same model as WHIP and the Staff Allowance app.

const CONFIG = {
  SB_URL: '',   // e.g. https://xxxxxxxx.supabase.co
  SB_KEY: '',   // Project Settings -> API -> anon / publishable key

  EMAILJS_PUBLIC_KEY: '',           // Account -> General -> Public Key (leave blank to disable email)
  EMAILJS_SERVICE_ID: '',
  EMAILJS_TEMPLATE_ID_SUBMITTED: '', // sent to approver when a new request comes in
  EMAILJS_TEMPLATE_ID_DECIDED: '',   // sent to requester when approved/rejected
  EMAILJS_TEMPLATE_ID_FULFILLED: '', // sent to requester when picked/shipped

  APPROVER_EMAIL: 'musa@freedomofmovement.co.za',
  WAREHOUSE_EMAIL: 'musa@freedomofmovement.co.za',

  ADMIN_PASSWORD: 'fom-admin-2026' // soft gate only, not real security — internal tool
};
