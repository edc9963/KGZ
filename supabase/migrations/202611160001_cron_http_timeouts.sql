-- Bring the card-bill LINE reminder schedule into source control and give
-- both Edge Function cron calls a realistic HTTP timeout.
--
-- quick-ledger-card-bill-reminders was created by hand in the hosted
-- database (supabase/functions/card-bill-reminders said "not scheduled
-- from inside this project"), so a fresh database never got it. It is
-- recreated here with the same name, schedule and body.
--
-- net.http_post defaults to a 5 s timeout. A cold-started Edge Function
-- that then pushes LINE messages can exceed that: on 2026-11-16 the
-- reminder call hit "Timeout of 5000 ms reached". Both HTTP jobs now
-- wait up to 30 s.
--
-- Like the quotes job, the reminder job is inert until project_url and
-- card_reminder_cron_secret exist in Supabase Vault.

-- Daily 08:00 Asia/Taipei (00:00 UTC).
do $$
begin
  if exists (select 1 from cron.job
             where jobname = 'quick-ledger-card-bill-reminders') then
    perform cron.unschedule('quick-ledger-card-bill-reminders');
  end if;
  perform cron.schedule(
    'quick-ledger-card-bill-reminders', '0 0 * * *', $job$
      select net.http_post(
        url := (select decrypted_secret from vault.decrypted_secrets
                where name = 'project_url') || '/functions/v1/card-bill-reminders',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets
                            where name = 'card_reminder_cron_secret')
        ),
        body := '{"action":"send"}'::jsonb,
        timeout_milliseconds := 30000
      )
      where exists (select 1 from vault.decrypted_secrets where name = 'project_url')
        and exists (select 1 from vault.decrypted_secrets
                    where name = 'card_reminder_cron_secret');
    $job$
  );
end
$$;

-- Monday-Friday 18:30 Asia/Taipei (10:30 UTC); unchanged apart from the
-- timeout (see 202608200002_investment_quotes_v8.sql).
do $$
begin
  if exists (select 1 from cron.job where jobname = 'quick-ledger-twse-quotes') then
    perform cron.unschedule('quick-ledger-twse-quotes');
  end if;
  perform cron.schedule(
    'quick-ledger-twse-quotes', '30 10 * * 1-5', $job$
      select net.http_post(
        url := (select decrypted_secret from vault.decrypted_secrets
                where name = 'project_url') || '/functions/v1/investment-quotes',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets
                            where name = 'investment_quote_cron_secret')
        ),
        body := '{"action":"refresh"}'::jsonb,
        timeout_milliseconds := 30000
      )
      where exists (select 1 from vault.decrypted_secrets where name = 'project_url')
        and exists (select 1 from vault.decrypted_secrets
                    where name = 'investment_quote_cron_secret');
    $job$
  );
end
$$;
