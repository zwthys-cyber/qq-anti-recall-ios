# Project constraints

- Target QQ 9.3.86 unless the user changes the target.
- Use GitHub APIs for repository edits. Do not run repository commands, builds, project scripts or tests on the current server.
- Compilation, automated tests, binary inspection and build verification run only in GitHub Actions.
- Do not publish third-party IPA binaries, signing identities, delivery keys or message contents in this public repository or its artifacts/logs.
- Keep real QQ runtime validation separate from synthetic tests and compilation.
- Require exact target version and expected Objective-C ABI before installing hooks. Unsupported targets must preserve QQ behavior.
