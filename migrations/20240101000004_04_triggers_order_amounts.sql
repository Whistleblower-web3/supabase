
-- ============================================
-- 2. Trigger functions for order amounts
-- ============================================

-- ============================================
-- Trigger function: update box_user_order_amounts table (payment)
-- ============================================
-- Listen to: payments table INSERT
-- All payments are accumulated to box_user_order_amounts
CREATE OR REPLACE FUNCTION update_box_user_order_amounts_on_payment()
RETURNS TRIGGER AS $$
DECLARE
    v_fund_id TEXT;
BEGIN
    -- Accumulate payment amount to box_user_order_amounts
    v_fund_id := NEW.user_id::TEXT || '-' || NEW.box_id::TEXT || '-' || NEW.token;
    INSERT INTO box_user_order_amounts (
        network, layer, id, user_id, box_id, token, amount
    )
    VALUES (
        NEW.network, NEW.layer, v_fund_id, NEW.user_id, NEW.box_id, NEW.token, NEW.amount
    )
    ON CONFLICT (network, layer, user_id, box_id, token)
    DO UPDATE SET
        amount = box_user_order_amounts.amount + NEW.amount;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_box_user_order_amounts_on_payment
AFTER INSERT ON payments
FOR EACH ROW
EXECUTE FUNCTION update_box_user_order_amounts_on_payment();


-- ============================================
-- Trigger function: update box_user_order_amounts table (withdraw)
-- ============================================
-- Listen to: withdraws table INSERT
-- withdraw_type: 'Order' or 'Refund' -> clear order funds for corresponding box and user (in the contract, withdraw is to withdraw all funds)
CREATE OR REPLACE FUNCTION update_box_user_order_amounts_on_withdraw()
RETURNS TRIGGER AS $$
DECLARE
    v_box_id NUMERIC(78, 0);
    v_user_id NUMERIC(78, 0);
BEGIN
    IF NEW.withdraw_type NOT IN ('Order', 'Refund') THEN
        RETURN NEW;
    END IF;

    -- user_id in withdraws table is NUMERIC(78, 0), directly use
    v_user_id := NEW.user_id;

    -- If box_list is empty, skip
    IF NEW.box_list IS NULL OR array_length(NEW.box_list, 1) = 0 THEN
        RETURN NEW;
    END IF;

    -- Loop through box_list, clear the funds of each box (in the contract, withdraw is to withdraw all funds)
    FOREACH v_box_id IN ARRAY NEW.box_list
    LOOP
        UPDATE box_user_order_amounts
        SET amount = 0
        WHERE network = NEW.network
            AND layer = NEW.layer
            AND user_id = v_user_id
            AND box_id = v_box_id
            AND token = NEW.token;
    END LOOP;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_box_user_order_amounts_on_withdraw
AFTER INSERT ON withdraws
FOR EACH ROW
WHEN (NEW.withdraw_type IN ('Order', 'Refund'))
EXECUTE FUNCTION update_box_user_order_amounts_on_withdraw();


-- ============================================
-- Trigger function: update box_user_order_amounts table (clear buyer's funds)
-- ============================================
-- Listen to: box_rewards table INSERT (only process Seller/Completer type)
CREATE OR REPLACE FUNCTION update_box_user_order_amounts_on_rewards_added()
RETURNS TRIGGER AS $$
DECLARE
    v_buyer_id NUMERIC(78, 0);
BEGIN
    -- Only process Seller or Completer rewards (skip Minter/Total)
    IF NEW.reward_type NOT IN ('Seller', 'Completer') THEN
        RETURN NEW;
    END IF;

    -- Only process INSERT or amount increase rewards
    IF TG_OP = 'UPDATE' AND NEW.amount <= COALESCE(OLD.amount, 0) THEN
        RETURN NEW;
    END IF;

    -- Get buyer_id from box
    SELECT buyer_id
    INTO v_buyer_id
    FROM boxes
    WHERE network = NEW.network 
        AND layer = NEW.layer 
        AND id = NEW.box_id;

    -- If buyer_id is empty, skip
    IF v_buyer_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- Clear buyer's order funds for this box and this token
    UPDATE box_user_order_amounts
    SET amount = 0
    WHERE network = NEW.network
        AND layer = NEW.layer
        AND user_id = v_buyer_id
        AND box_id = NEW.box_id
        AND token = NEW.token;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_box_user_order_amounts_on_rewards_added
AFTER INSERT ON rewards_addeds
FOR EACH ROW
WHEN (NEW.reward_type IN ('Seller', 'Completer'))
EXECUTE FUNCTION update_box_user_order_amounts_on_rewards_added();
