# Backup and Restore

Screenlogger can export a self-contained `.screenloggerbackup` package from
Settings under Storage. Export uses a consistent SQLite snapshot and verifies
every managed file before completing. The live Library remains unchanged.

Restore verifies package structure, manifest hashes, schema compatibility, file
paths, and available disk space before presenting a review. Replacing the
Library is the only step that pauses capture or changes current data.

Keep backups on storage appropriate for sensitive screenshots. A backup contains
the same private material as the Library and is not encrypted by Screenlogger.

Do not manually copy an active SQLite database without its WAL state. Use the
in-app export flow for a consistent backup.
