-- WikiTruth Supabase 数据库迁移文件
-- 06_triggers.sql - 创建自动更新聚合表的触发器
-- 
-- 说明：
-- 应用端会提取事件参数数据并写入业务表，触发器监听业务表的变化
-- 使用数据库触发器实现"新旧数据相加"的逻辑

-- 注意：box_rewards 中的 Total 类型是直接累加的，不需要计算Minter+Seller+Completer的奖励
-- 因为合约中已经计算了 Total，rewards_addeds 表中会包含 Total 类型的记录
-- 触发器 update_box_rewards_on_rewards_added 会自动累加所有类型（包括 Total）的奖励

-- ============================================
-- 触发器函数：更新 box_rewards 表（累加奖励）
-- ============================================
-- 监听：rewards_addeds 表 INSERT
-- 当 RewardAmountAdded 事件插入时，累加到 box_rewards 表
-- 根据box_id、reward_type、token累加amount
CREATE OR REPLACE FUNCTION update_box_rewards_on_rewards_added()
RETURNS TRIGGER AS $$
DECLARE
    v_reward_id TEXT;
BEGIN
    -- 累加奖励到 box_rewards 表
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

-- 创建触发器
CREATE TRIGGER trigger_update_box_rewards_on_rewards_added
AFTER INSERT ON rewards_addeds
FOR EACH ROW
EXECUTE FUNCTION update_box_rewards_on_rewards_added();


-- ============================================
-- 触发器函数：更新 user_withdraws 表 （累加提取金额）
-- ============================================
-- 监听：withdraws 表 INSERT
-- 只处理 Helper 和 Minter 类型的提取
CREATE OR REPLACE FUNCTION update_user_withdraws_on_withdraw()
RETURNS TRIGGER AS $$
DECLARE
    v_id TEXT;
BEGIN
    -- 只处理 Helper 和 Minter 类型的提取
    IF NEW.withdraw_type NOT IN ('Helper', 'Minter') THEN
        RETURN NEW;
    END IF;

    -- 更新 user_withdraws 表（累加）
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

-- 创建触发器
CREATE TRIGGER trigger_update_user_withdraws_on_withdraw
AFTER INSERT ON withdraws
FOR EACH ROW
WHEN (NEW.withdraw_type IN ('Helper', 'Minter'))
EXECUTE FUNCTION update_user_withdraws_on_withdraw();

-- ============================================
-- 触发器函数：更新 user_rewards 表（奖励添加）
-- ============================================
-- 监听：rewards_addeds 表 INSERT
-- 需要根据 boxId 查找 minter_id/seller_id/completer_id
-- 然后根据minter_id/seller_id/completer_id累加amount
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
    -- 只处理 Minter、Seller、Completer 类型的奖励
    IF NEW.reward_type NOT IN ('Minter', 'Seller', 'Completer') THEN
        RETURN NEW;
    END IF;

    -- 获取 box 的用户信息
    SELECT minter_id, seller_id, completer_id
    INTO v_minter_id, v_seller_id, v_completer_id
    FROM boxes
    WHERE network = NEW.network 
        AND layer = NEW.layer 
        AND id = NEW.box_id;

    -- 计算金额变化量
    IF TG_OP = 'INSERT' THEN
        v_amount_change := NEW.amount;
    ELSE
        v_amount_change := NEW.amount - COALESCE(OLD.amount, 0);
    END IF;

    -- 根据奖励类型确定用户
    v_user_id := CASE NEW.reward_type
        WHEN 'Minter' THEN v_minter_id
        WHEN 'Seller' THEN v_seller_id
        WHEN 'Completer' THEN v_completer_id
        ELSE NULL
    END;

    -- 如果用户 ID 为空，跳过
    IF v_user_id IS NULL OR v_user_id = '' THEN
        RETURN NEW;
    END IF;

    -- 更新用户奖励（Minter/Seller/Completer）
    -- 注意：user_rewards 中不包含 Total 类型，只记录分配给具体角色的奖励
    v_user_reward_id := v_user_id::BIGINT::TEXT || '-' || NEW.reward_type || '-' || NEW.token;
    INSERT INTO user_rewards (
        network, layer, id, user_id, reward_type, token, amount
    )
    VALUES (
        NEW.network, NEW.layer, v_user_reward_id, v_user_id::BIGINT, NEW.reward_type, NEW.token, 
        GREATEST(0, COALESCE((SELECT amount FROM user_rewards WHERE network = NEW.network AND layer = NEW.layer AND user_id = v_user_id::BIGINT AND reward_type = NEW.reward_type AND token = NEW.token), 0) + v_amount_change)
    )
    ON CONFLICT (network, layer, user_id, reward_type, token)
    DO UPDATE SET
        amount = GREATEST(0, user_rewards.amount + v_amount_change);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 创建触发器
CREATE TRIGGER trigger_update_user_rewards_on_rewards_added
AFTER INSERT OR UPDATE ON box_rewards
FOR EACH ROW
WHEN (NEW.reward_type IN ('Minter', 'Seller', 'Completer'))
EXECUTE FUNCTION update_user_rewards_on_rewards_added();


-- ============================================
-- 触发器函数：更新 box_user_order_amounts 表（支付）
-- ============================================
-- 监听：payments 表 INSERT
-- 所有支付都累加到 box_user_order_amounts
CREATE OR REPLACE FUNCTION update_box_user_order_amounts_on_payment()
RETURNS TRIGGER AS $$
DECLARE
    v_fund_id TEXT;
BEGIN
    -- 累加支付金额到 box_user_order_amounts
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

-- 创建触发器
CREATE TRIGGER trigger_update_box_user_order_amounts_on_payment
AFTER INSERT ON payments
FOR EACH ROW
EXECUTE FUNCTION update_box_user_order_amounts_on_payment();

-- ============================================
-- 触发器函数：更新 box_user_order_amounts 表（提取）
-- ============================================
-- 监听：withdraws 表 INSERT
-- withdraw_type: 'Order' 或 'Refund' -> 清零对应box、user的order资金（合约中 withdraw 是提取全部资金）
CREATE OR REPLACE FUNCTION update_box_user_order_amounts_on_withdraw()
RETURNS TRIGGER AS $$
DECLARE
    v_box_id BIGINT;
    v_user_id BIGINT;
BEGIN
    -- 只处理 Order 和 Refund 类型的提取
    IF NEW.withdraw_type NOT IN ('Order', 'Refund') THEN
        RETURN NEW;
    END IF;

    -- user_id 在 withdraws 表中是 BIGINT，直接使用
    v_user_id := NEW.user_id;

    -- 如果 box_list 为空，跳过
    IF NEW.box_list IS NULL OR array_length(NEW.box_list, 1) = 0 THEN
        RETURN NEW;
    END IF;

    -- 遍历 box_list，清零每个 box 的资金（合约中 withdraw 是提取全部资金）
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

-- 创建触发器
CREATE TRIGGER trigger_update_box_user_order_amounts_on_withdraw
AFTER INSERT ON withdraws
FOR EACH ROW
WHEN (NEW.withdraw_type IN ('Order', 'Refund'))
EXECUTE FUNCTION update_box_user_order_amounts_on_withdraw();

-- ============================================
-- 触发器函数：更新 box_user_order_amounts 表（清零buyer的资金）
-- ============================================
-- 监听：rewards_addeds 表 INSERT（只处理Seller/Completer 类型），
CREATE OR REPLACE FUNCTION update_box_user_order_amounts_on_rewards_added()
RETURNS TRIGGER AS $$
DECLARE
    v_buyer_id TEXT;
BEGIN
    -- 只处理 Seller、Completer 类型的奖励（Total 类型不处理）
    IF NEW.reward_type NOT IN ('Seller', 'Completer') THEN
        RETURN NEW;
    END IF;

    -- 只处理新增奖励的情况（INSERT）或金额增加的情况（UPDATE）
    IF TG_OP = 'UPDATE' AND NEW.amount <= COALESCE(OLD.amount, 0) THEN
        RETURN NEW;
    END IF;

    -- 获取 box 的 buyer_id
    SELECT buyer_id
    INTO v_buyer_id
    FROM boxes
    WHERE network = NEW.network 
        AND layer = NEW.layer 
        AND id = NEW.box_id;

    -- 如果 buyer_id 为空，跳过
    IF v_buyer_id IS NULL OR v_buyer_id = '' THEN
        RETURN NEW;
    END IF;

    -- 清零 buyer 在该 box 该 token 的 order 资金
    -- buyer_id 在 boxes 表中是 TEXT，需要转换为 BIGINT 以匹配 box_user_order_amounts.user_id
    UPDATE box_user_order_amounts
    SET amount = 0
    WHERE network = NEW.network
        AND layer = NEW.layer
        AND user_id = v_buyer_id::BIGINT
        AND box_id = NEW.box_id
        AND token = NEW.token;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 创建触发器
CREATE TRIGGER trigger_update_box_user_order_amounts_on_rewards_added
AFTER INSERT OR UPDATE ON box_rewards
FOR EACH ROW
WHEN (NEW.reward_type IN ('Seller', 'Completer'))
EXECUTE FUNCTION update_box_user_order_amounts_on_rewards_added();

-- ============================================
-- 触发器函数：更新 token_total_amounts 表（支付）
-- ============================================
-- 监听：payments 表 INSERT -> OrderPaid
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

-- 创建触发器
CREATE TRIGGER trigger_update_token_total_amounts_on_payment
AFTER INSERT ON payments
FOR EACH ROW
EXECUTE FUNCTION update_token_total_amounts_on_payment();


-- ============================================
-- 触发器函数：更新 token_total_amounts 表（RewardsAdded-Total）
-- ============================================
-- 监听：rewards_addeds 表 INSERT
-- 当 Total 类型的奖励添加时，更新 RewardsAdded 类型的 token_total_amounts
-- 注意：直接监听 rewards_addeds 表，因为只需要 Total 类型
CREATE OR REPLACE FUNCTION update_token_total_amounts_on_rewards_added()
RETURNS TRIGGER AS $$
DECLARE
    v_id TEXT;
    v_amount_change NUMERIC(78, 0);
BEGIN
    -- 只处理 Total 类型的奖励
    IF NEW.reward_type != 'Total' THEN
        RETURN NEW;
    END IF;

    -- 计算金额变化量
    IF TG_OP = 'INSERT' THEN
        v_amount_change := NEW.amount;
    ELSE
        v_amount_change := NEW.amount - COALESCE(OLD.amount, 0);
    END IF;

    -- 如果金额没有变化，跳过
    IF v_amount_change = 0 THEN
        RETURN NEW;
    END IF;

    -- 更新 token_total_amounts 表
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

-- 创建触发器
CREATE TRIGGER trigger_update_token_total_amounts_on_rewards_added
AFTER INSERT ON rewards_addeds
FOR EACH ROW
EXECUTE FUNCTION update_token_total_amounts_on_rewards_added();


-- ============================================
-- 触发器函数：更新 token_total_amounts 表（提取）
-- ============================================
-- 监听：withdraws 表 INSERT -> 依据withdraw_type更新token_total_amounts的funds_type
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
-- 触发器函数：更新 statistical_state 表
-- ============================================
-- 监听：boxes 表 INSERT -> BoxCreated
-- 监听：boxes 表 UPDATE status -> BoxStatusChanged
CREATE OR REPLACE FUNCTION update_statistical_state_on_box_insert()
RETURNS TRIGGER AS $$
BEGIN
    -- 新 box 创建：total_supply +1，对应状态的 supply +1
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
    -- 只处理 status 字段的变化
    IF OLD.status = NEW.status THEN
        RETURN NEW;
    END IF;

    -- 更新统计：旧状态-1，新状态+1，total_supply 不变
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

-- 创建触发器
CREATE TRIGGER trigger_update_statistical_state_on_box_insert
AFTER INSERT ON boxes
FOR EACH ROW
EXECUTE FUNCTION update_statistical_state_on_box_insert();

CREATE TRIGGER trigger_update_statistical_state_on_box_update
AFTER UPDATE ON boxes
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION update_statistical_state_on_box_update();
