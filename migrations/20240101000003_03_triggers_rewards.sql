
-- ============================================
-- 1. Trigger functions for rewards
-- ============================================

-- ============================================
-- Trigger function: update box_rewards table (accumulate rewards)
-- ============================================
-- Listen to: rewards_addeds table INSERT
-- When the RewardAmountAdded event is inserted, accumulate to the box_rewards table
-- Accumulate amount based on box_id, reward_type, and token
CREATE OR REPLACE FUNCTION update_box_rewards_on_rewards_added()
RETURNS TRIGGER AS $$
DECLARE
    v_reward_id TEXT;
BEGIN
    -- Accumulate rewards to the box_rewards table
    v_reward_id := NEW.box_id::TEXT || '-' || NEW.reward_type || '-' || NEW.token;
    INSERT INTO box_rewards (
        network, layer, id, box_id, reward_type, token, amount
    )
    VALUES (
        NEW.network, NEW.layer, v_reward_id, NEW.box_id, NEW.reward_type, NEW.token, NEW.amount
    )
    ON CONFLICT (network, layer, box_id, reward_type, token)
    DO UPDATE SET
        amount = box_rewards.amount + NEW.amount;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger
CREATE TRIGGER trigger_update_box_rewards_on_rewards_added
AFTER INSERT ON rewards_addeds
FOR EACH ROW
EXECUTE FUNCTION update_box_rewards_on_rewards_added();


-- ============================================
-- Trigger function: update user_rewards table (reward added)
-- ============================================
-- Listen to: rewards_addeds table INSERT
-- Need to find minter_id/seller_id/completer_id based on boxId
-- Then accumulate amount based on minter_id/seller_id/completer_id
CREATE OR REPLACE FUNCTION update_user_rewards_on_rewards_added()
RETURNS TRIGGER AS $$
DECLARE
    v_minter_id TEXT;
    v_seller_id TEXT;
    v_completer_id TEXT;
    v_user_id TEXT;
    v_user_reward_id TEXT;
    v_amount_change NUMERIC(78, 0);
BEGIN
    -- Only process Minter, Seller, Completer reward types (skip Total)
    IF NEW.reward_type NOT IN ('Minter', 'Seller', 'Completer') THEN
        RETURN NEW;
    END IF;

    -- Get user information from box
    SELECT minter_id, seller_id, completer_id
    INTO v_minter_id, v_seller_id, v_completer_id
    FROM boxes
    WHERE network = NEW.network 
        AND layer = NEW.layer 
        AND id = NEW.box_id;

    -- Calculate amount change
    IF TG_OP = 'INSERT' THEN
        v_amount_change := NEW.amount;
    ELSE
        v_amount_change := NEW.amount - COALESCE(OLD.amount, 0);
    END IF;

    -- Determine user based on reward type
    v_user_id := CASE NEW.reward_type
        WHEN 'Minter' THEN v_minter_id
        WHEN 'Seller' THEN v_seller_id
        WHEN 'Completer' THEN v_completer_id
        ELSE NULL
    END;

    -- If user ID is empty, skip
    IF v_user_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- Update user rewards (Minter/Seller/Completer)
    v_user_reward_id := v_user_id::TEXT || '-' || NEW.reward_type || '-' || NEW.token;
    INSERT INTO user_rewards (
        network, layer, id, user_id, reward_type, token, amount
    )
    VALUES (
        NEW.network, NEW.layer, v_user_reward_id, v_user_id, NEW.reward_type, NEW.token, 
        GREATEST(0, COALESCE((SELECT amount FROM user_rewards WHERE network = NEW.network AND layer = NEW.layer AND user_id = v_user_id AND reward_type = NEW.reward_type AND token = NEW.token), 0) + v_amount_change)
    )
    ON CONFLICT (network, layer, user_id, reward_type, token)
    DO UPDATE SET
        amount = GREATEST(0, user_rewards.amount + v_amount_change);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger
CREATE TRIGGER trigger_update_user_rewards_on_rewards_added
AFTER INSERT ON rewards_addeds
FOR EACH ROW
WHEN (NEW.reward_type IN ('Minter', 'Seller', 'Completer'))
EXECUTE FUNCTION update_user_rewards_on_rewards_added();


-- ============================================
-- Trigger function: update user_withdraws table (accumulate withdrawal amount)
-- ============================================
-- Listen to: withdraws table INSERT
-- Only process Helper and Minter type of withdrawal
CREATE OR REPLACE FUNCTION update_user_withdraws_on_withdraw()
RETURNS TRIGGER AS $$
DECLARE
    v_id TEXT;
BEGIN
    IF NEW.withdraw_type != 'Reward' THEN
        RETURN NEW;
    END IF;

    -- Update user_withdraws table (accumulate)
    v_id := NEW.user_id || '-' || NEW.withdraw_type || '-' || NEW.token;
    INSERT INTO user_withdraws (
        network, layer, id, user_id, withdraw_type, token, amount
    )
    VALUES (
        NEW.network, NEW.layer, v_id, NEW.user_id, NEW.withdraw_type, NEW.token, NEW.amount
    )
    ON CONFLICT (network, layer, user_id, withdraw_type, token)
    DO UPDATE SET
        amount = user_withdraws.amount + NEW.amount;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_user_withdraws_on_withdraw
AFTER INSERT ON withdraws
FOR EACH ROW
WHEN (NEW.withdraw_type = 'Reward')
EXECUTE FUNCTION update_user_withdraws_on_withdraw();
