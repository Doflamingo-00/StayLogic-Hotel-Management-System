-- ============================================================================
-- STAYLOGIC: Automated Hotel Room Booking & Management System
-- File: run_all.sql
-- Description: Master Orchestration Script. Builds schema, packages,
--              triggers, seed data, and executes the full test suite.
-- ============================================================================

SET ECHO OFF;
SET FEEDBACK ON;
SET SERVEROUTPUT ON SIZE UNLIMITED;

PROMPT [1/7] Deploying Schema Tables & Constraints...
@01_schema_ddl.sql

PROMPT [2/7] Compiling Package Specification (staylogic_pkg)...
@02_staylogic_pkg_spec.sql

PROMPT [3/7] Compiling Package Body (staylogic_pkg)...
@03_staylogic_pkg_body.sql

PROMPT [4/7] Deploying Double-Booking Shield Compound Trigger...
@04_compound_trigger.sql

PROMPT [5/7] Seeding Baseline Rooms, Guests, and Bookings...
@05_seed_data.sql

PROMPT [6/7] Running Automated Verification Test Suite...
@06_test_suite.sql

PROMPT [7/7] Launching Interactive Demonstration Folio...
@07_interactive_cli.sql

PROMPT 
PROMPT ========================================================================
PROMPT [STAYLOGIC DEPLOYMENT COMPLETE]
PROMPT All database objects are compiled and verified.
PROMPT ========================================================================
