# STS2_MOD_Master

Repository starter for a future original character MOD for **Slay the Spire 2**.

**Initialization only:** this repository contains documentation and empty source
and asset directories. There is no character implementation, C# project,
compilable skeleton, playable MOD, launcher, or selected MOD framework.
No game or MOD runtime integration has been tested.

## Repository contents

- `src\`: reserved for original or otherwise authorized MOD source.
- `assets\`: reserved for original or otherwise authorized MOD assets.
- `docs\local-development.md`: local reference, save-safety, and publication rules.

No dependencies or SDK installation are required for this documentation-only
starter. Character design and implementation are future work.

## Local workspace boundary

Keep the game, this Git repository, and backups as separate sibling directories:

```text
<workspace>\
  game\       Separately owned local game installation or authorized local copy
  mod\        This Git repository: STS2_MOD_Master
  backup\     Private local backups, never tracked in Git
```

You must separately own and lawfully obtain the game. Its compiled distribution
is not original source and is not included here. The documented reference
baseline is game version `v0.111.0`, targeting `net9.0`; this is not a MOD
compatibility or runtime-integration guarantee.

**A separate executable directory does not isolate game saves.** Before any
future debug or launch workflow uses a live profile, establish and verify save
isolation. Ordinary save backups alone are not isolation.

See [local development and publication rules](docs/local-development.md) for
portable path conventions and the ordinary-save-only backup policy.

## Publication policy

Only original or explicitly authorized MOD source, assets, and related project
documentation belong in Git. Do not add game binaries or reference assemblies,
extracted or decompiled game content, saves, backup manifests, actual
account-folder identifiers, secrets, or machine-local metadata. The external
directory boundary is the primary protection; `.gitignore` is only a safeguard.

No license has been selected for this project. Public repository visibility does
not grant a license to third-party game code or assets, nor does it establish
permission to reuse them. Confirm the rights to any future contribution before
publication.
