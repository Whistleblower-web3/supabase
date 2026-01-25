
-- ============================================
-- 3. Trigger functions for token total amounts
-- ============================================

-- ============================================
-- Trigger function: update token_total_amounts table (payment)
-- ============================================
-- Listen to: payments table INSERT -> OrderPaid
CREATE OR REPLACE FUNCTION update_token_total_amounts_on_payment()
RETURNS TRIGGER AS $$
DECLARE
    v_id TEXT;
BEGIN
    v_id := NEW.token || '-OrderPaid';

    INSERT INTO token_total_amounts (
        network, layer, id, token, fund_manager_id, funds_type, amount
    )
    VALUES (
        NEW.network, NEW.layer, v_id, NEW.token, 'fundManager', 'OrderPaid', NEW.amount
    )
    ON CONFLICT (network, layer, token, funds_type)
    DO UPDATE SET
        amount = token_total_amounts.amount + NEW.amount;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_token_total_amounts_on_payment
AFTER INSERT ON payments
FOR EACH ROW
EXECUTE FUNCTION update_token_total_amounts_on_payment();


-- ============================================
-- Trigger function: update token_total_amounts table (RewardsAdded-Total)
-- ============================================
-- Listen to: rewards_addeds table INSERT
-- When Total type of reward is added, update RewardsAdded type of token_total_amounts
CREATE OR REPLACE FUNCTION update_token_total_amounts_on_rewards_added()
RETURNS TRIGGER AS $$
DECLARE
    v_id TEXT;
    v_amount_change NUMERIC(78, 0);
BEGIN
    -- Only process Total type of reward
    IF NEW.reward_type != 'Total' THEN
        RETURN NEW;
    END IF;

    -- Calculate amount change
    IF TG_OP = 'INSERT' THEN
        v_amount_change := NEW.amount;
    ELSE
        v_amount_change := NEW.amount - COALESCE(OLD.amount, 0);
    END IF;

    -- If amount is not changed, skip
    IF v_amount_change = 0 THEN
        RETURN NEW;
    END IF;

    -- Update token_total_amounts table
    v_id := NEW.token || '-RewardsAdded';
    INSERT INTO token_total_amounts (
        network, layer, id, token, fund_manager_id, funds_type, amount
    )
    VALUES (
        NEW.network, NEW.layer, v_id, NEW.token, 'fundManager', 'RewardsAdded', 
        GREATEST(0, COALESCE((SELECT amount FROM token_total_amounts WHERE network = NEW.network AND layer = NEW.layer AND token = NEW.token AND funds_type = 'RewardsAdded'), 0) + v_amount_change)
    )
    ON CONFLICT (network, layer, token, funds_type)
    DO UPDATE SET
        amount = GREATEST(0, token_total_amounts.amount + v_amount_change);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger
CREATE TRIGGER trigger_update_token_total_amounts_on_rewards_added
AFTER INSERT ON rewards_addeds
FOR EACH ROW
WHEN (NEW.reward_type = 'Total')
EXECUTE FUNCTION update_token_total_amounts_on_rewards_added();


-- ============================================
-- Trigger function: update token_total_amounts table (withdraw)
-- ============================================
-- Listen to: withdraws table INSERT -> update funds_type of token_total_amounts based on withdraw_type
CREATE OR REPLACE FUNCTION update_token_total_amounts_on_withdraw()
RETURNS TRIGGER AS $$
DECLARE
    v_id TEXT;
    v_funds_type TEXT;
BEGIN
    v_funds_type := CASE NEW.withdraw_type
        WHEN 'Order' THEN 'OrderWithdraw'
        WHEN 'Helper' THEN 'HelperRewardsWithdraw'
        WHEN 'Minter' THEN 'MinterRewardsWithdraw'
        WHEN 'Refund' THEN 'RefundWithdraw'
        ELSE NULL
    END;

    IF v_funds_type IS NULL THEN
        RETURN NEW;
    END IF;

    v_id := NEW.token || '-' || v_funds_type;

    INSERT INTO token_total_amounts (
        network, layer, id, token, fund_manager_id, funds_type, amount
    )
    VALUES (
        NEW.network, NEW.layer, v_id, NEW.token, 'fundManager', v_funds_type, NEW.amount
    )
    ON CONFLICT (network, layer, token, funds_type)
    DO UPDATE SET
        amount = token_total_amounts.amount + NEW.amount;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_token_total_amounts_on_withdraw
AFTER INSERT ON withdraws
FOR EACH ROW
EXECUTE FUNCTION update_token_total_amounts_on_withdraw();
