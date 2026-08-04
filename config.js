// Stock Requests — configuration
// The Supabase key is meant to be embedded in client-side code (protected by RLS policies) —
// same model as WHIP and the Staff Allowance app. This app shares WHIP's Supabase project (free
// tier caps projects per org) but lives in its own "stock_requests" schema — see schema.sql for
// the one-time "Exposed schemas" step that has to be done in the Supabase dashboard first.

const CONFIG = {
  SB_URL: 'https://wqsibegaczuhgrcjwitl.supabase.co',
  SB_KEY: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Indxc2liZWdhY3p1aGdyY2p3aXRsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA2OTg2MzgsImV4cCI6MjA5NjI3NDYzOH0.IyXcvF3HbPqgdyl2vsFTzXUc8VuUWjgTnyYQMJomzkw',
  SB_SCHEMA: 'stock_requests',

  // Separate free EmailJS account (own 2-template/200-email allowance, independent of the
  // Staff Allowance app's account) — handles the "request submitted" notification with a
  // branded template. Template is the account's auto-created "Order Confirmation" template,
  // repurposed with our own content — see email-template-submitted.html. One free template
  // slot still spare on this account if another notification is added later.
  EMAILJS_PUBLIC_KEY: 'neFl0OLWFDzTuEBLI',
  EMAILJS_SERVICE_ID: 'service_hee0ini',
  EMAILJS_TEMPLATE_ID_SUBMITTED: 'template_94xemaq',

  LOGISTICS_EMAIL: 'musa@freedomofmovement.co.za',

  ADMIN_PASSWORD: 'fom-admin-2026' // soft gate only, not real security — internal tool
};
