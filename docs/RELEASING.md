# Releasing Zoe

Releases are automated, as in [maclens](https://github.com/amrakshay/maclens/blob/main/docs/RELEASING.md). You merge pull requests, and CI handles versions and the changelog. CI builds the app, attests it, attaches it to the release and updates the Homebrew cask.

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

## What a release builds

The `build` job in `release.yml` runs on macos-26 when a release is created:
1. Core tests and `swift run zoe-selftest`.
2. `scripts/build-app.sh` → `dist/Zoe.app`: the release binary (ONNX Runtime and WhisperKit are linked in), the core's source and `core/launch.sh` in `Contents/Resources/core`, the icon, an Info.plist with the Microphone and Speech Recognition usage strings, and an ad-hoc signature. The build number is the workflow's run number.
3. `scripts/package-release.sh` → `Zoe-X.Y.Z.zip`, its `.sha256` and the cask `dist/zoe.rb`.
4. `scripts/check-version.sh vX.Y.Z`: the tag, `version.txt`, the app, the zip and the cask agree.
5. Build provenance (`actions/attest`), upload to the release, then the cask update (once the tap token exists).

CI runs steps 2–4 on every PR too, starts the bundled core with the echo brain, checks the signature is still intact afterwards, and lints the cask (`brew style` and `brew audit`).

**How the installed app runs the core:** the app starts `Contents/Resources/core/launch.sh`. It runs `uv sync --frozen --no-dev` into `~/Library/Application Support/Zoe/core-venv` (instant when nothing changed; the first run downloads Python and the dependencies, about 400 MB with the Claude Code CLI the Agent SDK ships), then replaces itself with the core. Nothing is written into the signed bundle. That's why the cask depends on `uv`.

## Homebrew tap setup

**Not set up yet:** releases currently ship the zip only (the release job skips the tap while `HOMEBREW_TAP_TOKEN` is missing), and the README tells users to download it from Releases. When the tap is set up, switch the README's install section back to `brew install --cask amrakshay/tap/zoe`.

Zoe uses the same tap as maclens, `amrakshay/homebrew-tap` (cask `Casks/zoe.rb`). The main `homebrew/cask` repo only accepts notarized apps.

One-time setup:
1. **Token.** Reuse maclens's fine-grained token if it's limited to `homebrew-tap` with Contents read/write, or create one the same way (GitHub → Settings → Developer settings → Fine-grained tokens; only `homebrew-tap`; Contents → Read and write).
2. **Store it in this repo:** Settings → Secrets and variables → Actions → New repository secret → **`HOMEBREW_TAP_TOKEN`**.
3. **Publish an existing release once** if it was made before the secret existed: Actions → **Publish Homebrew cask** → tag. Later releases update the cask automatically.

Users install and update with:

```bash
brew install --cask amrakshay/tap/zoe
```

```bash
brew upgrade --cask zoe
```

To change the cask (description, caveats, `depends_on`), edit `scripts/make-cask.sh`; the next release carries it.

**Gatekeeper:** releases are ad-hoc signed and not notarized, so macOS blocks the first launch until **Open Anyway** (the cask's caveats and the README say so). Each update has a new ad-hoc signature, so macOS may ask for Microphone and Accessibility again after an update.

## Building a release locally

```bash
./scripts/build-app.sh && ./scripts/package-release.sh && ./scripts/check-version.sh
```

**Keeping permissions across your own rebuilds.** Each ad-hoc build is a new identity to macOS, so Accessibility (and sometimes Microphone) must be granted again; removing and re-adding Zoe in System Settings may not be enough. If that happens: `tccutil reset Accessibility io.github.amrakshay.zoe`, launch Zoe, grant at the prompt, relaunch. To avoid it, sign your builds with a self-signed identity:
1. Keychain Access → Certificate Assistant → Create a Certificate… → Name `Zoe Dev`, Identity Type **Self-Signed Root**, Certificate Type **Code Signing**.
2. Build with `ZOE_SIGN_IDENTITY="Zoe Dev" ./scripts/build-app.sh`. Grants then survive rebuilds signed with the same certificate.
