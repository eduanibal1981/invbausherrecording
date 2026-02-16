-- =============================================
-- Hall Schedule Configuration Table
-- Easy to manage monthly/yearly hall-day-shift configs
-- =============================================

CREATE TABLE IF NOT EXISTS hall_schedule_config (
    id SERIAL PRIMARY KEY,
    hallname TEXT NOT NULL,                    -- 'HALL 1', 'HALL 2', etc.
    day_name TEXT NOT NULL,                    -- 'Sunday', 'Monday', etc.
    shift_name TEXT NOT NULL,                  -- 'AM', 'PM', 'LPM', 'NIGHT'
    is_active BOOLEAN DEFAULT TRUE,            -- Enable/disable without deleting
    effective_from DATE DEFAULT CURRENT_DATE,  -- When this config starts
    effective_to DATE DEFAULT NULL,            -- NULL = ongoing, or set end date
    notes TEXT,                                -- Optional notes
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Unique constraint per hall-day-shift
    CONSTRAINT unique_hall_day_shift UNIQUE (hallname, day_name, shift_name, effective_from)
);

-- Create index for faster lookups
CREATE INDEX idx_hall_schedule_active ON hall_schedule_config(hallname, is_active) WHERE is_active = TRUE;

-- Add trigger to auto-update updated_at
CREATE OR REPLACE FUNCTION update_hall_schedule_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_hall_schedule_updated
    BEFORE UPDATE ON hall_schedule_config
    FOR EACH ROW
    EXECUTE FUNCTION update_hall_schedule_timestamp();

-- =============================================
-- Insert Initial Configuration Data
-- Based on user's requirements
-- =============================================

-- HALL 1 & HALL 5: Sunday & Monday
INSERT INTO hall_schedule_config (hallname, day_name, shift_name) VALUES
('HALL 1', 'Sunday', 'AM'), ('HALL 1', 'Sunday', 'PM'), ('HALL 1', 'Sunday', 'LPM'),
('HALL 1', 'Monday', 'AM'), ('HALL 1', 'Monday', 'PM'), ('HALL 1', 'Monday', 'LPM'),
('HALL 5', 'Sunday', 'AM'), ('HALL 5', 'Sunday', 'PM'), ('HALL 5', 'Sunday', 'LPM'),
('HALL 5', 'Monday', 'AM'), ('HALL 5', 'Monday', 'PM'), ('HALL 5', 'Monday', 'LPM');

-- HALL 2 & HALL 7: Tuesday & Wednesday
INSERT INTO hall_schedule_config (hallname, day_name, shift_name) VALUES
('HALL 2', 'Tuesday', 'AM'), ('HALL 2', 'Tuesday', 'PM'), ('HALL 2', 'Tuesday', 'LPM'),
('HALL 2', 'Wednesday', 'AM'), ('HALL 2', 'Wednesday', 'PM'), ('HALL 2', 'Wednesday', 'LPM'),
('HALL 7', 'Tuesday', 'AM'), ('HALL 7', 'Tuesday', 'PM'), ('HALL 7', 'Tuesday', 'LPM'),
('HALL 7', 'Wednesday', 'AM'), ('HALL 7', 'Wednesday', 'PM'), ('HALL 7', 'Wednesday', 'LPM');

-- HALL 3: Monday & Thursday
INSERT INTO hall_schedule_config (hallname, day_name, shift_name) VALUES
('HALL 3', 'Monday', 'AM'), ('HALL 3', 'Monday', 'PM'), ('HALL 3', 'Monday', 'LPM'),
('HALL 3', 'Thursday', 'AM'), ('HALL 3', 'Thursday', 'PM'), ('HALL 3', 'Thursday', 'LPM');

-- HALL 4: Sunday & Wednesday
INSERT INTO hall_schedule_config (hallname, day_name, shift_name) VALUES
('HALL 4', 'Sunday', 'AM'), ('HALL 4', 'Sunday', 'PM'), ('HALL 4', 'Sunday', 'LPM'), ('HALL 4', 'Sunday', 'NIGHT'),
('HALL 4', 'Wednesday', 'AM'), ('HALL 4', 'Wednesday', 'PM'), ('HALL 4', 'Wednesday', 'LPM'), ('HALL 4', 'Wednesday', 'NIGHT');

-- HALL 6: Wednesday only
INSERT INTO hall_schedule_config (hallname, day_name, shift_name) VALUES
('HALL 6', 'Wednesday', 'AM'), ('HALL 6', 'Wednesday', 'PM'), ('HALL 6', 'Wednesday', 'LPM');

-- Also add Saturday schedules (based on groupsofpatients existing data)
INSERT INTO hall_schedule_config (hallname, day_name, shift_name) VALUES
('HALL 1', 'Saturday', 'AM'), ('HALL 1', 'Saturday', 'PM'), ('HALL 1', 'Saturday', 'LPM'),
('HALL 2', 'Saturday', 'AM'), ('HALL 2', 'Saturday', 'PM'), ('HALL 2', 'Saturday', 'LPM'),
('HALL 3', 'Saturday', 'AM'), ('HALL 3', 'Saturday', 'PM'), ('HALL 3', 'Saturday', 'LPM'),
('HALL 4', 'Saturday', 'AM'), ('HALL 4', 'Saturday', 'PM'), ('HALL 4', 'Saturday', 'LPM'), ('HALL 4', 'Saturday', 'NIGHT'),
('HALL 5', 'Saturday', 'AM'), ('HALL 5', 'Saturday', 'PM'), ('HALL 5', 'Saturday', 'LPM'),
('HALL 6', 'Saturday', 'AM'), ('HALL 6', 'Saturday', 'PM'),
('HALL 7', 'Saturday', 'AM'), ('HALL 7', 'Saturday', 'PM'), ('HALL 7', 'Saturday', 'LPM');

COMMENT ON TABLE hall_schedule_config IS 'Configurable hall-day-shift schedule. Change is_active or set effective_to date to modify without deleting records.';;
