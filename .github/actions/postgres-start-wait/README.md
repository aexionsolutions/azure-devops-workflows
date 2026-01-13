# Postgres Start & Wait (Composite Action)

Starts an Azure PostgreSQL Flexible Server and waits for `Ready`.

Inputs:
- `resource-group` (required)
- `server-name` (required)
- `attempts` (default 60)
- `sleep-seconds` (default 10)
- `non-blocking` (default false)
- `api-version` (default 2024-08-01)

Example (non-blocking short warm-up):
```
- uses: ./.github/actions/postgres-start-wait
  with:
    resource-group: ${{ env.RG }}
    server-name: tems-${{ env.ENV }}-pg
    attempts: '30'
    sleep-seconds: '5'
    non-blocking: 'true'
```