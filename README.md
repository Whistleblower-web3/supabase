# WikiTruth Supabase Database

This document explains how to set up and use the Supabase database for the WikiTruth project.

## Quick Start

### 1. Create Supabase Project

1. Visit [Supabase Dashboard](https://app.supabase.com/)
2. Create a new project
3. Record the project URL and API Keys

### 2. Configure Environment Variables

1. Copy `env.template` to `.env`
2. Fill in Supabase project configuration:

```bash
SUPABASE_URL=https://xxxxxxxxxxxxx.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

### 3. Run Database Migrations

#### Method A: Using Supabase CLI (Recommended)

```bash
# Install Supabase CLI
npm install -g supabase

# Login to Supabase
supabase login

# Link to project
supabase link --project-ref your-project-ref

# Run migrations
supabase db push
```

#### Method B: Using Supabase Dashboard

1. Login to [Supabase Dashboard](https://app.supabase.com/)
2. Go to Project -> SQL Editor
3. Execute the contents of the following files in order:
   - `migrations/20240101000000_01_tables.sql`
   - `migrations/20240101000001_02_indexes.sql`
   - `migrations/20240101000002_03_functions.sql`

### 4. Configure Client

1. Copy `config/supabase.config.example.ts` to `config/supabase.config.ts`
2. Ensure `.env` file is configured
3. Use in code:

```typescript
import { supabase } from './config/supabase.config';

// Query example
const { data, error } = await supabase
  .from('boxes')
  .select('*')
  .limit(10);
```

## Security Considerations

1. **Service Role Key**:
   - Use only on the server side
   - Do not expose to clients
   - Do not commit to code repository

2. **Row Level Security (RLS)**:
   - Recommend enabling RLS for tables
   - Configure appropriate access policies
   - Refer to RLS policy examples in requirements documentation

3. **Environment Variables**:
   - Do not commit `.env` file to code repository
   - Use `.env.example` as template
   - Use secure key management services in production

## Maintenance

### Update Database Schema

1. Create new migration file: `migrations/YYYYMMDDHHMMSS_description.sql`
2. Use `CREATE OR REPLACE` to ensure idempotent execution
3. Test migration files
4. Execute migrations

### Backup

Supabase provides automatic backup functionality. Recommendations:
- Regularly check backup status
- Manually create backups before important changes
- Keep migration file history

## Troubleshooting

### Migration Failures

1. Check for SQL syntax errors
2. Verify table dependencies are correct
3. Check foreign key constraints
4. View logs in Supabase Dashboard

### Query Performance Issues

1. Check if indexes are created
2. Use `EXPLAIN ANALYZE` to analyze queries
3. Optimize query statements
4. Consider adding composite indexes

### Connection Issues

1. Check environment variable configuration
2. Verify Supabase URL and Key
3. Check network connection
4. View project status in Supabase Dashboard

## Testing

### Running Tests

1. **Configure Test Environment**:
   ```bash
   # Copy test environment variable template
   cp env.test.template .env.test
   # Edit .env.test and fill in Supabase configuration for test environment
   ```

2. **Install Test Dependencies**:
   ```bash
   npm install
   ```

3. **Run Tests**:
   ```bash
   # Run all tests
   npm test

   # Watch mode (for development)
   npm run test:watch

   # Run specific tests
   npm run test:migrations    # Migration tests
   npm run test:network      # Network isolation tests
   npm run test:search       # Search function tests
   npm run test:crud         # CRUD operation tests
   npm run test:types        # Type definition tests

   # Generate coverage report
   npm run test:coverage
   ```
