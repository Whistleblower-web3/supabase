
-- ============================================
-- 4. Trigger functions for statistical state
-- ============================================

-- ============================================
-- Trigger function: update statistical_state table (INSERT)
-- ============================================
-- Listen to: boxes table INSERT -> BoxCreated
CREATE OR REPLACE FUNCTION update_statistical_state_on_box_insert()
RETURNS TRIGGER AS $$
BEGIN
    -- New box created: total_supply +1, corresponding status supply +1
    INSERT INTO statistical_state (
        network, layer, id, total_supply,
        status_0_supply, status_1_supply, status_2_supply, status_3_supply,
        status_4_supply, status_5_supply, status_6_supply, status_7_supply
    )
    VALUES (
        NEW.network, NEW.layer, 'statistical', 1,
        CASE WHEN NEW.status = 0 THEN 1 ELSE 0 END,
        CASE WHEN NEW.status = 1 THEN 1 ELSE 0 END,
        CASE WHEN NEW.status = 2 THEN 1 ELSE 0 END,
        CASE WHEN NEW.status = 3 THEN 1 ELSE 0 END,
        CASE WHEN NEW.status = 4 THEN 1 ELSE 0 END,
        CASE WHEN NEW.status = 5 THEN 1 ELSE 0 END,
        CASE WHEN NEW.status = 6 THEN 1 ELSE 0 END,
        CASE WHEN NEW.status = 7 THEN 1 ELSE 0 END
    )
    ON CONFLICT (network, layer, id)
    DO UPDATE SET
        total_supply = statistical_state.total_supply + 1,
        status_0_supply = statistical_state.status_0_supply + CASE WHEN NEW.status = 0 THEN 1 ELSE 0 END,
        status_1_supply = statistical_state.status_1_supply + CASE WHEN NEW.status = 1 THEN 1 ELSE 0 END,
        status_2_supply = statistical_state.status_2_supply + CASE WHEN NEW.status = 2 THEN 1 ELSE 0 END,
        status_3_supply = statistical_state.status_3_supply + CASE WHEN NEW.status = 3 THEN 1 ELSE 0 END,
        status_4_supply = statistical_state.status_4_supply + CASE WHEN NEW.status = 4 THEN 1 ELSE 0 END,
        status_5_supply = statistical_state.status_5_supply + CASE WHEN NEW.status = 5 THEN 1 ELSE 0 END,
        status_6_supply = statistical_state.status_6_supply + CASE WHEN NEW.status = 6 THEN 1 ELSE 0 END,
        status_7_supply = statistical_state.status_7_supply + CASE WHEN NEW.status = 7 THEN 1 ELSE 0 END;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_statistical_state_on_box_insert
AFTER INSERT ON boxes
FOR EACH ROW
EXECUTE FUNCTION update_statistical_state_on_box_insert();


-- ============================================
-- Trigger function: update statistical_state table (UPDATE)
-- ============================================
-- Listen to: boxes table UPDATE status -> BoxStatusChanged
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
        status_0_supply, status_1_supply, status_2_supply, status_3_supply,
        status_4_supply, status_5_supply, status_6_supply, status_7_supply
    )
    VALUES (
        NEW.network, NEW.layer, 'statistical',
        CASE WHEN NEW.status = 0 THEN 1 WHEN OLD.status = 0 THEN -1 ELSE 0 END,
        CASE WHEN NEW.status = 1 THEN 1 WHEN OLD.status = 1 THEN -1 ELSE 0 END,
        CASE WHEN NEW.status = 2 THEN 1 WHEN OLD.status = 2 THEN -1 ELSE 0 END,
        CASE WHEN NEW.status = 3 THEN 1 WHEN OLD.status = 3 THEN -1 ELSE 0 END,
        CASE WHEN NEW.status = 4 THEN 1 WHEN OLD.status = 4 THEN -1 ELSE 0 END,
        CASE WHEN NEW.status = 5 THEN 1 WHEN OLD.status = 5 THEN -1 ELSE 0 END,
        CASE WHEN NEW.status = 6 THEN 1 WHEN OLD.status = 6 THEN -1 ELSE 0 END,
        CASE WHEN NEW.status = 7 THEN 1 WHEN OLD.status = 7 THEN -1 ELSE 0 END
    )
    ON CONFLICT (network, layer, id)
    DO UPDATE SET
        status_0_supply = statistical_state.status_0_supply + CASE WHEN NEW.status = 0 THEN 1 WHEN OLD.status = 0 THEN -1 ELSE 0 END,
        status_1_supply = statistical_state.status_1_supply + CASE WHEN NEW.status = 1 THEN 1 WHEN OLD.status = 1 THEN -1 ELSE 0 END,
        status_2_supply = statistical_state.status_2_supply + CASE WHEN NEW.status = 2 THEN 1 WHEN OLD.status = 2 THEN -1 ELSE 0 END,
        status_3_supply = statistical_state.status_3_supply + CASE WHEN NEW.status = 3 THEN 1 WHEN OLD.status = 3 THEN -1 ELSE 0 END,
        status_4_supply = statistical_state.status_4_supply + CASE WHEN NEW.status = 4 THEN 1 WHEN OLD.status = 4 THEN -1 ELSE 0 END,
        status_5_supply = statistical_state.status_5_supply + CASE WHEN NEW.status = 5 THEN 1 WHEN OLD.status = 5 THEN -1 ELSE 0 END,
        status_6_supply = statistical_state.status_6_supply + CASE WHEN NEW.status = 6 THEN 1 WHEN OLD.status = 6 THEN -1 ELSE 0 END,
        status_7_supply = statistical_state.status_7_supply + CASE WHEN NEW.status = 7 THEN 1 WHEN OLD.status = 7 THEN -1 ELSE 0 END;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_statistical_state_on_box_update
AFTER UPDATE ON boxes
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION update_statistical_state_on_box_update();
