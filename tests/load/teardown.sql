-- tests/load/teardown.sql
-- Run against both DBs after a load test run to reclaim disk space.
-- Does NOT drop the pool config — just removes slot/ticket data.

-- DB1: remove load test slots
DELETE FROM inventory_slots WHERE pool_id = 'load_test';
DELETE FROM engine_metrics WHERE pool_id = 'load_test';

-- DB2: run this against DB2 separately (see README):
-- DELETE FROM confirmed_tickets WHERE pool_id = 'load_test';
