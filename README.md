<div align="center">

<img src="https://raw.githubusercontent.com/livetennisapi/.github/main/profile/banner.jpg" alt="Live Tennis API" width="640">

# livetennisapi for R

**Live tennis scores, fixtures, players and rankings from the [Live Tennis API](https://livetennisapi.com), as tibbles.**

Covers the ATP, WTA, Challenger and ITF tours, plus head-to-head records and the 1968 to 2022 results archive.

[![R-CMD-check](https://github.com/livetennisapi/livetennisapi-r/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/livetennisapi/livetennisapi-r/actions/workflows/R-CMD-check.yaml)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE.md)

[**Website**](https://livetennisapi.com) · [**Documentation**](https://docs.livetennisapi.com) · [**Pricing**](https://livetennisapi.com/pricing) · [**Changelog**](https://docs.livetennisapi.com/changelog.html) · [**Get a free API key**](https://livetennisapi.com/subscribe/free)

</div>

---

## Install

```r
# install.packages("remotes")
remotes::install_github("livetennisapi/livetennisapi-r")
```

## Set your key

Get a free key at [livetennisapi.com/subscribe/free](https://livetennisapi.com/subscribe/free). No card is needed. Put it in `~/.Renviron` so every session has it:

```
LIVETENNISAPI_KEY=twjp_...
```

You can also pass `key` to any function that needs one. It wins over the environment.

## Use

```r
library(livetennisapi)

live <- live_matches(tour = "atp")
if (nrow(live) > 0) {
  print(live[, c("id", "tournament", "players.p1.name", "players.p2.name")])
  match_score(live$id[1])
}

search_players("sinner")
list_fixtures(tour = "wta", limit = 20)
```

The results archive (1968 to 2022) and head-to-head records are on the Basic plan and up:

```r
finals <- archive_matches(tour = "atp", name = "federer", round = "F", level = "G")
head_to_head("djokovic", "nadal")$totals
```

Ranking tables are on the Pro plan and up. Elo ratings and per-player records come in through the same function:

```r
rankings(system = "atp", limit = 100)
rankings(system = "elo", tour = "wta", surface = "clay")
```

List endpoints return a tibble with nested fields flattened into columns, such as `players.p1.name`. `lta_meta(x)` returns the paging details. To read a whole filtered set, raise `offset` by `limit` until `lta_meta(x)$has_more` is `FALSE`. Single resources come back as lists.

## Functions

| Function | Endpoint | Returns |
|---|---|---|
| `api_health()` | `GET /health` (no key) | list |
| `api_usage()` | `GET /usage` | list |
| `live_matches()`, `list_matches()` | `GET /matches` | tibble |
| `get_match()`, `match_score()` | `GET /matches/{id}`, `/score` | list |
| `list_fixtures()` | `GET /fixtures` | tibble |
| `search_players()` | `GET /players` | tibble |
| `get_player()`, `player_stats()` | `GET /players/{id}`, `/stats` | list |
| `list_tournaments()` | `GET /tournaments` | tibble |
| `get_tournament()` | `GET /tournaments/{id}` | list |
| `archive_matches()`, `archive_players()` | `GET /history/archive/...` | tibble |
| `archive_career()` | `GET /history/archive/career` | list |
| `head_to_head()` | `GET /h2h` | list |
| `rankings()` | `GET /rankings` | tibble |
| `lta_get()` | any endpoint | list |

The free plan opens live and upcoming matches, scores, players, fixtures and tournaments, at 30 requests a minute and 100 a day. Each paid plan adds more, and the [pricing page](https://livetennisapi.com/pricing) lists what each one opens. A call your plan does not cover raises `lta_plan_error`.

`lta_get()` calls any endpoint in the [API reference](https://docs.livetennisapi.com/reference.html) that has no wrapper yet.

## Errors

A failed call raises a condition of class `lta_error`, with a subclass you can catch on its own:

| Class | When |
|---|---|
| `lta_auth_error` | 401: the key is missing, wrong or revoked |
| `lta_plan_error` | 403: the endpoint needs a higher plan |
| `lta_rate_limited` | 429: a rate limit or the daily quota was reached |
| `lta_abuse_throttled` | 429 `abuse_throttled`: a 24-hour block, also an `lta_rate_limited` |
| `lta_not_found` | 404 |
| `lta_bad_request` | 400: a parameter the API refused |
| `lta_gone` | 410: the record was merged into another, which the body names |
| `lta_connection_error` | the API could not be reached, after three tries |
| `lta_http_error` | any other failure, such as a 5xx after three tries |

```r
tryCatch(rankings(system = "atp"),
         lta_plan_error = function(e) message("Rankings need the PRO plan"))
```

Each condition carries `status`, `code` (the API's own error code), `body` and `retry_after`.

A call is tried up to three times, each with a 30-second timeout. Dropped connections, timeouts, server errors (5xx) and the per-minute 429 are retried. The client waits what the `Retry-After` header asks for, up to a minute, or backs off briefly when there is no header. The daily-quota 429 and `abuse_throttled` are raised straight away, because neither clears in seconds. The Python and JavaScript clients follow the same policy.

## Other clients

The same API has official clients for [Python](https://github.com/livetennisapi/livetennisapi-python), [JavaScript and TypeScript](https://github.com/livetennisapi/livetennisapi-js), [Go](https://github.com/livetennisapi/livetennisapi-go), [PHP](https://github.com/livetennisapi/livetennisapi-php), [.NET](https://github.com/livetennisapi/livetennisapi-dotnet), [Dart](https://github.com/livetennisapi/livetennisapi-dart) and [Swift](https://github.com/livetennisapi/livetennisapi-swift), and an [MCP server](https://github.com/livetennisapi/livetennisapi-mcp).

## Changes

Package releases are listed in [NEWS.md](NEWS.md). Changes to the API itself are in the [API changelog](https://docs.livetennisapi.com/changelog.html).

## License

MIT. Built by [Live Tennis API](https://livetennisapi.com).
