-- Preserve past receipts; current redemption function only inserts 999 CAD cents.
alter table private.dating_payment_redemptions drop constraint dating_payment_redemptions_amount_cents_check; alter table private.dating_payment_redemptions add constraint dating_payment_redemptions_amount_cents_check check (amount_cents in (499,999));
