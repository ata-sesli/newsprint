# Manual Homebrew Release

This project uses a local-machine release flow. There is no GitHub Actions release automation.

Version covered by this guide:

```text
1.0.0
```

## 1. Package the App

From the project root:

```sh
scripts/package-release.sh 1.0.0
```

This creates:

```text
dist/Newsprint.app
dist/Newsprint-1.0.0.zip
```

The script prints the SHA256 checksum and updates:

```text
packaging/homebrew/Casks/newsprint.rb
```

## 2. Verify the App Metadata

```sh
plutil -p dist/Newsprint.app/Contents/Info.plist
```

Confirm:

```text
CFBundleShortVersionString => 1.0.0
LSUIElement => 1
LSMinimumSystemVersion => 14.0
```

## 3. Create and Push the Source Tag

```sh
git tag v1.0.0
git push origin dev
git push origin v1.0.0
```

If the release should come from another branch, push that branch instead of `dev`.

## 4. Create the GitHub Release Manually

Open:

```text
https://github.com/ata-sesli/newsprint/releases/new?tag=v1.0.0
```

Use:

```text
Tag: v1.0.0
Title: Newsprint v1.0.0
```

Upload:

```text
dist/Newsprint-1.0.0.zip
```

Publish the release.

## 5. Create the Homebrew Tap Repo

Create this GitHub repository manually:

```text
ata-sesli/homebrew-newsprint
```

Then clone it locally:

```sh
git clone https://github.com/ata-sesli/homebrew-newsprint.git /tmp/homebrew-newsprint
mkdir -p /tmp/homebrew-newsprint/Casks
cp packaging/homebrew/Casks/newsprint.rb /tmp/homebrew-newsprint/Casks/newsprint.rb
cd /tmp/homebrew-newsprint
git add Casks/newsprint.rb
git commit -m "Add Newsprint cask"
git push origin main
```

## 6. Validate the Cask in the Tap

Homebrew requires cask audit/style checks to run from a tap, not from this source repository's `packaging` folder.

From `/tmp/homebrew-newsprint`:

```sh
brew audit --cask --strict newsprint
brew style --cask Casks/newsprint.rb
```

## 7. Test Install

```sh
brew tap ata-sesli/newsprint
brew install --cask newsprint
```

Confirm the app is installed:

```sh
test -d /Applications/Newsprint.app
```

Confirm quarantine is absent:

```sh
xattr /Applications/Newsprint.app
```

Expected: no `com.apple.quarantine` entry.

Launch:

```sh
open /Applications/Newsprint.app
```

Confirm:

- The menu bar icon appears.
- The dashboard opens from the menu.
- Feed refresh works.
- Quit works from the menu.

## 8. Test Uninstall

```sh
brew uninstall --cask newsprint
brew install --cask newsprint
brew uninstall --cask --zap newsprint
```

The `--zap` uninstall removes Newsprint's local support files.

## Updating Later Versions

For a future version such as `1.0.1`:

```sh
scripts/publish-release.sh 1.0.1
```

This command:

1. Builds `Newsprint.app`.
2. Creates `dist/Newsprint-1.0.1.zip`.
3. Updates the cask `version` and `sha256`.
4. Commits release metadata if packaging changed it.
5. Tags the latest commit as `v1.0.1`.
6. Pushes the current branch and tag.
7. Creates the GitHub Release with `gh`.
8. Uploads the zip.
9. Pulls or clones `/tmp/homebrew-newsprint`.
10. Copies the updated cask into the tap repo.
11. Commits and pushes the tap repo.

Requirements for `scripts/publish-release.sh`:

- `gh` is installed.
- `gh auth login` has been completed.
- `ata-sesli/homebrew-newsprint` already exists.
- The Newsprint working tree is clean before the command starts.

If you only want to build the zip and cask locally without publishing:

```sh
scripts/package-release.sh 1.0.1
```
