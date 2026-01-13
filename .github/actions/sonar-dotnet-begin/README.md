# Sonar .NET Begin (Composite Action)

Installs `dotnet-sonarscanner` and runs analysis begin.

Inputs:
- `token`, `org`, `projectKey` (required)
- `branch` (optional; defaults empty)
- `cobertura_glob` (optional; defaults **/TestResults/**/coverage.cobertura.xml)

Example:
```
- uses: ./.github/actions/sonar-dotnet-begin
  with:
    token: ${{ secrets.SONAR_TOKEN }}
    org: ${{ secrets.SONAR_ORG }}
    projectKey: ${{ secrets.SONAR_PROJECT_KEY }}
    branch: ${{ github.ref_name }}
```