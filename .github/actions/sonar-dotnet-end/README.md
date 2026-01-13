# Sonar .NET End (Composite Action)

Completes SonarCloud analysis.

Inputs:
- `token`: SonarCloud token

Example:
```
- uses: ./.github/actions/sonar-dotnet-end
  with:
    token: ${{ secrets.SONAR_TOKEN }}
```