-- ============================================================================
-- STAYLOGIC: Automated Hotel Room Booking & Management System
-- File: 01_schema_ddl.sql
-- Description: DDL Schema creation with Primary Keys, Foreign Keys, 
--              Check Constraints, Sequences / Identity columns, and Indexes.
-- ============================================================================

-- Drop existing tables in reverse dependency order (safe script execution)
BEGIN
    FOR t IN (
        SELECT table_name FROM user_tables 
        WHERE table_name IN ('BILLING', 'RESERVATIONS', 'ROOMS', 'GUESTS')
    ) LOOP
        EXECUTE IMMEDIATE 'DROP TABLE ' || t.table_name || ' CASCADE CONSTRAINTS PURGE';
    END LOOP;
END;
/

-- ---------------------------------------------------------------------------
-- 1. ROOMS Table
-- Stores inventory, room categories, pricing, and operational status.
-- ---------------------------------------------------------------------------
CREATE TABLE ROOMS (
    room_id         NUMBER GENERATED ALWAYS AS IDENTITY (START WITH 101 INCREMENT BY 1),
    room_number     VARCHAR2(10)     NOT NULL,
    room_type       VARCHAR2(20)     NOT NULL,
    price_per_night NUMBER(10, 2)    NOT NULL,
    floor_number    NUMBER(3)        DEFAULT 1 NOT NULL,
    status          VARCHAR2(20)     DEFAULT 'AVAILABLE' NOT NULL,
    created_at      DATE             DEFAULT SYSDATE NOT NULL,
    
    CONSTRAINT pk_rooms PRIMARY KEY (room_id),
    CONSTRAINT uq_room_number UNIQUE (room_number),
    CONSTRAINT chk_room_type CHECK (room_type IN ('STANDARD', 'DELUXE', 'SUITE', 'PENTHOUSE')),
    CONSTRAINT chk_room_price CHECK (price_per_night > 0),
    CONSTRAINT chk_room_status CHECK (status IN ('AVAILABLE', 'OCCUPIED', 'MAINTENANCE'))
);

-- ---------------------------------------------------------------------------
-- 2. GUESTS Table
-- Stores guest profile details, contact information, and loyalty status.
-- ---------------------------------------------------------------------------
CREATE TABLE GUESTS (
    guest_id        NUMBER GENERATED ALWAYS AS IDENTITY (START WITH 1001 INCREMENT BY 1),
    first_name      VARCHAR2(50)     NOT NULL,
    last_name       VARCHAR2(50)     NOT NULL,
    email           VARCHAR2(100)    NOT NULL,
    phone           VARCHAR2(20)     NOT NULL,
    id_card_num     VARCHAR2(50),
    created_at      DATE             DEFAULT SYSDATE NOT NULL,
    
    CONSTRAINT pk_guests PRIMARY KEY (guest_id),
    CONSTRAINT uq_guest_email UNIQUE (email),
    CONSTRAINT chk_guest_email_format CHECK (INSTR(email, '@') > 1 AND INSTR(email, '.') > INSTR(email, '@') + 1)
);

-- ---------------------------------------------------------------------------
-- 3. RESERVATIONS Table
-- Core transactional entity linking guests, rooms, and booking date ranges.
-- ---------------------------------------------------------------------------
CREATE TABLE RESERVATIONS (
    reservation_id  NUMBER GENERATED ALWAYS AS IDENTITY (START WITH 50001 INCREMENT BY 1),
    room_id         NUMBER           NOT NULL,
    guest_id        NUMBER           NOT NULL,
    check_in_date   DATE             NOT NULL,
    check_out_date  DATE             NOT NULL,
    booking_status  VARCHAR2(20)     DEFAULT 'CONFIRMED' NOT NULL,
    special_requests VARCHAR2(255),
    created_at      DATE             DEFAULT SYSDATE NOT NULL,
    
    CONSTRAINT pk_reservations PRIMARY KEY (reservation_id),
    CONSTRAINT fk_res_room FOREIGN KEY (room_id) REFERENCES ROOMS (room_id) ON DELETE CASCADE,
    CONSTRAINT fk_res_guest FOREIGN KEY (guest_id) REFERENCES GUESTS (guest_id) ON DELETE CASCADE,
    CONSTRAINT chk_res_status CHECK (booking_status IN ('CONFIRMED', 'CHECKED_IN', 'CHECKED_OUT', 'CANCELLED')),
    CONSTRAINT chk_res_dates CHECK (check_out_date > check_in_date)
);

-- High-performance composite index for availability and overlap queries
CREATE INDEX idx_res_room_dates ON RESERVATIONS (room_id, check_in_date, check_out_date, booking_status);
CREATE INDEX idx_res_guest ON RESERVATIONS (guest_id);

-- ---------------------------------------------------------------------------
-- 4. BILLING Table
-- Financial records capturing base rate, nights, adjustments, taxes, and final total.
-- ---------------------------------------------------------------------------
CREATE TABLE BILLING (
    bill_id         NUMBER GENERATED ALWAYS AS IDENTITY (START WITH 80001 INCREMENT BY 1),
    reservation_id  NUMBER           NOT NULL,
    total_nights    NUMBER(4)        NOT NULL,
    base_rate       NUMBER(10, 2)    NOT NULL,
    subtotal        NUMBER(10, 2)    NOT NULL,
    seasonal_surge  NUMBER(10, 2)    DEFAULT 0.00 NOT NULL,
    discount_amount NUMBER(10, 2)    DEFAULT 0.00 NOT NULL,
    tax_amount      NUMBER(10, 2)    NOT NULL,
    total_amount    NUMBER(10, 2)    NOT NULL,
    payment_status  VARCHAR2(20)     DEFAULT 'PENDING' NOT NULL,
    payment_method  VARCHAR2(30),
    bill_date       DATE             DEFAULT SYSDATE NOT NULL,
    
    CONSTRAINT pk_billing PRIMARY KEY (bill_id),
    CONSTRAINT uq_billing_reservation UNIQUE (reservation_id),
    CONSTRAINT fk_bill_reservation FOREIGN KEY (reservation_id) REFERENCES RESERVATIONS (reservation_id) ON DELETE CASCADE,
    CONSTRAINT chk_billing_nights CHECK (total_nights > 0),
    CONSTRAINT chk_billing_amounts CHECK (subtotal >= 0 AND tax_amount >= 0 AND total_amount >= 0),
    CONSTRAINT chk_payment_status CHECK (payment_status IN ('PENDING', 'PAID', 'REFUNDED'))
);

CREATE INDEX idx_bill_res ON BILLING (reservation_id);

PROMPT [SUCCESS] Schema tables, constraints, and indexes created successfully.
