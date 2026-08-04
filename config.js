// Stock Requests — configuration
// The Supabase key is meant to be embedded in client-side code (protected by RLS policies) —
// same model as WHIP and the Staff Allowance app. This app shares WHIP's Supabase project (free
// tier caps projects per org) but lives in its own "stock_requests" schema — see schema.sql for
// the one-time "Exposed schemas" step that has to be done in the Supabase dashboard first.

const CONFIG = {
  SB_URL: 'https://wqsibegaczuhgrcjwitl.supabase.co',
  SB_KEY: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Indxc2liZWdhY3p1aGdyY2p3aXRsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA2OTg2MzgsImV4cCI6MjA5NjI3NDYzOH0.IyXcvF3HbPqgdyl2vsFTzXUc8VuUWjgTnyYQMJomzkw',
  SB_SCHEMA: 'stock_requests',

  // Reuses the same EmailJS account/service as the Staff Allowance app (RSLU4ptjtK9who1fa /
  // service_637v8yq) — one EmailJS account can hold many templates, so no new account needed,
  // just a new template. Fill in EMAILJS_TEMPLATE_ID_SUBMITTED once that template exists —
  // see email-template-submitted.html for its content.
  EMAILJS_PUBLIC_KEY: 'RSLU4ptjtK9who1fa',
  EMAILJS_SERVICE_ID: 'service_637v8yq',
  EMAILJS_TEMPLATE_ID_SUBMITTED: '',  // sent to LOGISTICS_EMAIL when a new request comes in
  EMAILJS_TEMPLATE_ID_TRANSFERRED: '', // sent to requester once a Transfer # is recorded (stock is on its way)

  LOGISTICS_EMAIL: 'musa@freedomofmovement.co.za',

  ADMIN_PASSWORD: 'fom-admin-2026' // soft gate only, not real security — internal tool
};
