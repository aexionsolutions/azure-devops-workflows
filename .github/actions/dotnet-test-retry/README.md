# Smart .NET Test Retry

A composite GitHub Action that runs `dotnet test` with intelligent retry logic - **only re-runs failed tests** instead of the entire test suite.

## Why?

Traditional retry logic reruns the **entire test suite** on each attempt:
- ✗ 99 passing tests + 1 flaky test = All 100 tests run 3× = **300 test executions**
- ✗ Wastes ~2x-3x the time unnecessarily
- ✗ Puts load on all tests, not just flaky ones

Smart retry only reruns **failed tests**:
- ✓ 99 passing tests + 1 flaky test = 100 tests (attempt 1) + 1 test (attempt 2) = **101 test executions**
- ✓ ~66% reduction in test time when you have flaky tests
- ✓ Efficient use of CI/CD resources

## Features

- 🎯 **Smart retry**: Parses `.trx` files to identify failed tests, only reruns those
- 🧪 **Framework support**: Works with NUnit, xUnit, MSTest, Reqnroll, SpecFlow
- 🔧 **Flexible filters**: Supports dotnet test filter expressions (Category, FullyQualifiedName, etc.)
- 📊 **Multiple outputs**: Exit code, attempts used, failed tests count
- 🛡️ **Graceful fallback**: If TRX parsing fails, falls back to full test rerun
- 🎭 **Special characters**: Handles Reqnroll/SpecFlow scenario names with spaces, parentheses, quotes
- ✅ **Correct filter syntax**: Builds proper OR expressions for dotnet test --filter
- 🔒 **No shell injection**: Uses PowerShell arrays, avoids eval and quote escaping issues

## Why This Implementation is Correct

This action fixes several critical issues found in naive retry implementations:

### ✅ Proper TRX Parsing
- Uses XML DOM with XPath and namespace handling
- Maps `testId` → `TestMethod className.name` for stable FQNs
- Doesn't rely on unreliable `testName` display strings
- O(n) performance, not O(n²)

### ✅ Correct Filter Syntax
**Wrong:** `FullyQualifiedName~A|B|C` 
- This creates: `(FullyQualifiedName~A) OR (B) OR (C)` ← `B` and `C` aren't valid expressions

**Correct:** `(FullyQualifiedName="A") | (FullyQualifiedName="B") | (FullyQualifiedName="C")`
- Proper OR conditions in dotnet test filter language

### ✅ Safe Argument Handling
- PowerShell arrays prevent shell injection
- No `eval` command that breaks on special characters
- Quotes in test names are properly escaped

## Usage

### Basic Example

```yaml
- name: Run tests with smart retry
  uses: ./.github/actions/dotnet-test-retry
  with:
    project: tests/MyApp.Tests/MyApp.Tests.csproj
    max-attempts: 3
```

### With Test Filter

```yaml
- name: Run smoke tests with retry
  uses: ./.github/actions/dotnet-test-retry
  with:
    project: tests/E2E.Tests/E2E.Tests.csproj
    filter: Category=smoke
    max-attempts: 3
```

### Reqnroll/SpecFlow with Gherkin Tags

```yaml
- name: Strip @ from Gherkin tag
  run: |
    FILTER="${{ inputs.test_filter }}"
    FILTER="${FILTER#@}"  # Remove @ prefix
    echo "TEST_FILTER=Category=$FILTER" >> $GITHUB_ENV

- name: Run Reqnroll tests
  uses: ./.github/actions/dotnet-test-retry
  with:
    project: tests/E2E.Reqnroll/E2E.Reqnroll.csproj
    filter: ${{ env.TEST_FILTER }}
    max-attempts: 3
    configuration: Release
    no-build: true
```

### Using Outputs

```yaml
- name: Run tests
  id: tests
  uses: ./.github/actions/dotnet-test-retry
  with:
    project: tests/MyApp.Tests/MyApp.Tests.csproj
    max-attempts: 3

- name: Report test results
  if: always()
  run: |
    echo "Exit code: ${{ steps.tests.outputs.exit-code }}"
    echo "Attempts used: ${{ steps.tests.outputs.attempts-used }}"
    echo "Failed tests: ${{ steps.tests.outputs.failed-tests-count }}"
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `project` | Path to `.csproj` file or directory to test | Yes | - |
| `filter` | Test filter (e.g., `Category=smoke`, `FullyQualifiedName~MyTest`) | No | `''` (all tests) |
| `max-attempts` | Maximum number of test attempts (1 disables retry) | No | `3` |
| `results-directory` | Directory to store test results (`.trx` files) | No | `./TestResults` |
| `configuration` | Build configuration (Debug/Release) | No | `Release` |
| `no-build` | Skip building the test project (`true`/`false`) | No | `false` |
| `additional-args` | Additional arguments to pass to `dotnet test` | No | `''` |
| `trx-filename-prefix` | Prefix for TRX log filenames | No | `test-results` |

## Outputs

| Output | Description |
|--------|-------------|
| `exit-code` | Exit code from the test run (0 = success, non-zero = failure) |
| `attempts-used` | Number of attempts used |
| `failed-tests-count` | Number of tests that failed on first attempt |

## How It Works

1. **First attempt**: Runs all tests (with filter if provided)
2. **Parse failures**: If tests fail, extracts failed test IDs from `.trx` file using proper XML parsing
   - Maps `testId` → `UnitTest/TestMethod` → `className.name` for stable FQN
   - Uses XPath with proper namespace handling
3. **Build correct filter**: Creates proper OR expression: `(FullyQualifiedName="Test1") | (FullyQualifiedName="Test2")`
4. **Combine filters**: ANDs with user-provided filter: `(Category=smoke) & ((FullyQualifiedName="Test1") | (FullyQualifiedName="Test2"))`
5. **Repeat**: Continues until tests pass or max attempts reached

## Implementation Details

### Why PowerShell instead of Bash?

The action uses PowerShell (`pwsh`) for several critical reasons:

1. **Proper XML parsing**: PowerShell's native XML DOM parsing is deterministic and namespace-aware
2. **Correct filter syntax**: Builds `(FullyQualifiedName="A") | (FullyQualifiedName="B")` instead of broken `FullyQualifiedName~A|B|C`
3. **No eval risks**: Avoids shell injection and quote escaping issues
4. **Special characters**: Handles Reqnroll scenario names with spaces, parentheses, quotes safely

### TRX Parsing Strategy

The action maps failed tests using:
```powershell
# 1. Find failed test IDs
UnitTestResult[@outcome='Failed']/@testId

# 2. Map testId → stable FQN
UnitTest[@id='<testId>']/TestMethod/@className + @name
```

This is more reliable than using `@testName` which is often a display name (especially in Reqnroll/SpecFlow).

## Important Caveats

### ⚠️ Order-Dependent Test Failures

**Retrying only failed tests can hide test pollution issues.**

If some tests only fail when run after other tests (shared state / lack of isolation), rerunning only the failed ones may pass, making you think it's flaky when it's actually a real isolation bug.

**Mitigation:**
- Keep `max-attempts` low (2-3) to detect persistent failures quickly
- If the same test fails on retry, it's likely a real issue
- Consider: if >10 tests fail, treat as systemic issue (not flakiness)

### 📝 Additional Args Format

The `additional-args` input splits on whitespace. **Do not wrap in quotes**:

❌ **Wrong:**
```yaml
additional-args: --logger "console;verbosity=normal"
```

✅ **Correct:**
```yaml
additional-args: --logger console;verbosity=normal
```

Multiple args work fine:
```yaml
additional-args: --logger console;verbosity=normal --blame-hang-timeout 5min
```

## Example Output

```
🧪 Smart .NET Test Retry
   Project: tests/E2E.Tests/E2E.Tests.csproj
   Filter: Category=smoke
   Max attempts: 3
   Results directory: ./TestResults

🔄 Running tests (attempt 1/3)
➡️  dotnet test tests/E2E.Tests/E2E.Tests.csproj -c Release --results-directory ./TestResults --logger trx;LogFileName=test-results-1.trx --filter Category=smoke
❌ 97 passed, 3 failed

⚠️ Parsing failures from: ./TestResults/test-results-1.trx
🔄 Retrying ONLY 3 failed test(s) (attempt 2/3)
   Failed tests:
     - E2E.Tests.LoginFeature.Login_with_invalid_password
     - E2E.Tests.CheckoutFeature.Checkout_with_empty_cart
     - E2E.Tests.SearchFeature.Search_with_special_characters
   Retry filter: (Category=smoke) & ((FullyQualifiedName="E2E.Tests.LoginFeature.Login_with_invalid_password") | (FullyQualifiedName="E2E.Tests.CheckoutFeature.Checkout_with_empty_cart") | (FullyQualifiedName="E2E.Tests.SearchFeature.Search_with_special_characters"))
➡️  dotnet test tests/E2E.Tests/E2E.Tests.csproj -c Release --results-directory ./TestResults --logger trx;LogFileName=test-results-2.trx --filter (Category=smoke) & ((FullyQualifiedName="E2E.Tests.LoginFeature.Login_with_invalid_password") | (FullyQualifiedName="E2E.Tests.CheckoutFeature.Checkout_with_empty_cart") | (FullyQualifiedName="E2E.Tests.SearchFeature.Search_with_special_characters"))
✅ Failed tests passed on retry attempt 2
```

## Reqnroll/SpecFlow Considerations

Reqnroll/SpecFlow scenario names are converted to stable test method names:

**TRX contains:**
- `testName`: `"Feature: User Authentication\nScenario: Login with valid credentials"` (display name)
- `testId`: `guid`
- `UnitTest[@id=guid]/TestMethod`: 
  - `className`: `"MyApp.Tests.Features.UserAuthenticationFeature"`
  - `name`: `"LoginWithValidCredentials"`

**We use:** `className.name` → `"MyApp.Tests.Features.UserAuthenticationFeature.LoginWithValidCredentials"`

This ensures:
- ✅ Stable, executable test names
- ✅ Works with special characters in scenario wording
- ✅ Accurate matching in retry filter

## Limitations

- **TRX format required**: Action relies on `.trx` output (default for `dotnet test`)
- **PowerShell Core**: Requires `pwsh` (pre-installed on GitHub hosted runners)
- **NUnit/xUnit/MSTest**: All supported; XML structure is standardized in TRX 2010 schema
- **Parameterized tests**: Each parameter set gets its own `testId`, so retries work correctly

## Migration Guide

### Before (Full Suite Rerun)

```yaml
- name: Run tests with retry
  run: |
    attempt=1
    while [ $attempt -le 3 ]; do
      dotnet test tests/MyApp.Tests/MyApp.Tests.csproj && break
      attempt=$((attempt + 1))
    done
```

### After (Smart Retry)

```yaml
- name: Run tests with smart retry
  uses: ./.github/actions/dotnet-test-retry
  with:
    project: tests/MyApp.Tests/MyApp.Tests.csproj
    max-attempts: 3
```

## See Also

- [web-e2e-deployed.yml](../../workflows/web-e2e-deployed.yml) - Deployed environment E2E tests using this action
- [web-e2e-ci.yml](../../workflows/web-e2e-ci.yml) - CI E2E tests using this action
