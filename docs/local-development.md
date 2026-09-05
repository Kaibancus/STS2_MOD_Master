# Local development boundary

## Initialization status and reference baseline

This is a documentation-only starter for a future character MOD. It has no C#
project, compilable skeleton, character implementation, dependency setup, MOD
framework, launcher, or verified game/MOD runtime integration. No build, game
launch, SDK installation, or dependency installation is needed in this phase.

The reference game version is `v0.111.0`, with a managed runtime target of
`net9.0`. These describe a compiled local game distribution, not original source
or a supported MOD API. Future compatibility must be established separately.

Reference assembly names in that external distribution include:

- `data_sts2_windows_x86_64\sts2.dll`
- `data_sts2_windows_x86_64\GodotSharp.dll`
- `data_sts2_windows_x86_64\0Harmony.dll`

These files remain outside Git. This starter does not copy, link, redistribute,
extract, or decompile them. A future integration approach requires separate
implementation and validation; the presence of these assemblies proves neither
compatibility nor permission to redistribute them.

## Portable local directory conventions

Choose a workspace location on your own machine:

```text
<workspace>\
  game\
  mod\
    src\
    assets\
    docs\
  backup\
    normal-saves\
      <snapshot>\
```

`<workspace>`, `<snapshot>`, `<Steam>`, and `<account>` in this document are
placeholders, not actual machine paths or account identifiers. `profileN` means
an ordinary numbered profile directory, not a MOD profile.

The Git root is only `<workspace>\mod`. Keep your separately owned game
installation or authorized local copy at `<workspace>\game`, and private
backups at `<workspace>\backup`. Do not initialize Git at the workspace parent,
move these private directories into the repository, or create links from the
repository to game or backup content.

Future machine-specific paths and configuration must remain untracked.
Do not commit absolute local paths, actual account-folder identifiers, or
environment-specific setup files. `.gitignore` does not remove already tracked
files and can be bypassed by force-adding, so it cannot replace this boundary
or a review of staged content.

## Ordinary-save-only backup policy

Preserve the two ordinary-save locations separately in an external snapshot.
Do not merge them or assume the Steam-side copy matches the AppData copy.

| Source | Ordinary content to preserve |
| --- | --- |
| `%APPDATA%\SlayTheSpire2\steam\<account>` | Ordinary `profileN` directories, account-level `profile.save` and `settings.save`, and their `.backup` variants |
| `%APPDATA%\SlayTheSpire2\default\<account>` | Ordinary settings files and their `.backup` variants, when present |
| `<Steam>\userdata\<account>\2868840\remote` | Ordinary `profileN` directories, root `profile.save` and `settings.save`, and their `.backup` variants |

The first two rows belong to the AppData source group; the third is the
Steam-side source group. Preserve source-relative paths within each group so
identically named files do not overwrite one another.

Exclude `modded`, `mod_data`, MOD configuration and telemetry, logs, runtime
caches, and `remotecache.vdf`. Do not broaden an ordinary-save snapshot into an
entire account-directory or Steam-userdata copy.

Keep snapshot identifiers, source-path manifests, hashes, actual account-folder
identifiers, and all backed-up data under the external backup directory, never
in Git. Verify future snapshots against their included source files while those
files are stable, and retain both source groups rather than selecting one as
authoritative without evidence. No restoration or Steam Cloud changes are part
of this repository initialization.

## Save isolation before future debugging

**A separate executable directory does not isolate game saves.** A copied game
may still access the same AppData profiles, Steam-side data, and cloud-associated
state as another installation.

Before future debugging or launch work uses a live profile, establish and verify
a save-isolation mechanism appropriate to the game version. Determine the actual
read/write destinations and demonstrate that an isolated disposable profile
cannot write to the ordinary live profiles. Do not assume isolation from an
executable path, a backup snapshot, an unverified launch option, or a MOD folder.
Do not use a live profile while isolation is unproven.

This starter provides no isolation implementation and makes no claim of a tested
launch or runtime integration. It does not launch the game, restore saves, or
alter Steam Cloud settings.

## Rules before any publication

Publish only original or explicitly authorized MOD source, source assets, and
related project documentation. Images and audio are not blanket-ignored because
authorized MOD source assets are valid future contributions.

Never stage or publish the game distribution; DLL, EXE, or PCK files; local
reference assemblies; extracted or decompiled game code or assets; save data;
backups or their manifests; actual account-folder identifiers; secrets; or
machine-local configuration and metadata. Do not hide these payloads in
archives or Git history. Do not force-add ignored files.

Review the complete staged diff, tracked paths, and history being pushed before
publication. Ignore rules protect only untracked paths; removing a file from the
latest tree does not remove it from prior commits. If prohibited content is
found, stop publication and resolve it explicitly rather than pushing it or
overwriting an existing remote.

No project license is selected in this starter. Public visibility does not
license third-party assets or grant rights to game code. Establish authorization
and any applicable attribution or license requirements before adding future
source or assets.
