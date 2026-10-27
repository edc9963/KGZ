-- Apply a remembered card / account mapping to captures already waiting.
--
-- Matching runs when a capture is ingested, so captures that arrived
-- together (one Apps Script run forwarding several debit notices, or two
-- Apple Pay taps before the first answer) were all stored as 'unknown', and
-- answering the first one left the others asking again. Whenever a label's
-- mapping is saved, pending captures with that label that are still
-- 'unknown' now take it too.

create or replace function public.capture_apply_alias()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.capture_inbox i
  set card_id = new.card_id,
      account_id = new.account_id,
      card_resolution = case
        when new.card_id is not null then 'card'
        when new.account_id is not null then 'account'
        else 'none'
      end
  where i.user_id = new.user_id and i.card_label = new.card_label
    and i.status = 'pending' and i.card_resolution = 'unknown'
    -- A card mapping only fits card captures and an account mapping only
    -- account captures;「不指定」fits both.
    and case
      when public.capture_uses_account(i.source) then new.card_id is null
      else new.account_id is null
    end;
  return new;
end
$$;

create trigger capture_card_aliases_apply
after insert or update on public.capture_card_aliases
for each row execute function public.capture_apply_alias();

-- Captures already stuck behind an answered label.
update public.capture_inbox i
set card_id = a.card_id,
    account_id = a.account_id,
    card_resolution = case
      when a.card_id is not null then 'card'
      when a.account_id is not null then 'account'
      else 'none'
    end
from public.capture_card_aliases a
where a.user_id = i.user_id and a.card_label = i.card_label
  and i.status = 'pending' and i.card_resolution = 'unknown'
  and case
    when public.capture_uses_account(i.source) then a.card_id is null
    else a.account_id is null
  end;

revoke all on function public.capture_apply_alias()
  from public, anon, authenticated;
