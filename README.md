# millriverct-website

Welcome / landing site for **[www.millriverct.com](https://www.millriverct.com)** — a static
site about Mill River in Southport, Connecticut and its historic tide-powered grist mill.

## Stack

- Plain static HTML + CSS — **no build step**.
- Deployed by **Cloudflare Pages** (build output = repository root).
- Custom domain `www.millriverct.com` managed in Cloudflare.

## Local preview

```sh
npx serve .
# or
python -m http.server 8080
```

Then open <http://localhost:8080>.

## Source control topology

```
            git push  (one command)
                |
        +-------+-------+
        v               v
   Gitea (local)    GitHub (origin mirror)
                        |
                        v
              Cloudflare Pages  --build & deploy-->  www.millriverct.com
```

- A single `git push` writes to **both** Gitea (on-prem) and GitHub via a multi-URL remote.
- **Cloudflare Pages pulls from GitHub** and auto-deploys every push to `main`.

## Files

| File | Purpose |
|------|---------|
| `index.html` | The welcome page |
| `styles.css` | Styling |
| `README.md` | This file |

## History sources

- Mill River (Fairfield, CT) — Wikipedia
- Sturges Tide Mill — ConnecticutMills.org
- Southport Historic District — Wikipedia
- Southport, Connecticut — NewEngland.com
