# Releasing Zoe

Releases are automated, as in [maclens](https://github.com/amrakshay/maclens/blob/main/docs/RELEASING.md). You merge pull requests, and CI handles versions and the changelog. Building and publishing the app are added in phase 1 (see "Coming in phase 1").

## How a release happens

1. **Merge PRs to `main`** with [Conventional Commit](https://www.conventionalcommits.org/) titles. PRs are squash-merged, so the title becomes the commit.
   - `fix:` bumps the patch version.
   - `feat:` bumps the minor version (before 1.0 as well).
   - `feat!:` or a `BREAKING CHANGE:` footer bumps the major version (before 1.0 it bumps the minor version, because `bump-minor-pre-major` is on).
   - `docs:`, `chore:`, `ci:`, `refactor:` and `test:` don't trigger a release on their own.
2. **release-please** (`.github/workflows/release.yml`) opens or updates a PR titled `chore(main): release X.Y.Z`. That PR bumps `version.txt` and `.release-please-manifest.json` and prepends the new entries to `CHANGELOG.md`.
3. **Merge that release PR** when you want to ship. It tags `vX.Y.Z` and creates the GitHub Release with the changelog as notes.
   - The PR is opened by the Actions bot, so GitHub holds its CI run. Open the PR's **Checks** tab and click **Approve and run workflows** so the required `build-and-test` check can pass.
   - If you'd rather not approve every time, give release-please a fine-grained personal access token (Contents + Pull requests: read/write on this repo) as the `token:` input.
   - If the release PR ever shows conflicts, delete its branch `release-please--branches--main`. The next push to `main` regenerates it.

The version starts at `0.0.0`; the first `feat:` merged after setup produces `0.1.0`.

## One-time setup

**Repository settings:**
- Settings → Actions → General → Workflow permissions: **Read and write**, and tick **Allow GitHub Actions to create and approve pull requests** (release-please needs this).
- Settings → General → Pull Requests: allow **squash merging** only, with the default commit message set to "Pull request title".
- Settings → Rules → Rulesets: protect `main`. Require a PR, require the `build-and-test` status check, and block force pushes and deletion.
- Settings → Code security: enable **Private vulnerability reporting**, **Secret scanning** and **Push protection**.

## Coming in phase 1

These are tracked in PLAN.md §8 (phase 1) so they aren't forgotten:
- `scripts/build-app.sh` → `dist/Zoe.app` (Info.plist, icon, ad-hoc codesign; build number = CI run number).
- `scripts/package-release.sh` → `Zoe-X.Y.Z.zip` and `.sha256`.
- A self-test target (`swift run zoe-selftest`) and the core's gate policy tests, run in CI.
- `scripts/check-version.sh` extended to the app bundle, zip and cask, as in maclens.
- A build job in `release.yml`: build, package, attest provenance (`actions/attest`), upload to the release.
- Homebrew: `scripts/make-cask.sh`, `scripts/publish-cask.sh`, `.github/workflows/homebrew.yml`, and the cask in `amrakshay/homebrew-tap` (same tap and `HOMEBREW_TAP_TOKEN` setup as maclens), plus the cask lint in CI.
- CodeQL for Swift; Dependabot for Swift packages and the core's Python dependencies.
- **Gatekeeper:** releases are ad-hoc signed and not notarized, so macOS blocks the first launch until **Open Anyway** (README will say so).
