-- ============================================================================
-- STAYLOGIC: Automated Hotel Room Booking & Management System
-- File: 07_interactive_cli.sql
-- Description: Interactive Terminal Dashboard for SQL*Plus / SQL Developer.
--              Demonstrates availability search, live booking, and invoice printing.
-- ============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED;
SET LINESIZE 200;
SET PAGESIZE 50;
SET FEEDBACK OFF;

PROMPT 
PROMPT ========================================================================
PROMPT                     STAYLOGIC HOTEL CONSOLE DEMO                        
PROMPT ========================================================================
PROMPT 1. Querying Real-Time Room Availability for next week...
PROMPT 

BEGIN
    -- Query availability for Day +3 to Day +7
    staylogic_pkg.find_available_rooms(
        p_check_in  => TRUNC(SYSDATE) + 3,
        p_check_out => TRUNC(SYSDATE) + 7
    );
END;
/

PROMPT 
PROMPT 2. Active Bookings in Database:
PROMPT ------------------------------------------------------------------------
SELECT 
    r.reservation_id AS "RES_ID",
    g.first_name || ' ' || g.last_name AS "GUEST_NAME",
    rm.room_number AS "ROOM",
    rm.room_type AS "TIER",
    TO_CHAR(r.check_in_date, 'YYYY-MM-DD') AS "CHECK_IN",
    TO_CHAR(r.check_out_date, 'YYYY-MM-DD') AS "CHECK_OUT",
    r.booking_status AS "STATUS"
FROM RESERVATIONS r
JOIN GUESTS g ON r.guest_id = g.guest_id
JOIN ROOMS rm ON r.room_id = rm.room_id
ORDER BY r.check_in_date ASC;

PROMPT 
PROMPT 3. Generating Sample Folio for seeded Reservation #50001 with Voucher:
PROMPT ------------------------------------------------------------------------

DECLARE
    v_sample_res NUMBER;
BEGIN
    SELECT MIN(reservation_id) INTO v_sample_res FROM RESERVATIONS;
    IF v_sample_res IS NOT NULL THEN
        staylogic_pkg.print_invoice(v_sample_res, 'SUMMER10');
    ELSE
        DBMS_OUTPUT.PUT_LINE('No active reservation found to print.');
    END IF;
END;
/

SET FEEDBACK ON;
PROMPT ========================================================================
PROMPT Demo run complete. You can also run @06_test_suite.sql to verify all tests.
PROMPT ========================================================================
