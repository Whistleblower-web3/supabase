
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
-- Trigger function: update user_withdraws table (accumulate withdrawal amount)
-- ============================================
-- Listen to: withdraws table INSERT
-- Only process Helper and Minter type of withdrawal
CREATE OR REPLACE FUNCTION update_user_withdraws_on_withdraw()
RETURNS TRIGGER AS $$
DECLARE
    v_id TEXT;
BEGIN
    IF NEW.withdraw_type NOT IN ('Helper', 'Minter') THEN
        RETURN NEW;
    END IF;

    -- Update user_withdraws table (accumulate)
    v_id := NEW.user_id::TEXT || '-' || NEW.withdraw_type || '-' || NEW.token;
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
WHEN (NEW.withdraw_type IN ('Helper', 'Minter'))
EXECUTE FUNCTION update_user_withdraws_on_withdraw();

-- ============================================
-- Trigger function: update user_rewards table (reward added)
-- ============================================
-- Listen to: rewards_addeds table INSERT
-- Need to find minter_id/seller_id/completer_id based on boxId
-- Then accumulate amount based on minter_id/seller_id/completer_id
CREATE OR REPLACE FUNCTION update_user_rewards_on_rewards_added()
RETURNS TRIGGER AS $$
DECLARE
    v_minter_id NUMERIC(78, 0);
    v_seller_id NUMERIC(78, 0);
    v_completer_id NUMERIC(78, 0);
    v_user_id NUMERIC(78, 0);
    v_user_reward_id TEXT;
    v_amount_change NUMERIC(78, 0);
BEGIN
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
    -- Note: user_rewards does not include Total type, only records rewards assigned to specific roles
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
AFTER INSERT OR UPDATE ON box_rewards
FOR EACH ROW
WHEN (NEW.reward_type IN ('Minter', 'Seller', 'Completer'))
EXECUTE FUNCTION update_user_rewards_on_rewards_added();


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
-- Listen to: rewards_addeds table INSERT (only process Seller/Completer type),
CREATE OR REPLACE FUNCTION update_box_user_order_amounts_on_rewards_added()
RETURNS TRIGGER AS $$
DECLARE
    v_buyer_id NUMERIC(78, 0);
BEGIN
    IF NEW.reward_type NOT IN ('Seller', 'Completer') THEN
        RETURN NEW;
    END IF;

    -- Only process新增奖励的情况（INSERT）或金额增加的情况（UPDATE）
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
AFTER INSERT OR UPDATE ON box_rewards
FOR EACH ROW
WHEN (NEW.reward_type IN ('Seller', 'Completer'))
EXECUTE FUNCTION update_box_user_order_amounts_on_rewards_added();

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
-- Note: directly listen to rewards_addeds table, because only Total type is needed
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

-- ============================================
-- Trigger function: update statistical_state table
-- ============================================
-- Listen to: boxes table INSERT -> BoxCreated
-- Listen to: boxes table UPDATE status -> BoxStatusChanged
CREATE OR REPLACE FUNCTION update_statistical_state_on_box_insert()
RETURNS TRIGGER AS $$
BEGIN
    -- New box created: total_supply +1, corresponding status supply +1
    INSERT INTO statistical_state (
        network, layer, id, total_supply,
        storing_supply, selling_supply, auctioning_supply, paid_supply,
        refunding_supply, in_secrecy_supply, published_supply, blacklisted_supply
    )
    VALUES (
        NEW.network, NEW.layer, 'statistical', 1,
        CASE WHEN NEW.status = 'Storing' THEN 1 ELSE 0 END,
        CASE WHEN NEW.status = 'Selling' THEN 1 ELSE 0 END,
        CASE WHEN NEW.status = 'Auctioning' THEN 1 ELSE 0 END,
        CASE WHEN NEW.status = 'Paid' THEN 1 ELSE 0 END,
        CASE WHEN NEW.status = 'Refunding' THEN 1 ELSE 0 END,
        CASE WHEN NEW.status = 'InSecrecy' THEN 1 ELSE 0 END,
        CASE WHEN NEW.status = 'Published' THEN 1 ELSE 0 END,
        CASE WHEN NEW.status = 'Blacklisted' THEN 1 ELSE 0 END
    )
    ON CONFLICT (network, layer, id)
    DO UPDATE SET
        total_supply = statistical_state.total_supply + 1,
        storing_supply = statistical_state.storing_supply + CASE WHEN NEW.status = 'Storing' THEN 1 ELSE 0 END,
        selling_supply = statistical_state.selling_supply + CASE WHEN NEW.status = 'Selling' THEN 1 ELSE 0 END,
        auctioning_supply = statistical_state.auctioning_supply + CASE WHEN NEW.status = 'Auctioning' THEN 1 ELSE 0 END,
        paid_supply = statistical_state.paid_supply + CASE WHEN NEW.status = 'Paid' THEN 1 ELSE 0 END,
        refunding_supply = statistical_state.refunding_supply + CASE WHEN NEW.status = 'Refunding' THEN 1 ELSE 0 END,
        in_secrecy_supply = statistical_state.in_secrecy_supply + CASE WHEN NEW.status = 'InSecrecy' THEN 1 ELSE 0 END,
        published_supply = statistical_state.published_supply + CASE WHEN NEW.status = 'Published' THEN 1 ELSE 0 END,
        blacklisted_supply = statistical_state.blacklisted_supply + CASE WHEN NEW.status = 'Blacklisted' THEN 1 ELSE 0 END;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION update_statistical_state_on_box_update()
RETURNS TRIGGER AS $$
BEGIN
    -- Only process status field change
    IF OLD.status = NEW.status THEN
        RETURN NEW;
    END IF;

    -- Update statistical: old status -1, new status +1, total_supply unchanged
    INSERT INTO statistical_state (
        network, layer, id,
        storing_supply, selling_supply, auctioning_supply, paid_supply,
        refunding_supply, in_secrecy_supply, published_supply, blacklisted_supply
    )
    VALUES (
        NEW.network, NEW.layer, 'statistical',
        CASE WHEN NEW.status = 'Storing' THEN 1 WHEN OLD.status = 'Storing' THEN -1 ELSE 0 END,
        CASE WHEN NEW.status = 'Selling' THEN 1 WHEN OLD.status = 'Selling' THEN -1 ELSE 0 END,
        CASE WHEN NEW.status = 'Auctioning' THEN 1 WHEN OLD.status = 'Auctioning' THEN -1 ELSE 0 END,
        CASE WHEN NEW.status = 'Paid' THEN 1 WHEN OLD.status = 'Paid' THEN -1 ELSE 0 END,
        CASE WHEN NEW.status = 'Refunding' THEN 1 WHEN OLD.status = 'Refunding' THEN -1 ELSE 0 END,
        CASE WHEN NEW.status = 'InSecrecy' THEN 1 WHEN OLD.status = 'InSecrecy' THEN -1 ELSE 0 END,
        CASE WHEN NEW.status = 'Published' THEN 1 WHEN OLD.status = 'Published' THEN -1 ELSE 0 END,
        CASE WHEN NEW.status = 'Blacklisted' THEN 1 WHEN OLD.status = 'Blacklisted' THEN -1 ELSE 0 END
    )
    ON CONFLICT (network, layer, id)
    DO UPDATE SET
        storing_supply = statistical_state.storing_supply + CASE WHEN NEW.status = 'Storing' THEN 1 WHEN OLD.status = 'Storing' THEN -1 ELSE 0 END,
        selling_supply = statistical_state.selling_supply + CASE WHEN NEW.status = 'Selling' THEN 1 WHEN OLD.status = 'Selling' THEN -1 ELSE 0 END,
        auctioning_supply = statistical_state.auctioning_supply + CASE WHEN NEW.status = 'Auctioning' THEN 1 WHEN OLD.status = 'Auctioning' THEN -1 ELSE 0 END,
        paid_supply = statistical_state.paid_supply + CASE WHEN NEW.status = 'Paid' THEN 1 WHEN OLD.status = 'Paid' THEN -1 ELSE 0 END,
        refunding_supply = statistical_state.refunding_supply + CASE WHEN NEW.status = 'Refunding' THEN 1 WHEN OLD.status = 'Refunding' THEN -1 ELSE 0 END,
        in_secrecy_supply = statistical_state.in_secrecy_supply + CASE WHEN NEW.status = 'InSecrecy' THEN 1 WHEN OLD.status = 'InSecrecy' THEN -1 ELSE 0 END,
        published_supply = statistical_state.published_supply + CASE WHEN NEW.status = 'Published' THEN 1 WHEN OLD.status = 'Published' THEN -1 ELSE 0 END,
        blacklisted_supply = statistical_state.blacklisted_supply + CASE WHEN NEW.status = 'Blacklisted' THEN 1 WHEN OLD.status = 'Blacklisted' THEN -1 ELSE 0 END;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_statistical_state_on_box_insert
AFTER INSERT ON boxes
FOR EACH ROW
EXECUTE FUNCTION update_statistical_state_on_box_insert();

CREATE TRIGGER trigger_update_statistical_state_on_box_update
AFTER UPDATE ON boxes
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION update_statistical_state_on_box_update();
