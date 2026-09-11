# AUR packaging (maintainer notes)

This directory holds the `-git` AUR package: `readym-wukong-linux-git`. It
tracks the `main` branch of this repo and rebuilds itself against whatever the
latest commit is (`pkgver()` derives `rN.<short-hash>` from `git rev-list` /
`git rev-parse`, the standard scheme for VCS packages).

It ships:

- `usr/bin/readym-wukong`, `usr/bin/readym-uri-handler` — copied verbatim from `bin/`
- `usr/bin/readym-wukong-setup` — this repo's `install.sh`
- `usr/bin/readym-wukong-remove` — this repo's `uninstall.sh`
- desktop entries, `LICENSE`, and the docs, under the usual `/usr/share` paths

## Test a build locally (no AUR account needed)

```bash
cd packaging/aur
makepkg --printsrcinfo > .SRCINFO   # keep this in sync whenever PKGBUILD changes
makepkg -si                          # build + install, asks for sudo to pull deps
```

## Publish / update on the AUR

One-time:

1. Create an AUR account: <https://aur.archlinux.org/register>
2. Add an SSH public key to it (Account → My Account → SSH Public Key).

First publish:

```bash
git clone ssh://aur@aur.archlinux.org/readym-wukong-linux-git.git aur-repo
cp packaging/aur/PKGBUILD packaging/aur/.SRCINFO \
   packaging/aur/readym-wukong-linux-git.install aur-repo/
cd aur-repo
git add -A
git commit -m "initial import"
git push
```

Later updates: repeat the `cp` + regenerate `.SRCINFO` + commit + push. Since
this is a `-git` package, most of the time nothing in `PKGBUILD` itself needs
to change — `pkgver()` picks up new commits from the real repo automatically
on the next `makepkg`/user rebuild.
