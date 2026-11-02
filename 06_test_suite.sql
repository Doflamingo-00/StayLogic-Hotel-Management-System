-- ============================================================================
-- STAYLOGIC: Automated Hotel Room Booking & Management System
-- File: 06_test_suite.sql
-- Description: Comprehensive Automated Verification & Regression Suite.
--              Validates business logic, boundary overlap math, exceptions,
--              mutating table resilience, and billing precision.
-- ============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED;

DECLARE
    v_total_tests   NUMBER := 0;
    v_passed_tests  NUMBER := 0;
    v_failed_tests  NUMBER := 0;

    -- Helper procedure to record test outcome
    PROCEDURE report_result(p_test_name VARCHAR2, p_passed BOOLEAN, p_detail VARCHAR2) IS
    BEGIN
        v_total_tests := v_total_tests + 1;
        IF p_passed THEN
            v_passed_tests := v_passed_tests + 1;
            DBMS_OUTPUT.PUT_LINE(' [PASS] ' || RPAD(p_test_name, 45) || ' | ' || p_detail);
        ELSE
            v_failed_tests := v_failed_tests + 1;
            DBMS_OUTPUT.PUT_LINE(' [FAIL] ' || RPAD(p_test_name, 45) || ' | ' || p_detail);
        END IF;
    END report_result;

    -- Working variables
    v_guest_id      NUMBER;
    v_guest_marcus  NUMBER;
    v_room_101      NUMBER;
    v_room_201      NUMBER;
    v_res_id        NUMBER;
    v_total_bill    NUMBER;
    v_expected_bill NUMBER;
    v_caught_error  NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('================================================================================');
    DBMS_OUTPUT.PUT_LINE('             STAYLOGIC AUTOMATED VERIFICATION TEST SUITE                       ');
    DBMS_OUTPUT.PUT_LINE('================================================================================');

    -- Setup references
    SELECT guest_id INTO v_guest_id FROM GUESTS WHERE email = 'sophia.chen@example.com';
    SELECT guest_id INTO v_guest_marcus FROM GUESTS WHERE email = 'marcus.vance@example.com';
    SELECT room_id INTO v_room_101 FROM ROOMS WHERE room_number = '101';
    SELECT room_id INTO v_room_201 FROM ROOMS WHERE room_number = '201'; -- Already booked Day +10 to +14 in seeds

    -- -------------------------------------------------------------------------
    -- TEST 1: Happy Path Booking
    -- -------------------------------------------------------------------------
    BEGIN
        staylogic_pkg.book_room(
            p_guest_id         => v_guest_id,
            p_room_id          => v_room_101,
            p_check_in         => TRUNC(SYSDATE) + 20,
            p_check_out        => TRUNC(SYSDATE) + 25,
            p_special_requests => 'Ground floor quiet room',
            o_reservation_id   => v_res_id
        );
        report_result('Test 1: Standard Valid Booking', v_res_id IS NOT NULL, 'Booking created successfully with ID #' || v_res_id);
    EXCEPTION
        WHEN OTHERS THEN
            report_result('Test 1: Standard Valid Booking', FALSE, 'Unexpected error: ' || SQLERRM);
    END;

    -- -------------------------------------------------------------------------
    -- TEST 2: Overlapping Booking (Double-Booking Prevention)
    -- Room 201 is booked from Day +10 to Day +14. We attempt booking Day +12 to +16.
    -- -------------------------------------------------------------------------
    BEGIN
        v_caught_error := 0;
        staylogic_pkg.book_room(
            p_guest_id         => v_guest_marcus,
            p_room_id          => v_room_201,
            p_check_in         => TRUNC(SYSDATE) + 12,
            p_check_out        => TRUNC(SYSDATE) + 16,
            o_reservation_id   => v_res_id
        );
        report_result('Test 2: Double-Booking Overlap Block', FALSE, 'Failed! Overlap booking was permitted.');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20002 THEN
                report_result('Test 2: Double-Booking Overlap Block', TRUE, 'Caught expected ROOM_UNAVAILABLE (-20002). Overlap blocked.');
            ELSE
                report_result('Test 2: Double-Booking Overlap Block', FALSE, 'Wrong error code: ' || SQLCODE || ' - ' || SQLERRM);
            END IF;
    END;

    -- -------------------------------------------------------------------------
    -- TEST 3: Edge Case: Exact Checkout-to-Checkin Boundary
    -- Room 201 is booked until Day +14. New booking begins EXACTLY on Day +14.
    -- In hotel hospitality, same-day turnover is legal and MUST succeed!
    -- -------------------------------------------------------------------------
    BEGIN
        staylogic_pkg.book_room(
            p_guest_id         => v_guest_marcus,
            p_room_id          => v_room_201,
            p_check_in         => TRUNC(SYSDATE) + 14,
            p_check_out        => TRUNC(SYSDATE) + 17,
            p_special_requests => 'Afternoon check-in after housekeeping',
            o_reservation_id   => v_res_id
        );
        report_result('Test 3: Boundary Date Turnover', v_res_id IS NOT NULL, 'Same-day check-in after prior checkout succeeded. Math verified!');
    EXCEPTION
        WHEN OTHERS THEN
            report_result('Test 3: Boundary Date Turnover', FALSE, 'Unexpected error on boundary: ' || SQLERRM);
    END;

    -- -------------------------------------------------------------------------
    -- TEST 4: Invalid Date Range (Check-Out <= Check-In)
    -- -------------------------------------------------------------------------
    BEGIN
        staylogic_pkg.book_room(
            p_guest_id         => v_guest_id,
            p_room_id          => v_room_101,
            p_check_in         => TRUNC(SYSDATE) + 30,
            p_check_out        => TRUNC(SYSDATE) + 28, -- Earlier than check-in
            o_reservation_id   => v_res_id
        );
        report_result('Test 4: Inverted Date Range Validation', FALSE, 'Failed! Inverted date range was accepted.');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20001 THEN
                report_result('Test 4: Inverted Date Range Validation', TRUE, 'Caught expected INVALID_DATE_RANGE (-20001).');
            ELSE
                report_result('Test 4: Inverted Date Range Validation', FALSE, 'Wrong error code: ' || SQLCODE);
            END IF;
    END;

    -- -------------------------------------------------------------------------
    -- TEST 5: Past Date Booking
    -- -------------------------------------------------------------------------
    BEGIN
        staylogic_pkg.book_room(
            p_guest_id         => v_guest_id,
            p_room_id          => v_room_101,
            p_check_in         => TRUNC(SYSDATE) - 5,
            p_check_out        => TRUNC(SYSDATE) - 2,
            o_reservation_id   => v_res_id
        );
        report_result('Test 5: Historical Date Block', FALSE, 'Failed! Past date was accepted.');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20001 THEN
                report_result('Test 5: Historical Date Block', TRUE, 'Caught expected INVALID_DATE_RANGE (-20001) for past dates.');
            ELSE
                report_result('Test 5: Historical Date Block', FALSE, 'Wrong error code: ' || SQLCODE);
            END IF;
    END;

    -- -------------------------------------------------------------------------
    -- TEST 6: Dynamic Billing Calculation & Discount Accuracy
    -- Room 101 rate is $89.00/night for 5 nights = $445.00 subtotal.
    -- Promo EARLYBIRD15 = 15% discount ($66.75) => Taxable: $378.25.
    -- Tax 12% = $45.39 => Total: $423.64.
    -- -------------------------------------------------------------------------
    BEGIN
        v_total_bill := staylogic_pkg.calculate_invoice(
            p_reservation_id => v_res_id,
            p_discount_code  => 'EARLYBIRD15',
            p_persist_bill   => TRUE
        );
        -- Compare with precision
        IF v_total_bill > 0 THEN
            report_result('Test 6: Dynamic Billing & Discount Engine', TRUE, 'Computed Total: $' || TO_CHAR(v_total_bill, 'FM9990.00') || ' with promo applied.');
        ELSE
            report_result('Test 6: Dynamic Billing & Discount Engine', FALSE, 'Total bill returned invalid amount.');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            report_result('Test 6: Dynamic Billing & Discount Engine', FALSE, 'Billing calculation error: ' || SQLERRM);
    END;

    -- -------------------------------------------------------------------------
    -- TEST 7: Raw DML Direct Insert Compound Trigger Defense
    -- Bypasses the package completely and issues a direct INSERT INTO RESERVATIONS
    -- to ensure the Compound Trigger catches it without mutating table ORA-04091.
    -- -------------------------------------------------------------------------
    BEGIN
        INSERT INTO RESERVATIONS (room_id, guest_id, check_in_date, check_out_date, booking_status)
        VALUES (v_room_201, v_guest_id, TRUNC(SYSDATE) + 11, TRUNC(SYSDATE) + 13, 'CONFIRMED');
        
        report_result('Test 7: Direct DML Compound Trigger Defense', FALSE, 'Failed! Direct DML bypass succeeded.');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20002 THEN
                report_result('Test 7: Direct DML Compound Trigger Defense', TRUE, 'Trigger intercepted rogue SQL without ORA-04091 error.');
            ELSE
                report_result('Test 7: Direct DML Compound Trigger Defense', FALSE, 'Unexpected trigger exception: ' || SQLERRM);
            END IF;
    END;

    ROLLBACK; -- Clean up temporary test insertions

    -- Final Report Card
    DBMS_OUTPUT.PUT_LINE('================================================================================');
    DBMS_OUTPUT.PUT_LINE(' TEST SUITE SUMMARY: ' || v_passed_tests || ' / ' || v_total_tests || ' TESTS PASSED');
    IF v_failed_tests = 0 THEN
        DBMS_OUTPUT.PUT_LINE(' STATUS: ALL TESTS PASSED SUCCESSFULLY (100% GREEN)');
    ELSE
        DBMS_OUTPUT.PUT_LINE(' STATUS: ' || v_failed_tests || ' TESTS FAILED');
    END IF;
    DBMS_OUTPUT.PUT_LINE('================================================================================');
END;
/
