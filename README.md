# decidim-deploy

How Vocdoni runs Decidim: the production app behind <https://decidim.vocdoni.dev>
(Railway) and the dev instance <https://decidim-dev.vocdoni.net> (z4), both on one
image, `ghcr.io/vocdoni/decidim-vocdoni`.

The app pins two git sources in `railway/Gemfile.lock`:

- [vocdoni/decidim](https://github.com/vocdoni/decidim) `develop`: Decidim plus the
  elections changes Vocdoni proposes upstream;
- [vocdoni/decidim-secure_elections](https://github.com/vocdoni/decidim-secure_elections)
  `main`: the `decidim-elections-vocdoni` module.

| Path | What |
| --- | --- |
| `railway/` | the Rails app, its `Dockerfile` and the Railway setup; releasing and bumping in [railway/README.md](railway/README.md) |
| `dev/` | the z4 updater that keeps decidim-dev on the newest image ([dev/README.md](dev/README.md)) |
| `ci/` | scripts the workflows run, with their tests |
| `docs/` | design and plans of the pipeline |

## Pipeline

1. `Pin bump` (every 15 minutes) moves either pin to its branch head: merged by itself
   when the bump is mechanical, otherwise a PR labelled `needs-review`.
2. A merge to `main` touching `railway/` makes `Image` push `sha-<12>` and `:develop`.
3. decidim-dev follows `:develop` within ~2 minutes, with checks and automatic rollback.
4. A GitHub release `prod-YYYY.MM.DD` plus `railway/deploy-prod.sh` promotes the same
   image, by digest, to Railway.

Licensed under the AGPL-3.0, like Decidim (`railway/LICENSE-AGPLv3.txt`).
