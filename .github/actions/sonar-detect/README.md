# Sonar Detect (Composite Action)

Standardizes SonarCloud enablement for workflows.

Inputs:
- `requested` (true/false)
- `token` (SONAR_TOKEN)
- `org` (SONAR_ORG)
- `projectKey` (SONAR_PROJECT_KEY)

Outputs:
- `enabled`: 'true' or 'false'

Also exports `SONAR_ENABLED` to the job environment.

Example:
```
- id: sonar
  uses: ./.github/actions/sonar-detect
  with:
    requested: true
    token: ${{ secrets.SONAR_TOKEN }}
    org: ${{ secrets.SONAR_ORG }}
    projectKey: ${{ secrets.SONAR_PROJECT_KEY }}
```