# Self-hosted pacman repo

`repo/` at the root of this project **is** a real pacman repository — its
database (`readym-wukong-linux.db`) and the built `.pkg.tar.zst` are committed
straight into git and served to users via `raw.githubusercontent.com`. This is
what lets `sudo pacman -S readym-wukong-linux-git` work with no AUR helper.

## Updating it after a change

```bash
packaging/repo/update-repo.sh
git add repo/
git commit -m "repo: publish rN.<hash>"
git push
```

That's it — `update-repo.sh` rebuilds the package from the latest pushed
commit (via the AUR `PKGBUILD`, so both distribution channels always match),
refreshes the repo database, and fixes up the `repo-add`-generated symlinks
(GitHub's raw server returns a symlink's *target path as text*, not the file
it points to, which breaks pacman — see the script for details).

## Why unsigned (`SigLevel = Optional TrustAll`)

Signing packages needs a maintained GPG key and users importing it, which is
real ongoing key-management overhead for what is, realistically, a small
community project. If that trade-off stops being acceptable at some point,
sign the packages (`makepkg --sign`, `repo-add -s`) and change the README's
`SigLevel` instructions to `Required`.
