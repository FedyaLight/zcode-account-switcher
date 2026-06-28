# Security

Account snapshots contain ZCode login tokens. Do not attach snapshots,
`credentials.json`, `config.json`, exported account archives, logs with tokens,
or local environment files to public issues.

If you need to report a security-sensitive problem, open a private advisory or
contact the maintainer privately instead of filing a public issue with secrets.

Before sharing diagnostics, remove:

- `~/Library/Application Support/ZCode Account Switcher/accounts`
- `~/Library/Application Support/ZCode Account Switcher/.last`
- `~/.zcode/v2/credentials.json`
- `~/.zcode/v2/config.json`
- any exported account files
