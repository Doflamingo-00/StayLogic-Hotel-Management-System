-- ============================================================================
-- STAYLOGIC: Automated Hotel Room Booking & Management System
-- File: 05_seed_data.sql
-- Description: Realistic seed data for rooms across 4 tiers, guests,
--              and benchmark bookings for immediate demonstration.
-- ============================================================================

-- Clean existing data
DELETE FROM BILLING;
DELETE FROM RESERVATIONS;
DELETE FROM ROOMS;
DELETE FROM GUESTS;

-- ---------------------------------------------------------------------------
-- 1. Seed Rooms (Tiers: Standard, Deluxe, Suite, Penthouse)
-- ---------------------------------------------------------------------------
INSERT INTO ROOMS (room_number, room_type, price_per_night, floor_number, status)
VALUES ('101', 'STANDARD', 89.00, 1, 'AVAILABLE');

INSERT INTO ROOMS (room_number, room_type, price_per_night, floor_number, status)
VALUES ('102', 'STANDARD', 89.00, 1, 'AVAILABLE');

INSERT INTO ROOMS (room_number, room_type, price_per_night, floor_number, status)
VALUES ('201', 'DELUXE', 149.00, 2, 'AVAILABLE');

INSERT INTO ROOMS (room_number, room_type, price_per_night, floor_number, status)
VALUES ('202', 'DELUXE', 149.00, 2, 'AVAILABLE');

INSERT INTO ROOMS (room_number, room_type, price_per_night, floor_number, status)
VALUES ('203', 'DELUXE', 165.00, 2, 'MAINTENANCE'); -- Room under maintenance for testing

INSERT INTO ROOMS (room_number, room_type, price_per_night, floor_number, status)
VALUES ('301', 'SUITE', 279.00, 3, 'AVAILABLE');

INSERT INTO ROOMS (room_number, room_type, price_per_night, floor_number, status)
VALUES ('302', 'SUITE', 299.00, 3, 'AVAILABLE');

INSERT INTO ROOMS (room_number, room_type, price_per_night, floor_number, status)
VALUES ('401', 'PENTHOUSE', 550.00, 4, 'AVAILABLE');

-- ---------------------------------------------------------------------------
-- 2. Seed Guests
-- ---------------------------------------------------------------------------
INSERT INTO GUESTS (first_name, last_name, email, phone, id_card_num)
VALUES ('Alexander', 'Wright', 'alex.wright@example.com', '+1-555-0192', 'PASSPORT-US-99214');

INSERT INTO GUESTS (first_name, last_name, email, phone, id_card_num)
VALUES ('Elena', 'Rostova', 'elena.rostova@example.com', '+1-555-0144', 'DL-CA-44912');

INSERT INTO GUESTS (first_name, last_name, email, phone, id_card_num)
VALUES ('Marcus', 'Vance', 'marcus.vance@example.com', '+1-555-0187', 'PASSPORT-UK-11028');

INSERT INTO GUESTS (first_name, last_name, email, phone, id_card_num)
VALUES ('Sophia', 'Chen', 'sophia.chen@example.com', '+1-555-0123', 'DL-NY-88231');

INSERT INTO GUESTS (first_name, last_name, email, phone, id_card_num)
VALUES ('David', 'Miller', 'david.miller@example.com', '+1-555-0165', 'PASSPORT-AU-55291');

COMMIT;

-- ---------------------------------------------------------------------------
-- 3. Seed Benchmark Reservations (Using safe dynamic dates)
-- ---------------------------------------------------------------------------
DECLARE
    v_res1 NUMBER;
    v_res2 NUMBER;
    v_res3 NUMBER;
    v_room_deluxe NUMBER;
    v_room_suite  NUMBER;
    v_guest_alex  NUMBER;
    v_guest_elena NUMBER;
BEGIN
    SELECT room_id INTO v_room_deluxe FROM ROOMS WHERE room_number = '201';
    SELECT room_id INTO v_room_suite  FROM ROOMS WHERE room_number = '301';
    SELECT guest_id INTO v_guest_alex FROM GUESTS WHERE email = 'alex.wright@example.com';
    SELECT guest_id INTO v_guest_elena FROM GUESTS WHERE email = 'elena.rostova@example.com';

    -- Reservation 1: Alex Wright books Deluxe Room 201 from Day +10 to Day +14
    staylogic_pkg.book_room(
        p_guest_id         => v_guest_alex,
        p_room_id          => v_room_deluxe,
        p_check_in         => TRUNC(SYSDATE) + 10,
        p_check_out        => TRUNC(SYSDATE) + 14,
        p_special_requests => 'High floor, quiet corner, extra feather pillows',
        o_reservation_id   => v_res1
    );

    -- Calculate invoice & persist bill with SUMMER10 discount
    staylogic_pkg.calculate_invoice(
        p_reservation_id => v_res1,
        p_discount_code  => 'SUMMER10',
        p_persist_bill   => TRUE
    );

    -- Reservation 2: Elena Rostova books Suite Room 301 from Day +15 to Day +20
    staylogic_pkg.book_room(
        p_guest_id         => v_guest_elena,
        p_room_id          => v_room_suite,
        p_check_in         => TRUNC(SYSDATE) + 15,
        p_check_out        => TRUNC(SYSDATE) + 20,
        p_special_requests => 'Late check-in requested (after 8 PM)',
        o_reservation_id   => v_res2
    );

    -- Calculate invoice & persist bill with VIP20 discount
    staylogic_pkg.calculate_invoice(
        p_reservation_id => v_res2,
        p_discount_code  => 'VIP20',
        p_persist_bill   => TRUE
    );

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('[SEED DATA] Successfully seeded Rooms, Guests, and Initial Bookings.');
END;
/
