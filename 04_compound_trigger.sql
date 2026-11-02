-- ============================================================================
-- STAYLOGIC: Automated Hotel Room Booking & Management System
-- File: 04_compound_trigger.sql
-- Description: Automated Shield Compound Trigger on RESERVATIONS.
--              Solves the infamous Mutating Table Error (ORA-04091) cleanly
--              by decoupling row capture from statement-level conflict checks.
-- ============================================================================

CREATE OR REPLACE TRIGGER trg_shield_double_booking
FOR INSERT OR UPDATE ON RESERVATIONS
COMPOUND TRIGGER

    -- In-memory structure to capture rows being modified during this statement
    TYPE t_res_record IS RECORD (
        res_id         RESERVATIONS.reservation_id%TYPE,
        room_id        RESERVATIONS.room_id%TYPE,
        check_in_date  RESERVATIONS.check_in_date%TYPE,
        check_out_date RESERVATIONS.check_out_date%TYPE,
        booking_status RESERVATIONS.booking_status%TYPE
    );

    TYPE t_res_list IS TABLE OF t_res_record INDEX BY PLS_INTEGER;
    g_res_list t_res_list;

    -- -----------------------------------------------------------------------
    -- 1. BEFORE STATEMENT: Flush in-memory collection from previous executions
    -- -----------------------------------------------------------------------
    BEFORE STATEMENT IS
    BEGIN
        g_res_list.DELETE;
    END BEFORE STATEMENT;

    -- -----------------------------------------------------------------------
    -- 2. BEFORE EACH ROW: Enforce row-level date logic & sanitization
    -- -----------------------------------------------------------------------
    BEFORE EACH ROW IS
    BEGIN
        -- Truncate dates to remove any time component that causes subtle comparison bugs
        :NEW.check_in_date  := TRUNC(:NEW.check_in_date);
        :NEW.check_out_date := TRUNC(:NEW.check_out_date);

        -- Validate date order
        IF :NEW.check_out_date <= :NEW.check_in_date THEN
            RAISE_APPLICATION_ERROR(-20001, 
                'INVALID_DATE_RANGE: Check-out (' || TO_CHAR(:NEW.check_out_date, 'YYYY-MM-DD') || 
                ') must be strictly after Check-in (' || TO_CHAR(:NEW.check_in_date, 'YYYY-MM-DD') || ').');
        END IF;

        -- Prevent historical bookings for new reservations
        IF INSERTING AND :NEW.check_in_date < TRUNC(SYSDATE) THEN
            RAISE_APPLICATION_ERROR(-20001, 
                'INVALID_DATE_RANGE: Cannot create a booking in the past (' || TO_CHAR(:NEW.check_in_date, 'YYYY-MM-DD') || ').');
        END IF;
    END BEFORE EACH ROW;

    -- -----------------------------------------------------------------------
    -- 3. AFTER EACH ROW: Buffer target room and date ranges in PL/SQL memory
    -- -----------------------------------------------------------------------
    AFTER EACH ROW IS
        v_idx PLS_INTEGER;
    BEGIN
        -- Only buffer active reservations (skip cancelled bookings)
        IF :NEW.booking_status IN ('CONFIRMED', 'CHECKED_IN') THEN
            v_idx := g_res_list.COUNT + 1;
            g_res_list(v_idx).res_id         := :NEW.reservation_id;
            g_res_list(v_idx).room_id        := :NEW.room_id;
            g_res_list(v_idx).check_in_date  := :NEW.check_in_date;
            g_res_list(v_idx).check_out_date := :NEW.check_out_date;
            g_res_list(v_idx).booking_status := :NEW.booking_status;
        END IF;
    END AFTER EACH ROW;

    -- -----------------------------------------------------------------------
    -- 4. AFTER STATEMENT: Query RESERVATIONS table safely without ORA-04091!
    --    At AFTER STATEMENT, table RESERVATIONS is no longer mutating.
    -- -----------------------------------------------------------------------
    AFTER STATEMENT IS
        v_conflict_count NUMBER := 0;
        v_conflicting_id NUMBER := 0;
    BEGIN
        FOR i IN 1 .. g_res_list.COUNT LOOP
            BEGIN
                -- Find any overlapping active reservation for the same room
                SELECT reservation_id
                INTO v_conflicting_id
                FROM RESERVATIONS
                WHERE room_id = g_res_list(i).room_id
                  AND booking_status IN ('CONFIRMED', 'CHECKED_IN')
                  AND (g_res_list(i).res_id IS NULL OR reservation_id != g_res_list(i).res_id)
                  AND check_in_date < g_res_list(i).check_out_date
                  AND check_out_date > g_res_list(i).check_in_date
                  AND ROWNUM = 1;

                -- If a record is found, raise exception and abort transaction
                RAISE_APPLICATION_ERROR(-20002, 
                    'ROOM_UNAVAILABLE [SHIELD TRIGGER]: Room #' || g_res_list(i).room_id || 
                    ' is already booked by Reservation #' || v_conflicting_id || 
                    ' during the requested window (' || TO_CHAR(g_res_list(i).check_in_date, 'YYYY-MM-DD') || 
                    ' to ' || TO_CHAR(g_res_list(i).check_out_date, 'YYYY-MM-DD') || '). Double-booking blocked.');

            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    -- Safe! No conflict exists for this room during this window
                    NULL;
            END;
        END LOOP;

        -- Clean up memory
        g_res_list.DELETE;
    END AFTER STATEMENT;

END trg_shield_double_booking;
/
SHOW ERRORS;
