-- Drop the seeded weekly 'CoC content release' and 'PoA content release'
-- schedules per Sallie's ask. We delete BY NAME + persona_code (not just
-- id) so a user who renamed them still keeps the row, and so this
-- migration is safe to run twice. Materialised occurrences for those
-- schedules cascade via the FK on schedules → occurrences.

DELETE FROM schedules
 WHERE (name = 'CoC content release' AND persona_code = 'CoC')
    OR (name = 'PoA content release' AND persona_code = 'PoA');
