// Stock Requests — configuration
// The Supabase key is meant to be embedded in client-side code (protected by RLS policies) —
// same model as WHIP and the Staff Allowance app. This app shares WHIP's Supabase project (free
// tier caps projects per org) but lives in its own "stock_requests" schema — see schema.sql for
// the one-time "Exposed schemas" step that has to be done in the Supabase dashboard first.

const CONFIG = {
  SB_URL: 'https://wqsibegaczuhgrcjwitl.supabase.co',
  SB_KEY: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Indxc2liZWdhY3p1aGdyY2p3aXRsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA2OTg2MzgsImV4cCI6MjA5NjI3NDYzOH0.IyXcvF3HbPqgdyl2vsFTzXUc8VuUWjgTnyYQMJomzkw',
  SB_SCHEMA: 'stock_requests',

  // Web3Forms (web3forms.com) — free, no dashboard template to configure or run out of; it just
  // emails whatever fields get posted to it, routed to whichever address the access key was
  // created with. Sign up free, grab the Access Key, paste it below. Leave blank to disable
  // notifications entirely.
  WEB3FORMS_ACCESS_KEY: '',

  LOGISTICS_EMAIL: 'musa@freedomofmovement.co.za',

  ADMIN_PASSWORD: 'fom-admin-2026' // soft gate only, not real security — internal tool
};
