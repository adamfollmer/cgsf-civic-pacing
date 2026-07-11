# cgsf-civic-pacing

A [Discourse](https://www.discourse.org/) plugin for [Connect St. Francis](https://connectstfrancis.com): **token-budget pacing** for designated civic categories. Every member gets the same small rolling budget of topics, replies, and likes in paced categories — deliberation over domination, with no karma or reputation mechanics.

## Design principles

- **Equal budgets.** Identical for every member. Staff bypass is the only exception, and staff roles are already visible on their posts.
- **Computed at read time.** Token state is always derived from the event ledger against current settings — no stored balances — so budget changes apply retroactively in both directions.
- **Content-free ledger.** `civic_pacing_events` records *that* a member acted (who, which action, when), never *what* on. Which post someone liked stays private, forever, by schema.
- **Rolling windows.** A token returns the moment its spend ages out — no reset day, no accumulation.
- **Scoped.** Only categories listed in `civic_pacing_paced_categories` spend tokens; the rest of the forum is unlimited.

## Settings

| Setting | Default | |
|---|---|---|
| `civic_pacing_enabled` | `false` | Master switch (ships off) |
| `civic_pacing_paced_categories` | — | Which categories spend tokens |
| `civic_pacing_topic_budget` / `_window_days` | 1 / 5 | New topics per rolling window |
| `civic_pacing_reply_budget` / `_window_days` | 2 / 5 | Replies per rolling window |
| `civic_pacing_like_budget` / `_window_days` | 4 / 5 | Likes per rolling window |

## Install

Add to your `app.yml` under `hooks / after_code / exec / cmd`:

```yaml
- git clone https://github.com/adamfollmer/cgsf-civic-pacing.git
```

then `./launcher rebuild app`.

## Roadmap

- Member-facing "your tokens" card (composer + profile) — currently the state shows via the friendly denial message
- Community-note refund mechanics (arrives with the future notes plugin)

## Development

Specs: `LOAD_PLUGINS=1 bundle exec rspec plugins/cgsf-civic-pacing/spec`

Heritage: this ports the pacing engine from the original Supabase-based Connect St. Francis forum (2026-06), preserving its invariants.
