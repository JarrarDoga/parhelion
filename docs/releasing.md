# Releasing

Parhelion uses [Semantic Versioning](https://semver.org). Before 1.0, a minor version can contain
breaking changes, and the changelog lists them under **Changed** or **Removed**.

## Labels

Release notes are generated from pull request labels by
[`.github/release.yml`](../.github/release.yml). Label every pull request before you merge it:

| Label | Section in the release notes |
| --- | --- |
| `breaking` | Breaking changes |
| `enhancement` | New features |
| `bug` | Bug fixes |
| `documentation` | Documentation |
| `ignore-for-release` | Not listed |

Pull requests with any other label appear under *Other changes*.

## Cutting a release

1. Make sure CI passes on `main`.
2. In `CHANGELOG.md`, rename `Unreleased` to the new version and date, for example
   `## [0.1.0] - 2026-11-02`. Add a new empty `Unreleased` section and update the links at the
   bottom of the file.
3. Commit the change: `git commit -am "Release 0.1.0"`.
4. Create an annotated tag and push it:

   ```console
   $ git tag -a v0.1.0 -m "Parhelion 0.1.0"
   $ git push origin main v0.1.0
   ```

5. The [release workflow](../.github/workflows/release.yml) runs the tests at the tag and
   publishes a GitHub release with generated notes. Review the release page, and add a short
   summary at the top of the notes.
