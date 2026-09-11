#!/usr/bin/env bash
#
# Rebuilds the AUR package and refreshes the self-hosted pacman repo at
# repo/ (served to end users straight from GitHub, no AUR helper needed).
#
# Run from anywhere; needs: base-devel, git, pacman-contrib (repo-add).
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AUR_DIR="$ROOT/packaging/aur"
REPO_DIR="$ROOT/repo"
REPO_NAME="readym-wukong-linux"

echo "==> Building the package against the latest pushed commit"
( cd "$AUR_DIR" && rm -f -- *.pkg.tar.zst && makepkg -f --noconfirm )

PKGFILE=$(ls -t "$AUR_DIR"/*.pkg.tar.zst | head -n1)
echo "==> Built: $(basename "$PKGFILE")"

mkdir -p "$REPO_DIR"
# drop older builds of the same package so the repo doesn't grow forever
find "$REPO_DIR" -maxdepth 1 -name "${REPO_NAME}*-git-*.pkg.tar.zst" -delete
cp "$PKGFILE" "$REPO_DIR/"

echo "==> Updating the repo database"
( cd "$REPO_DIR" && repo-add "$REPO_NAME.db.tar.gz" "$(basename "$PKGFILE")" )

# repo-add leaves .db/.files as symlinks to the .tar.gz; GitHub's raw server
# hands back a symlink's *target path as text*, not the file it points to,
# which breaks pacman fetching it. Replace them with real copies.
for ext in db files; do
  ln="$REPO_DIR/$REPO_NAME.$ext"
  if [ -L "$ln" ]; then
    target="$(readlink "$ln")"
    cp --remove-destination "$REPO_DIR/$target" "$ln"
  fi
done

# makepkg build litter -- keep only PKGBUILD/.SRCINFO/*.install/README.md in packaging/aur
rm -rf "$AUR_DIR"/src "$AUR_DIR"/pkg "$AUR_DIR"/readym-wukong-linux-git* "$AUR_DIR"/*.pkg.tar.zst

echo
echo "==> Done. Now: cd '$ROOT' && git add repo/ && git commit -m 'repo: publish <version>' && git push"
