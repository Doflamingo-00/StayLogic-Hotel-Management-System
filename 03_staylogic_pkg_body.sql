-- ============================================================================
-- STAYLOGIC: Automated Hotel Room Booking & Management System
-- File: 03_staylogic_pkg_body.sql
-- Description: Package Body implementing business logic, parameterized cursors,
--              dynamic billing calculations, exception handling, and reporting.
-- ============================================================================

CREATE OR REPLACE PACKAGE BODY staylogic_pkg AS

    -- -----------------------------------------------------------------------
    -- Private Helper: Format currency string
    -- -----------------------------------------------------------------------
    FUNCTION format_curr(p_amount NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN '$' || TO_CHAR(p_amount, 'FM999,990.00');
    END format_curr;

    -- -----------------------------------------------------------------------
    -- Function: is_room_available
    -- Implements robust date overlap check:
    -- An overlap occurs IF AND ONLY IF:
    --   (existing.check_in_date < p_check_out) AND (existing.check_out_date > p_check_in)
    -- -----------------------------------------------------------------------
    FUNCTION is_room_available(
        p_room_id       IN NUMBER,
        p_check_in      IN DATE,
        p_check_out     IN DATE,
        p_ignore_res_id IN NUMBER DEFAULT NULL
    ) RETURN BOOLEAN IS
        v_conflict_count NUMBER := 0;
        v_room_status    ROOMS.status%TYPE;
    BEGIN
        -- 1. Check if room exists and is not under maintenance
        BEGIN
            SELECT status INTO v_room_status
            FROM ROOMS
            WHERE room_id = p_room_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RETURN FALSE;
        END;

        IF v_room_status != 'AVAILABLE' THEN
            RETURN FALSE;
        END IF;

        -- 2. Check for overlapping active reservations
        SELECT COUNT(*)
        INTO v_conflict_count
        FROM RESERVATIONS
        WHERE room_id = p_room_id
          AND booking_status IN ('CONFIRMED', 'CHECKED_IN')
          AND check_in_date < p_check_out
          AND check_out_date > p_check_in
          AND (p_ignore_res_id IS NULL OR reservation_id != p_ignore_res_id);

        RETURN (v_conflict_count = 0);
    END is_room_available;

    -- -----------------------------------------------------------------------
    -- Procedure: find_available_rooms
    -- Explicit Parameterized Cursor demonstrating cursor FOR loop & dynamic filtering
    -- -----------------------------------------------------------------------
    PROCEDURE find_available_rooms(
        p_check_in   IN DATE,
        p_check_out  IN DATE,
        p_room_type  IN VARCHAR2 DEFAULT NULL
    ) IS
        -- Parameterized Cursor: selects rooms without overlapping reservations
        CURSOR c_rooms(cp_in DATE, cp_out DATE, cp_type VARCHAR2) IS
            SELECT r.room_id, r.room_number, r.room_type, r.price_per_night, r.floor_number
            FROM ROOMS r
            WHERE r.status = 'AVAILABLE'
              AND (cp_type IS NULL OR UPPER(r.room_type) = UPPER(cp_type))
              AND NOT EXISTS (
                  SELECT 1
                  FROM RESERVATIONS res
                  WHERE res.room_id = r.room_id
                    AND res.booking_status IN ('CONFIRMED', 'CHECKED_IN')
                    AND res.check_in_date < cp_out
                    AND res.check_out_date > cp_in
              )
            ORDER BY r.price_per_night ASC, r.room_number ASC;

        v_found_count NUMBER := 0;
    BEGIN
        IF p_check_in IS NULL OR p_check_out IS NULL OR p_check_out <= p_check_in THEN
            RAISE_APPLICATION_ERROR(-20001, 'INVALID_DATE_RANGE: Check-out date must be strictly after check-in date.');
        END IF;

        DBMS_OUTPUT.PUT_LINE('========================================================================================');
        DBMS_OUTPUT.PUT_LINE(' STAYLOGIC: AVAILABLE ROOMS SEARCH RESULTS');
        DBMS_OUTPUT.PUT_LINE(' Window: ' || TO_CHAR(p_check_in, 'YYYY-MM-DD') || ' to ' || TO_CHAR(p_check_out, 'YYYY-MM-DD') ||
                             ' | Category Filter: ' || NVL(UPPER(p_room_type), 'ALL TIERS'));
        DBMS_OUTPUT.PUT_LINE('========================================================================================');
        DBMS_OUTPUT.PUT_LINE(RPAD('ROOM ID', 10) || RPAD('ROOM NO', 12) || RPAD('TIER', 16) || RPAD('PRICE/NIGHT', 16) || RPAD('FLOOR', 8));
        DBMS_OUTPUT.PUT_LINE('----------------------------------------------------------------------------------------');

        FOR rec IN c_rooms(p_check_in, p_check_out, p_room_type) LOOP
            v_found_count := v_found_count + 1;
            DBMS_OUTPUT.PUT_LINE(
                RPAD(rec.room_id, 10) ||
                RPAD(rec.room_number, 12) ||
                RPAD(rec.room_type, 16) ||
                RPAD(format_curr(rec.price_per_night), 16) ||
                RPAD(rec.floor_number, 8)
            );
        END LOOP;

        IF v_found_count = 0 THEN
            DBMS_OUTPUT.PUT_LINE(' [!] No rooms currently available matching the requested dates and category.');
        ELSE
            DBMS_OUTPUT.PUT_LINE('----------------------------------------------------------------------------------------');
            DBMS_OUTPUT.PUT_LINE(' Total Available Rooms Found: ' || v_found_count);
        END IF;
        DBMS_OUTPUT.PUT_LINE('========================================================================================');
    END find_available_rooms;

    -- -----------------------------------------------------------------------
    -- Procedure: book_room
    -- Safe transactional entry point for booking with defensive validations
    -- -----------------------------------------------------------------------
    PROCEDURE book_room(
        p_guest_id         IN NUMBER,
        p_room_id          IN NUMBER,
        p_check_in         IN DATE,
        p_check_out        IN DATE,
        p_special_requests IN VARCHAR2 DEFAULT NULL,
        o_reservation_id   OUT NUMBER
    ) IS
        v_guest_count NUMBER := 0;
        v_room_count  NUMBER := 0;
    BEGIN
        -- 1. Date Validation
        IF p_check_in IS NULL OR p_check_out IS NULL THEN
            RAISE_APPLICATION_ERROR(-20001, 'INVALID_DATE_RANGE: Check-in and check-out dates cannot be null.');
        END IF;

        IF TRUNC(p_check_in) < TRUNC(SYSDATE) THEN
            RAISE_APPLICATION_ERROR(-20001, 'INVALID_DATE_RANGE: Check-in date cannot be in the past (' || TO_CHAR(p_check_in, 'YYYY-MM-DD') || ').');
        END IF;

        IF TRUNC(p_check_out) <= TRUNC(p_check_in) THEN
            RAISE_APPLICATION_ERROR(-20001, 'INVALID_DATE_RANGE: Check-out (' || TO_CHAR(p_check_out, 'YYYY-MM-DD') || 
                                           ') must be strictly greater than check-in (' || TO_CHAR(p_check_in, 'YYYY-MM-DD') || ').');
        END IF;

        -- 2. Verify Foreign Key Entities exist
        SELECT COUNT(*) INTO v_guest_count FROM GUESTS WHERE guest_id = p_guest_id;
        IF v_guest_count = 0 THEN
            RAISE_APPLICATION_ERROR(-20003, 'GUEST_NOT_FOUND: Guest ID ' || p_guest_id || ' does not exist.');
        END IF;

        SELECT COUNT(*) INTO v_room_count FROM ROOMS WHERE room_id = p_room_id;
        IF v_room_count = 0 THEN
            RAISE_APPLICATION_ERROR(-20002, 'ROOM_NOT_FOUND: Room ID ' || p_room_id || ' does not exist.');
        END IF;

        -- 3. Room Availability Check
        IF NOT is_room_available(p_room_id, p_check_in, p_check_out) THEN
            RAISE_APPLICATION_ERROR(-20002, 'ROOM_UNAVAILABLE: Room ' || p_room_id || 
                                           ' is already reserved during ' || TO_CHAR(p_check_in, 'YYYY-MM-DD') || 
                                           ' to ' || TO_CHAR(p_check_out, 'YYYY-MM-DD') || '.');
        END IF;

        -- 4. Insert Reservation
        INSERT INTO RESERVATIONS (
            room_id, guest_id, check_in_date, check_out_date, booking_status, special_requests
        ) VALUES (
            p_room_id, p_guest_id, TRUNC(p_check_in), TRUNC(p_check_out), 'CONFIRMED', p_special_requests
        ) RETURNING reservation_id INTO o_reservation_id;

        DBMS_OUTPUT.PUT_LINE('[SUCCESS] Reservation confirmed! Booking ID: #' || o_reservation_id ||
                             ' for Guest #' || p_guest_id || ' in Room #' || p_room_id);
    END book_room;

    -- -----------------------------------------------------------------------
    -- Function: calculate_invoice
    -- Dynamic pricing engine: applies nights calculation, seasonal rate spikes,
    -- promo vouchers, and tax assessment.
    -- -----------------------------------------------------------------------
    FUNCTION calculate_invoice(
        p_reservation_id IN NUMBER,
        p_discount_code  IN VARCHAR2 DEFAULT NULL,
        p_persist_bill   IN BOOLEAN DEFAULT FALSE
    ) RETURN NUMBER IS
        v_check_in       DATE;
        v_check_out      DATE;
        v_price_per_night NUMBER(10, 2);
        v_nights         NUMBER;
        v_subtotal       NUMBER(10, 2);
        v_surge_pct      NUMBER(5, 2) := 0.00;
        v_surge_amount   NUMBER(10, 2) := 0.00;
        v_disc_pct       NUMBER(5, 2) := 0.00;
        v_disc_amount    NUMBER(10, 2) := 0.00;
        v_taxable_amount NUMBER(10, 2);
        v_tax_amount     NUMBER(10, 2);
        v_total_amount   NUMBER(10, 2);
        v_month_num      VARCHAR2(2);
    BEGIN
        -- 1. Fetch reservation & room rate
        BEGIN
            SELECT res.check_in_date, res.check_out_date, rm.price_per_night
            INTO v_check_in, v_check_out, v_price_per_night
            FROM RESERVATIONS res
            JOIN ROOMS rm ON res.room_id = rm.room_id
            WHERE res.reservation_id = p_reservation_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20003, 'RESERVATION_NOT_FOUND: Reservation ID #' || p_reservation_id || ' does not exist.');
        END;

        -- 2. Calculate Nights and Base Subtotal
        v_nights := TRUNC(v_check_out) - TRUNC(v_check_in);
        IF v_nights <= 0 THEN
            v_nights := 1;
        END IF;
        v_subtotal := ROUND(v_nights * v_price_per_night, 2);

        -- 3. Dynamic Seasonal Surge Evaluation
        -- June (06), July (07) (Summer Vacations) and December (12) (Winter Holidays) incur 20% surge
        v_month_num := TO_CHAR(v_check_in, 'MM');
        IF v_month_num IN ('06', '07', '12') THEN
            v_surge_pct := c_peak_season_surge;
            v_surge_amount := ROUND(v_subtotal * v_surge_pct, 2);
        END IF;

        -- 4. Promotional Voucher Evaluation
        IF p_discount_code IS NOT NULL THEN
            CASE UPPER(TRIM(p_discount_code))
                WHEN 'SUMMER10'    THEN v_disc_pct := 0.10;
                WHEN 'EARLYBIRD15' THEN v_disc_pct := 0.15;
                WHEN 'VIP20'       THEN v_disc_pct := 0.20;
                WHEN 'STAYLOGIC5'  THEN v_disc_pct := 0.05;
                ELSE v_disc_pct := 0.00;
            END CASE;
            v_disc_amount := ROUND((v_subtotal + v_surge_amount) * v_disc_pct, 2);
        END IF;

        -- 5. Standard Tax Calculation (12% standard)
        v_taxable_amount := (v_subtotal + v_surge_amount) - v_disc_amount;
        v_tax_amount := ROUND(v_taxable_amount * c_standard_tax_rate, 2);
        v_total_amount := v_taxable_amount + v_tax_amount;

        -- 6. Optional Persistence into BILLING Table
        IF p_persist_bill THEN
            MERGE INTO BILLING b
            USING (SELECT p_reservation_id AS res_id FROM dual) s
            ON (b.reservation_id = s.res_id)
            WHEN MATCHED THEN
                UPDATE SET
                    total_nights    = v_nights,
                    base_rate       = v_price_per_night,
                    subtotal        = v_subtotal,
                    seasonal_surge  = v_surge_amount,
                    discount_amount = v_disc_amount,
                    tax_amount      = v_tax_amount,
                    total_amount    = v_total_amount,
                    bill_date       = SYSDATE
            WHEN NOT MATCHED THEN
                INSERT (
                    reservation_id, total_nights, base_rate, subtotal,
                    seasonal_surge, discount_amount, tax_amount, total_amount, payment_status
                ) VALUES (
                    p_reservation_id, v_nights, v_price_per_night, v_subtotal,
                    v_surge_amount, v_disc_amount, v_tax_amount, v_total_amount, 'PENDING'
                );
        END IF;

        RETURN v_total_amount;
    END calculate_invoice;

    -- -----------------------------------------------------------------------
    -- Procedure: print_invoice
    -- Formats and prints an itemized ASCII guest folio
    -- -----------------------------------------------------------------------
    PROCEDURE print_invoice(
        p_reservation_id IN NUMBER,
        p_discount_code  IN VARCHAR2 DEFAULT NULL
    ) IS
        v_guest_name     VARCHAR2(120);
        v_guest_email    VARCHAR2(100);
        v_room_number    VARCHAR2(10);
        v_room_type      VARCHAR2(20);
        v_price_per_night NUMBER(10, 2);
        v_check_in       DATE;
        v_check_out      DATE;
        v_status         VARCHAR2(20);
        v_nights         NUMBER;
        v_subtotal       NUMBER(10, 2);
        v_surge_amount   NUMBER(10, 2) := 0.00;
        v_surge_pct      VARCHAR2(10)  := '0%';
        v_disc_amount    NUMBER(10, 2) := 0.00;
        v_disc_label     VARCHAR2(30)  := 'NONE';
        v_tax_amount     NUMBER(10, 2);
        v_total_amount   NUMBER(10, 2);
    BEGIN
        SELECT g.first_name || ' ' || g.last_name, g.email,
               rm.room_number, rm.room_type, rm.price_per_night,
               res.check_in_date, res.check_out_date, res.booking_status
        INTO v_guest_name, v_guest_email,
             v_room_number, v_room_type, v_price_per_night,
             v_check_in, v_check_out, v_status
        FROM RESERVATIONS res
        JOIN GUESTS g ON res.guest_id = g.guest_id
        JOIN ROOMS rm ON res.room_id = rm.room_id
        WHERE res.reservation_id = p_reservation_id;

        -- Run dynamic calculation and save to BILLING
        v_total_amount := calculate_invoice(p_reservation_id, p_discount_code, TRUE);

        -- Read back computed bill details
        SELECT total_nights, subtotal, seasonal_surge, discount_amount, tax_amount
        INTO v_nights, v_subtotal, v_surge_amount, v_disc_amount, v_tax_amount
        FROM BILLING
        WHERE reservation_id = p_reservation_id;

        IF v_surge_amount > 0 THEN
            v_surge_pct := '+20% (Peak Season)';
        END IF;

        IF p_discount_code IS NOT NULL THEN
            v_disc_label := UPPER(p_discount_code) || ' (-' || format_curr(v_disc_amount) || ')';
        END IF;

        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('                   STAYLOGIC HOTEL RESORT & SUITES              ');
        DBMS_OUTPUT.PUT_LINE('                       OFFICIAL GUEST FOLIO                     ');
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE('Folio / Booking Ref : #' || p_reservation_id);
        DBMS_OUTPUT.PUT_LINE('Bill Date           : ' || TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS'));
        DBMS_OUTPUT.PUT_LINE('Guest Name          : ' || v_guest_name);
        DBMS_OUTPUT.PUT_LINE('Guest Contact       : ' || v_guest_email);
        DBMS_OUTPUT.PUT_LINE('Booking Status      : ' || v_status);
        DBMS_OUTPUT.PUT_LINE('----------------------------------------------------------------');
        DBMS_OUTPUT.PUT_LINE('Room Assigned       : Room ' || v_room_number || ' (' || v_room_type || ')');
        DBMS_OUTPUT.PUT_LINE('Check-In Date       : ' || TO_CHAR(v_check_in, 'YYYY-MM-DD'));
        DBMS_OUTPUT.PUT_LINE('Check-Out Date      : ' || TO_CHAR(v_check_out, 'YYYY-MM-DD'));
        DBMS_OUTPUT.PUT_LINE('Total Duration      : ' || v_nights || ' Night(s)');
        DBMS_OUTPUT.PUT_LINE('Nightly Rate        : ' || format_curr(v_price_per_night));
        DBMS_OUTPUT.PUT_LINE('----------------------------------------------------------------');
        DBMS_OUTPUT.PUT_LINE(RPAD('Room Base Subtotal', 35) || LPAD(format_curr(v_subtotal), 25));
        DBMS_OUTPUT.PUT_LINE(RPAD('Seasonal Surge [' || v_surge_pct || ']', 35) || LPAD('+' || format_curr(v_surge_amount), 25));
        DBMS_OUTPUT.PUT_LINE(RPAD('Promotional Discount [' || v_disc_label || ']', 35) || LPAD('-' || format_curr(v_disc_amount), 25));
        DBMS_OUTPUT.PUT_LINE(RPAD('Government Tax (12% GST/VAT)', 35) || LPAD('+' || format_curr(v_tax_amount), 25));
        DBMS_OUTPUT.PUT_LINE('================================================================');
        DBMS_OUTPUT.PUT_LINE(RPAD('TOTAL NET PAYABLE:', 35) || LPAD(format_curr(v_total_amount), 25));
        DBMS_OUTPUT.PUT_LINE('================================================================');
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('[ERROR] Folio cannot be generated. Reservation #' || p_reservation_id || ' not found.');
    END print_invoice;

    -- -----------------------------------------------------------------------
    -- Procedure: process_payment
    -- -----------------------------------------------------------------------
    PROCEDURE process_payment(
        p_reservation_id IN NUMBER,
        p_payment_method IN VARCHAR2
    ) IS
    BEGIN
        UPDATE BILLING
        SET payment_status = 'PAID',
            payment_method = p_payment_method,
            bill_date      = SYSDATE
        WHERE reservation_id = p_reservation_id;

        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20003, 'BILL_NOT_FOUND: No bill exists for reservation #' || p_reservation_id);
        END IF;

        UPDATE RESERVATIONS
        SET booking_status = 'CHECKED_IN'
        WHERE reservation_id = p_reservation_id;

        DBMS_OUTPUT.PUT_LINE('[PAYMENT RECEIVED] Reservation #' || p_reservation_id || 
                             ' settled via ' || p_payment_method || '. Guest status updated to CHECKED_IN.');
    END process_payment;

    -- -----------------------------------------------------------------------
    -- Procedure: cancel_reservation
    -- -----------------------------------------------------------------------
    PROCEDURE cancel_reservation(
        p_reservation_id IN NUMBER
    ) IS
    BEGIN
        UPDATE RESERVATIONS
        SET booking_status = 'CANCELLED'
        WHERE reservation_id = p_reservation_id;

        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20003, 'RESERVATION_NOT_FOUND: Reservation #' || p_reservation_id || ' not found.');
        END IF;

        DBMS_OUTPUT.PUT_LINE('[CANCELLED] Reservation #' || p_reservation_id || ' has been marked as CANCELLED.');
    END cancel_reservation;

END staylogic_pkg;
/
SHOW ERRORS;
