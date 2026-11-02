-- ============================================================================
-- STAYLOGIC: Automated Hotel Room Booking & Management System
-- File: 02_staylogic_pkg_spec.sql
-- Description: Package Specification declaring custom exceptions, constants,
--              record types, cursor types, and business operations.
-- ============================================================================

CREATE OR REPLACE PACKAGE staylogic_pkg AS

    -- -----------------------------------------------------------------------
    -- Custom User-Defined Exceptions and Error Number Mappings
    -- -----------------------------------------------------------------------
    e_invalid_date_range EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_invalid_date_range, -20001);
    
    e_room_unavailable EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_room_unavailable, -20002);
    
    e_reservation_not_found EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_reservation_not_found, -20003);
    
    e_bill_already_exists EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_bill_already_exists, -20004);

    -- -----------------------------------------------------------------------
    -- Constants: Tax rates, surge percentages, and promo codes
    -- -----------------------------------------------------------------------
    c_standard_tax_rate  CONSTANT NUMBER := 0.12;  -- 12% GST/VAT
    c_peak_season_surge  CONSTANT NUMBER := 0.20;  -- 20% Peak season surge (June, July, Dec)
    c_weekend_surge      CONSTANT NUMBER := 0.10;  -- 10% Weekend stay surge (Fri/Sat nights)

    -- -----------------------------------------------------------------------
    -- Record Types for Reporting & Availability Queries
    -- -----------------------------------------------------------------------
    TYPE t_room_record IS RECORD (
        room_id         ROOMS.room_id%TYPE,
        room_number     ROOMS.room_number%TYPE,
        room_type       ROOMS.room_type%TYPE,
        price_per_night ROOMS.price_per_night%TYPE,
        floor_number    ROOMS.floor_number%TYPE
    );

    TYPE t_room_table IS TABLE OF t_room_record;

    -- -----------------------------------------------------------------------
    -- Public Functions and Procedures
    -- -----------------------------------------------------------------------

    -- Function: Checks whether a specific room is free for a given date window
    FUNCTION is_room_available(
        p_room_id       IN NUMBER,
        p_check_in      IN DATE,
        p_check_out     IN DATE,
        p_ignore_res_id IN NUMBER DEFAULT NULL
    ) RETURN BOOLEAN;

    -- Procedure: Parameterized cursor displaying all available rooms for a window
    PROCEDURE find_available_rooms(
        p_check_in   IN DATE,
        p_check_out  IN DATE,
        p_room_type  IN VARCHAR2 DEFAULT NULL
    );

    -- Procedure: Complete transaction to book a room with validation & exception handling
    PROCEDURE book_room(
        p_guest_id         IN NUMBER,
        p_room_id          IN NUMBER,
        p_check_in         IN DATE,
        p_check_out        IN DATE,
        p_special_requests IN VARCHAR2 DEFAULT NULL,
        o_reservation_id   OUT NUMBER
    );

    -- Function: Computes stay duration, seasonal surge, promo discounts, taxes, and total
    FUNCTION calculate_invoice(
        p_reservation_id IN NUMBER,
        p_discount_code  IN VARCHAR2 DEFAULT NULL,
        p_persist_bill   IN BOOLEAN DEFAULT FALSE
    ) RETURN NUMBER;

    -- Procedure: Formats and outputs an ASCII itemized guest folio / bill
    PROCEDURE print_invoice(
        p_reservation_id IN NUMBER,
        p_discount_code  IN VARCHAR2 DEFAULT NULL
    );

    -- Procedure: Updates payment status for an existing billing record
    PROCEDURE process_payment(
        p_reservation_id IN NUMBER,
        p_payment_method IN VARCHAR2
    );

    -- Procedure: Cancels a reservation safely
    PROCEDURE cancel_reservation(
        p_reservation_id IN NUMBER
    );

END staylogic_pkg;
/
SHOW ERRORS;
