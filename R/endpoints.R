#' Check the API and your plan
#'
#' `api_health()` needs no key and says whether the API is up.
#' `api_usage()` reports your plan, your limits and what you have used today.
#'
#' @inheritParams lta_get
#' @return A list.
#' @export
#' @examplesIf interactive()
#' api_health()
#' if (nzchar(Sys.getenv("LIVETENNISAPI_KEY"))) api_usage()$tier
api_health <- function() lta_get("/health", auth = FALSE)

#' @rdname api_health
#' @export
api_usage <- function(key = NULL) lta_get("/usage", key = key)

#' List matches
#'
#' `list_matches()` reads matches by lifecycle status. `live_matches()` is the
#' same call with `status = "live"`. Live and upcoming matches are on the free
#' plan. Completed results need a paid plan.
#'
#' @param status One of `"live"`, `"upcoming"`, `"completed"` or `"cancelled"`.
#' @param tour One of `"atp"`, `"wta"`, `"challenger"`, `"itf"` or `"juniors"`.
#' @param draw `"singles"` or `"doubles"`.
#' @param player One or more player ids. A match matches when either side is
#'   one of them.
#' @param tier One or more tier codes, such as `"atp_500"`. See
#'   <https://docs.livetennisapi.com/reference.html> for the list.
#' @param from,to Play dates, as `Date` values or `"YYYY-MM-DD"` strings.
#'   In the results archive they are tournament start dates.
#' @param limit Rows per page.
#' @param offset Rows to skip. To read a whole filtered set, add `limit` to
#'   `offset` until `lta_meta(x)$has_more` is `FALSE`.
#' @param updated_since Read the change feed: rows changed at or after this
#'   time, oldest first. Page it with `cursor`.
#' @param cursor `lta_meta(x)$next_cursor` from the previous change-feed
#'   page.
#' @param ... Other query parameters the endpoint accepts.
#' @inheritParams lta_get
#' @return A tibble, one row per match. Read its paging details with
#'   [lta_meta()].
#' @export
#' @examplesIf nzchar(Sys.getenv("LIVETENNISAPI_KEY"))
#' live <- live_matches(tour = "atp")
#' live[, c("id", "tournament", "players.p1.name", "players.p2.name")]
list_matches <- function(status = "live", tour = NULL, draw = NULL, player = NULL,
                         tier = NULL, from = NULL, to = NULL, limit = NULL,
                         offset = NULL, updated_since = NULL, cursor = NULL, ...,
                         key = NULL) {
  query <- c(list(status = status, tour = tour, draw = draw, player = player,
                  tier = if (is.null(tier)) NULL else paste(tier, collapse = ","),
                  from = from, to = to, limit = limit, offset = offset,
                  updated_since = updated_since, cursor = cursor),
             list(...))
  lta_list("/matches", query, key)
}

#' @rdname list_matches
#' @export
live_matches <- function(tour = NULL, ..., key = NULL) {
  list_matches(status = "live", tour = tour, ..., key = key)
}

#' Read one match
#'
#' `get_match()` returns the full match. `match_score()` returns only the
#' current score, which is the fastest read while a match is live.
#'
#' @param match_id The match id, from [list_matches()].
#' @inheritParams lta_get
#' @return A list.
#' @export
#' @examplesIf nzchar(Sys.getenv("LIVETENNISAPI_KEY"))
#' m <- live_matches()
#' match_score(m$id[1])
get_match <- function(match_id, key = NULL) {
  lta_get(paste0("/matches/", lta_id(match_id)), key = key)
}

#' @rdname get_match
#' @export
match_score <- function(match_id, key = NULL) {
  lta_get(paste0("/matches/", lta_id(match_id), "/score"), key = key)
}

#' Upcoming fixtures
#'
#' Scheduled matches, earliest first.
#'
#' @inheritParams list_matches
#' @return A tibble, one row per fixture.
#' @export
#' @examplesIf nzchar(Sys.getenv("LIVETENNISAPI_KEY"))
#' list_fixtures(tour = "wta", limit = 20)
list_fixtures <- function(tour = NULL, draw = NULL, limit = NULL, offset = NULL, ...,
                          key = NULL) {
  query <- c(list(tour = tour, draw = draw, limit = limit, offset = offset), list(...))
  lta_list("/fixtures", query, key)
}

#' Players
#'
#' `search_players()` finds players by name. `get_player()` returns one
#' player's profile and ranking. `player_stats()` returns a player's record,
#' with filters for dates, surface and level, and needs a paid plan.
#'
#' @param search A name or part of one.
#' @param player_id The player id.
#' @param surface `"hard"`, `"clay"`, `"grass"` or `"indoor"`.
#' @param level A tour code, as in [list_matches()].
#' @param last Only the most recent matches, this many.
#' @inheritParams list_matches
#' @return `search_players()` returns a tibble. The others return lists.
#' @export
#' @examplesIf nzchar(Sys.getenv("LIVETENNISAPI_KEY"))
#' p <- search_players("alcaraz")
#' get_player(p$id[1])
search_players <- function(search, limit = NULL, offset = NULL, key = NULL) {
  lta_list("/players", list(search = search, limit = limit, offset = offset), key)
}

#' @rdname search_players
#' @export
get_player <- function(player_id, key = NULL) {
  lta_get(paste0("/players/", lta_id(player_id)), key = key)
}

#' @rdname search_players
#' @export
player_stats <- function(player_id, from = NULL, to = NULL, surface = NULL,
                         level = NULL, last = NULL, key = NULL) {
  query <- list(from = from, to = to, surface = surface, level = level, last = last)
  lta_get(paste0("/players/", lta_id(player_id), "/stats"), query, key = key)
}

#' Tournaments
#'
#' `list_tournaments()` searches the tournament catalogue. `get_tournament()`
#' returns one tournament by its stable id.
#'
#' @param tournament_id The tournament id.
#' @inheritParams list_matches
#' @inheritParams search_players
#' @return `list_tournaments()` returns a tibble, `get_tournament()` a list.
#' @export
#' @examplesIf nzchar(Sys.getenv("LIVETENNISAPI_KEY"))
#' list_tournaments(search = "open", tier = "grand_slam")
list_tournaments <- function(search = NULL, tour = NULL, draw = NULL, tier = NULL,
                             limit = NULL, offset = NULL, key = NULL) {
  query <- list(search = search, tour = tour, draw = draw,
                tier = if (is.null(tier)) NULL else paste(tier, collapse = ","),
                limit = limit, offset = offset)
  lta_list("/tournaments", query, key)
}

#' @rdname list_tournaments
#' @export
get_tournament <- function(tournament_id, key = NULL) {
  lta_get(paste0("/tournaments/", lta_id(tournament_id)), key = key)
}

#' The results archive, 1968 to 2022
#'
#' `archive_matches()` searches past results. `archive_players()` returns
#' player bios. `archive_career()` sums one player's career over the archive.
#' These need a paid plan, from Basic up.
#'
#' @param name A player name, or part of one (at least three characters for
#'   `archive_career()`).
#' @param tour `"atp"` or `"wta"`.
#' @param round A round code such as `"F"` or `"QF"`.
#' @param level A level code such as `"G"` for a Grand Slam.
#' @param offset Rows to skip, for paging.
#' @inheritParams list_matches
#' @return `archive_matches()` and `archive_players()` return tibbles.
#'   `archive_career()` returns a list.
#' @export
#' @examplesIf nzchar(Sys.getenv("LIVETENNISAPI_KEY"))
#' archive_matches(tour = "atp", name = "federer", round = "F", level = "G")
archive_matches <- function(tour = NULL, name = NULL, from = NULL, to = NULL,
                            round = NULL, level = NULL, limit = NULL, offset = NULL,
                            key = NULL) {
  query <- list(tour = tour, name = name, from = from, to = to, round = round,
                level = level, limit = limit, offset = offset)
  lta_list("/history/archive/matches", query, key)
}

#' @rdname archive_matches
#' @export
archive_players <- function(name = NULL, tour = NULL, limit = NULL, offset = NULL,
                            key = NULL) {
  query <- list(name = name, tour = tour, limit = limit, offset = offset)
  lta_list("/history/archive/players", query, key)
}

#' @rdname archive_matches
#' @export
archive_career <- function(name, key = NULL) {
  lta_get("/history/archive/career", list(name = name), key = key)
}

#' Head-to-head record
#'
#' Every meeting between two players across the results archive and recent
#' matches, with totals and a split by surface.
#'
#' @param p1,p2 Player names, or parts of them (at least three characters).
#' @inheritParams lta_get
#' @return A list with `totals`, `by_surface` and `meetings`.
#' @export
#' @examplesIf nzchar(Sys.getenv("LIVETENNISAPI_KEY"))
#' h2h <- head_to_head("djokovic", "nadal")
#' h2h$totals
head_to_head <- function(p1, p2, key = NULL) {
  lta_get("/h2h", list(p1 = p1, p2 = p2), key = key)
}

#' Rankings and Elo ratings
#'
#' With no `player`, returns the rank-ordered table for one official `system`.
#' With `player`, returns the ranking records those players held at `as_of`.
#' Elo ratings (`system = "elo"` with a `tour`) come in four ladders:
#' `"overall"`, `"hard"`, `"clay"` and `"grass"`. The plan each mode needs is
#' on the pricing page, <https://livetennisapi.com/pricing>.
#'
#' @param system One or more of `"atp"`, `"wta"`, `"atp_doubles"`,
#'   `"wta_doubles"`, `"itf_mt"`, `"itf_wt"`, `"itf_jt"`, `"utr"` or `"elo"`.
#' @param tour `"atp"` or `"wta"`.
#' @param surface The Elo ladder.
#' @param player One or more player ids.
#' @param as_of The date the records must be in force on, as a `Date` or a
#'   `"YYYY-MM-DD"` string. The API's default is today.
#' @inheritParams list_matches
#' @return A tibble, one row per ranking record.
#' @export
#' @examplesIf nzchar(Sys.getenv("LIVETENNISAPI_KEY"))
#' rankings(system = "atp", limit = 100)
#' rankings(system = "elo", tour = "wta", surface = "clay")
rankings <- function(system = NULL, tour = NULL, surface = NULL, player = NULL,
                     as_of = NULL, limit = NULL, offset = NULL, ..., key = NULL) {
  query <- c(list(system = system, tour = tour, surface = surface, player = player,
                  as_of = as_of, limit = limit, offset = offset),
             list(...))
  lta_list("/rankings", query, key)
}
