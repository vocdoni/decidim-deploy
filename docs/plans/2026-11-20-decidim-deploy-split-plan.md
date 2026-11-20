# decidim-deploy: split from the fork (2026-11-20)

The deploy pipeline (Railway app, z4 updater, CI scripts, the three `vocdoni_*`
workflows) lives in its own repository so that vocdoni/decidim carries only Decidim
plus the elections changes proposed upstream, with upstream's CI unchanged.

Owner decisions: keep the git history (filter of `deploy/` and the `vocdoni_*`
workflows), keep the layout without the `deploy/` prefix, add a bot that follows the
fork pin the way the gem bump follows the gem. Image name, Railway project and the z4
updater stay as they are.

## Steps

1. Filter fork develop (`git filter-repo --path deploy/ --path <3 workflows>
   --path-rename deploy/:`), branch `main`, push as vocdoni/decidim-deploy (public,
   AGPL like Decidim). Nothing runs: the imported workflows trigger on `develop`.
2. PR "Adapt to a standalone repository": paths, `develop` → `main`, `REPO` in
   `deploy-prod.sh`, `Pin bump` (scheduled, gem then Decidim) replacing the
   dispatched gem bump, `io.vocdoni.decidim-revision` image label, CI for the
   scripts, dependabot (security updates, `dompurify` ignored), READMEs.
   Its PR build proves the image builds from `railway/`.
3. Repository setup: labels `needs-review` and `dependencies`; Actions may create
   and approve pull requests and merge commits are allowed (pin bumps open and
   merge PRs with GITHUB_TOKEN); ruleset on `main` (no deletion, no force-push,
   changes through PRs, no required approvals or status checks); GHCR package
   `decidim-vocdoni` grants this repository write (Actions access, UI only);
   environment `production` (tags `prod-*`, owner approval) for parity.
4. Merge the PR: `Image` pushes `sha-<12>` and `:develop` from `main`; decidim-dev
   moves to it within ~2 minutes (same Rails tree as the fork's last build, so no
   migration runs). Check the updater journal and both checks. Disable the fork's
   `vocdoni_image.yml` and `vocdoni_gem_bump.yml` right away, so only this
   repository writes `:develop` (re-enable them to roll back).
5. Run `Pin bump` by hand: both pins are current, so it reports nothing to do.
6. Gem PR: drop `notify_fork.yml`; then delete the `FORK_DISPATCH_TOKEN` secret and
   revoke the token.
7. Fork PR: delete `deploy/` and `.github/workflows/vocdoni_*.yml`.

## Rollback

Until step 7 the fork still holds the old pipeline. If the new image fails its
checks, the updater rolls dev back by itself; to pin dev to the fork's last image:
`decidim-dev-update --ref sha-<fork commit 12>` (timer stopped). Prod is untouched
until the next release, which is cut here; earlier releases roll back from a fork
checkout at their tag (`deploy/railway/deploy-prod.sh <tag>`).
