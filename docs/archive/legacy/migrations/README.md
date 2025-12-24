# Database Migrations

This directory contains SQL migration files for the System Dashboard SQLite database.

## Overview

Migrations are SQL files that modify the database schema or add performance optimizations. They are applied in alphanumeric order by filename.

## Naming Convention

Migration files should follow this pattern:
```
XXX_description.sql
```

Where:
- `XXX` is a three-digit sequence number (001, 002, etc.)
- `description` is a brief description of what the migration does
- All files must have the `.sql` extension

## Current Migrations

- `001_add_performance_indexes.sql` - Adds performance indexes to frequently-queried columns

## Applying Migrations

Migrations can be applied using the DatabaseManager:

```python
from app.db_manager import get_db_manager

db_manager = get_db_manager('/path/to/database.db')
applied, errors = db_manager.apply_migrations('./migrations')
print(f"Applied {applied} migrations")
if errors:
    print(f"Errors: {errors}")
```

## Creating New Migrations

1. Create a new file with the next sequence number
2. Write your SQL statements, separated by semicolons
3. Use `IF NOT EXISTS` for CREATE statements to make migrations idempotent
4. Test your migration on a copy of the database first

Example migration:

```sql
-- Add new column to devices table
ALTER TABLE devices ADD COLUMN notes TEXT;

-- Create index on new column
CREATE INDEX IF NOT EXISTS idx_devices_notes ON devices (notes);
```

## Best Practices

- Migrations should be idempotent (safe to run multiple times)
- Use `IF NOT EXISTS` for CREATE statements
- Test migrations on a backup before applying to production
- Keep migrations focused on a single logical change
- Document any breaking changes in the migration file
