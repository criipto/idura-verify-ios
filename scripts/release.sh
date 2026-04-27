#!/usr/bin/env bash
#
# Release a new version of IduraVerify.
#
# Usage: scripts/release.sh --patch | --minor | --major
#
# Example: scripts/release.sh --patch

set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") --patch | --minor | --major

Release a new version of IduraVerify. The new version is computed by
bumping the corresponding component of the current version in
Sources/IduraVerify/Verify.swift.

Flags (exactly one is required):
  --patch   Bump PATCH (X.Y.Z -> X.Y.Z+1)
  --minor   Bump MINOR (X.Y.Z -> X.Y+1.0)
  --major   Bump MAJOR (X.Y.Z -> X+1.0.0)

Steps:
  1. Validate the bump flag.
  2. Verify the working tree is clean and on master, in sync with origin.
  3. Verify the latest CI run on master succeeded.
  4. Compute the new version and update it in Sources/IduraVerify/Verify.swift.
  5. Run swift-format, swiftlint and the test suite.
  6. Commit, tag (unprefixed), and push commit + tag atomically.
  7. Create a GitHub release with auto-generated notes.

Requires: git, gh, swift, xcodebuild.
EOF
}

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 1
fi

case "$1" in
  -h|--help) usage; exit 0 ;;
  --patch|--minor|--major) BUMP="${1#--}" ;;
  *)
    echo "Error: expected exactly one of --patch, --minor, --major (got '$1')." >&2
    usage >&2
    exit 1
    ;;
esac

for cmd in git gh swift xcodebuild; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: required command '$cmd' is not on PATH." >&2
    exit 1
  fi
done

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

VERIFY_FILE="Sources/IduraVerify/Verify.swift"
DESTINATION="name=iPhone 17 Pro"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Error: working tree is not clean. Commit or stash changes first." >&2
  git status --short >&2
  exit 1
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$BRANCH" != "master" ]]; then
  echo "Error: must be on master (currently on '$BRANCH')." >&2
  exit 1
fi

CURRENT_VERSION="$(sed -nE 's/^private let version = "([^"]+)".*/\1/p' "$VERIFY_FILE")"
if [[ -z "$CURRENT_VERSION" ]]; then
  echo "Error: could not find 'private let version = \"...\"' in $VERIFY_FILE." >&2
  exit 1
fi
if [[ ! "$CURRENT_VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "Error: current version '$CURRENT_VERSION' is not plain MAJOR.MINOR.PATCH; bump manually." >&2
  exit 1
fi
MAJOR="${BASH_REMATCH[1]}"
MINOR="${BASH_REMATCH[2]}"
PATCH="${BASH_REMATCH[3]}"

case "$BUMP" in
  patch) PATCH=$((PATCH + 1)) ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
esac
VERSION="$MAJOR.$MINOR.$PATCH"

if git rev-parse --verify --quiet "refs/tags/$VERSION" >/dev/null; then
  echo "Error: tag '$VERSION' already exists locally." >&2
  exit 1
fi

echo "Fetching origin..."
git fetch --tags origin master

if git rev-parse --verify --quiet "refs/tags/$VERSION" >/dev/null; then
  echo "Error: tag '$VERSION' already exists on origin." >&2
  exit 1
fi

LOCAL_SHA="$(git rev-parse HEAD)"
REMOTE_SHA="$(git rev-parse origin/master)"
if [[ "$LOCAL_SHA" != "$REMOTE_SHA" ]]; then
  echo "Error: local master is not in sync with origin/master." >&2
  echo "  local : $LOCAL_SHA" >&2
  echo "  remote: $REMOTE_SHA" >&2
  exit 1
fi

echo "Checking latest CI run on master..."
CI_CONCLUSION="$(gh run list --branch master --limit 1 --json conclusion --jq '.[0].conclusion')"
if [[ "$CI_CONCLUSION" != "success" ]]; then
  echo "Error: latest CI run on master is '${CI_CONCLUSION:-in-progress}', not 'success'." >&2
  exit 1
fi

echo "Bumping version: $CURRENT_VERSION -> $VERSION ($BUMP)"
sed -i '' -E "s/^private let version = \"[^\"]+\"/private let version = \"$VERSION\"/" "$VERIFY_FILE"

NEW_VERSION="$(sed -nE 's/^private let version = "([^"]+)".*/\1/p' "$VERIFY_FILE")"
if [[ "$NEW_VERSION" != "$VERSION" ]]; then
  echo "Error: failed to update version in $VERIFY_FILE." >&2
  exit 1
fi

echo "Running swift format lint..."
swift format lint . -r -s

echo "Running swiftlint..."
swift package plugin --allow-writing-to-package-directory swiftlint lint

echo "Running tests..."
xcodebuild test -quiet -scheme IduraVerify -destination "$DESTINATION"

echo "Committing release..."
git add "$VERIFY_FILE"
git commit -m "Release $VERSION

Bump the hardcoded SDK version in Verify.swift so the value reported as
the idura.sdk.version telemetry attribute matches the released tag."

echo "Tagging $VERSION..."
git tag -a "$VERSION" -m "Release $VERSION"

echo "Pushing commit and tag..."
git push --atomic origin master "refs/tags/$VERSION"

echo "Creating GitHub release..."
gh release create "$VERSION" --title "$VERSION" --generate-notes

echo "Done — released $VERSION."
