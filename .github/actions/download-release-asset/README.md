# Download Release Asset (Composite Action)

Downloads a single asset from a GitHub Release tag.

Inputs:
- `repo` (optional, defaults to current)
- `tag` (required, e.g., v1.2.3)
- `asset_name` (required, e.g., web.zip)
- `token` (required)
- `out_path` (optional, defaults to asset_name)

Example:
```
- uses: ./.github/actions/download-release-asset
  with:
    tag: ${{ inputs.release_tag }}
    asset_name: web.zip
    token: ${{ secrets.GITHUB_TOKEN }}
    out_path: ${{ env.PACKAGE }}
```