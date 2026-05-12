# mani AUR packaging automation

This repository packages the stable `mani` release for the Arch User Repository.

The intended workflow is:

1. Mirror this repository to GitHub as `mikeboiko/mani-aur`.
2. Let GitHub Actions poll upstream `alajmo/mani` releases.
3. Update `PKGBUILD` and `.SRCINFO` when a new upstream release is published.
4. Validate the packaging metadata in CI.
5. Push a clean AUR tree back to `aur.archlinux.org/mani.git`.

## Repository layout

- `PKGBUILD` and `.SRCINFO` are the AUR payload.
- `.github/workflows/update-aur-package.yml` is the GitHub Actions automation for the mirror repo.
- `scripts/update-upstream-release.sh` updates `pkgver`, `_commit`, and `.SRCINFO`.
- `scripts/validate-package.sh` runs packaging validation locally or in CI.
- `scripts/publish-aur-tree.sh` pushes only the AUR payload to the AUR remote.

The AUR publish step intentionally sends only `PKGBUILD` and `.SRCINFO`. That keeps the AUR repo clean while the GitHub mirror can still hold workflow files, helper scripts, and documentation.

## Required GitHub setup

Create a dedicated GitHub repository for this package, such as `mikeboiko/mani-aur`, and push this repository there. The workflow is meant to run from that mirror, not from the upstream `mikeboiko/mani` source fork.

## Required secrets

| Secret | Purpose |
| --- | --- |
| `AUR_SSH_PRIVATE_KEY` | SSH private key for the AUR maintainer account. Its matching public key must be added to the AUR account that maintains `mani`. |

The workflow uses the built-in `GITHUB_TOKEN` for the GitHub mirror commit and push.

## AUR SSH key setup

1. Generate a dedicated key pair for AUR automation, for example `ssh-keygen -t ed25519 -f mani-aur`.
2. Add the public key to the AUR account that maintains the `mani` package.
3. Store the private key in the GitHub mirror as the `AUR_SSH_PRIVATE_KEY` secret.

The workflow uses the pinned host keys in `.github/aur-known_hosts`. If `aur.archlinux.org` rotates host keys, refresh that file before rerunning the workflow.

## Workflow behavior

The update workflow runs every 6 hours and through `workflow_dispatch`. Manual runs expose:

- `full_build` to force a complete package build even when upstream is already current.
- `publish_current` to attempt an AUR sync of the current `PKGBUILD` and `.SRCINFO` without waiting for a new upstream release.
- The workflow uses Node 24-compatible GitHub Actions dependencies so scheduled runs do not rely on the deprecated Node 20 runner path.

When a new upstream release is found, it:

1. Resolves the release tag to a commit SHA.
2. Updates `pkgver` and `_commit` in `PKGBUILD`.
3. Resets `pkgrel` to `1` for a new upstream version.
4. Increments `pkgrel` if the upstream tag moves without a version change.
5. Regenerates `.SRCINFO`.
6. Validates the package metadata with `makepkg`, `makepkg --verifysource`, and `namcap`.
7. Commits the packaging update to the GitHub mirror.
8. Pushes a clean AUR tree containing only `PKGBUILD` and `.SRCINFO` to `aur.archlinux.org`.

For manual runs, `full_build` and `publish_current` let the workflow exercise the current package state even when there is no new upstream release. If the AUR tree already matches, the publish step exits cleanly without creating a new AUR commit.

## Manual usage

Update to the latest upstream release:

```bash
./scripts/update-upstream-release.sh
```

Preview the next release update without changing files:

```bash
./scripts/update-upstream-release.sh --dry-run
```

Validate packaging metadata:

```bash
./scripts/validate-package.sh
```

Run validation and build the package locally:

```bash
./scripts/validate-package.sh --build
```

Publish the current `PKGBUILD` and `.SRCINFO` to AUR using the configured SSH identity:

```bash
./scripts/publish-aur-tree.sh
```

## Extending the AUR payload

If the package later needs patch files, `.install` files, or other AUR-tracked sources, add them to the `scripts/publish-aur-tree.sh` invocation in the GitHub Actions workflow so they are copied into the published AUR tree.
