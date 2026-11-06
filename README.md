<div align="center">

<img src="https://raw.githubusercontent.com/livetennisapi/.github/main/profile/banner.jpg" alt="Live Tennis API" width="640">

# livetennisapi for R

**R client for the [Live Tennis API](https://livetennisapi.com).**

Live scores, fixtures, players, rankings, head-to-head records and the 1968 to 2022 results archive, as data frames. Covers the ATP, WTA, Challenger, ITF and junior tours.

[![R-CMD-check](https://github.com/livetennisapi/livetennisapi-r/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/livetennisapi/livetennisapi-r/actions/workflows/R-CMD-check.yaml)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE.md)

[**Website**](https://livetennisapi.com) · [**Documentation**](https://docs.livetennisapi.com) · [**Get a free API key**](https://livetennisapi.com/subscribe/free) · [**Pricing**](https://livetennisapi.com/pricing) · [**Changelog**](https://docs.livetennisapi.com/changelog.html)

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
live[, c("id", "tournament", "players.p1.name", "players.p2.name")]

match_score(live$id[1])

search_players("sinner")
list_fixtures(tour = "wta", limit = 20)
```

The results archive covers 1968 to 2022 and needs the BASIC plan or a history plan:

```r
finals <- archive_matches(tour = "atp", name = "federer", round = "F", level = "G")
head_to_head("djokovic", "nadal")$totals
```

Rankings tables need PRO. Elo ratings and per-player rankings need ULTRA:

```r
rankings(system = "atp", limit = 100)
rankings(system = "elo", tour = "wta", surface = "clay")
```

List endpoints return a data frame with nested fields flattened into columns, such as `players.p1.name`. The response's `meta` is kept as `attr(x, "meta")`. To read a whole filtered set, raise `offset` by `limit` until `attr(x, "meta")$has_more` is `FALSE`. Single resources come back as lists.

## Functions

| Function | Endpoint | Plan |
|---|---|---|
| `api_health()` | `GET /health` | no key |
| `api_usage()` | `GET /usage` | any |
| `live_matches()`, `list_matches()` | `GET /matches` | FREE for live and upcoming |
| `get_match()`, `match_score()` | `GET /matches/{id}`, `/score` | FREE |
| `list_fixtures()` | `GET /fixtures` | FREE |
| `search_players()`, `get_player()` | `GET /players`, `/players/{id}` | FREE |
| `player_stats()` | `GET /players/{id}/stats` | PRO |
| `list_tournaments()`, `get_tournament()` | `GET /tournaments` | FREE |
| `archive_matches()`, `archive_players()`, `archive_career()` | `GET /history/archive/...` | BASIC |
| `head_to_head()` | `GET /h2h` | BASIC |
| `rankings()` | `GET /rankings` | PRO, or ULTRA for Elo and per-player rankings |
| `lta_get()` | any endpoint | depends |

`lta_get()` calls any endpoint in the [API reference](https://docs.livetennisapi.com/reference.html) that has no wrapper yet. Plans and prices are on the [pricing page](https://livetennisapi.com/pricing).

## Errors

A failed call raises a condition of class `lta_error`, with a subclass you can catch on its own:

| Class | When |
|---|---|
| `lta_auth_error` | 401 or 403: the key is missing, wrong or revoked |
| `lta_plan_error` | the endpoint needs a higher plan |
| `lta_rate_limited` | 429: a rate limit or the daily quota was reached |
| `lta_not_found` | 404 |
| `lta_bad_request` | 400: a parameter the API refused |
| `lta_gone` | 410: the record was merged into another, which the body names |

```r
tryCatch(rankings(system = "atp"),
         lta_plan_error = function(e) message("Rankings need the PRO plan"))
```

Each condition carries `status`, `code` (the API's own error code) and `body`. Failed gateway responses (502, 503 and 504) are retried up to three times. A 429 is never retried: read the condition and wait before calling again.

## Other clients

The same API has official clients for [Python](https://github.com/livetennisapi/livetennisapi-python), [JavaScript and TypeScript](https://github.com/livetennisapi/livetennisapi-js), [Go](https://github.com/livetennisapi/livetennisapi-go), [PHP](https://github.com/livetennisapi/livetennisapi-php), [.NET](https://github.com/livetennisapi/livetennisapi-dotnet), [Dart](https://github.com/livetennisapi/livetennisapi-dart) and [Swift](https://github.com/livetennisapi/livetennisapi-swift), and an [MCP server](https://github.com/livetennisapi/livetennisapi-mcp).

## License

MIT. Built by [Live Tennis API](https://livetennisapi.com).
