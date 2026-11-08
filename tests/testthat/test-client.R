test_that("the key comes from LIVETENNISAPI_KEY and a missing key is a typed error", {
  old <- Sys.getenv("LIVETENNISAPI_KEY", NA)
  on.exit(if (is.na(old)) Sys.unsetenv("LIVETENNISAPI_KEY") else Sys.setenv(LIVETENNISAPI_KEY = old))
  Sys.unsetenv("LIVETENNISAPI_KEY")
  expect_error(lta_key(), class = "lta_auth_error")
  Sys.setenv(LIVETENNISAPI_KEY = "twjp_abc")
  expect_equal(lta_key(), "twjp_abc")
})

test_that("requests carry the bearer key, a user agent and the query", {
  seen <- NULL
  httr2::local_mocked_responses(function(req) {
    seen <<- req
    json_response(list(data = list(), meta = list()))
  })
  with_key(list_matches(status = "upcoming", tour = "atp", player = c(1, 2),
                        from = as.Date("2026-11-01"), limit = 5))
  expect_equal(auth_header(seen), "Bearer twjp_test")
  expect_match(seen$options$useragent, "^livetennisapi-r/")
  url <- seen$url
  expect_match(url, "/matches\\?")
  expect_match(url, "status=upcoming")
  expect_match(url, "tour=atp")
  expect_match(url, "player=1&player=2")
  expect_match(url, "from=2026-11-01")
  expect_false(grepl("draw=", url))
})

test_that("logicals are sent as true and false", {
  expect_equal(lta_query(list(a = TRUE, b = FALSE, c = NULL, d = NA)),
               list(a = "true", b = "false"))
})

test_that("an explicit key wins over the environment", {
  seen <- NULL
  httr2::local_mocked_responses(function(req) {
    seen <<- req
    json_response(list(principal = "x", tier = "free"))
  })
  with_key(api_usage(key = "twjp_other"))
  expect_equal(auth_header(seen), "Bearer twjp_other")
})

test_that("api_health sends no key", {
  seen <- NULL
  httr2::local_mocked_responses(function(req) {
    seen <<- req
    json_response(list(status = "ok", version = "1"))
  })
  old <- Sys.getenv("LIVETENNISAPI_KEY", NA)
  on.exit(if (is.na(old)) Sys.unsetenv("LIVETENNISAPI_KEY") else Sys.setenv(LIVETENNISAPI_KEY = old))
  Sys.unsetenv("LIVETENNISAPI_KEY")
  expect_equal(api_health()$status, "ok")
  expect_null(auth_header(seen))
})

test_that("list endpoints return a flattened tibble with meta", {
  httr2::local_mocked_responses(function(req) {
    json_response(list(
      data = list(
        list(id = 1, tournament = "Paris", players = list(p1 = list(name = "A"), p2 = list(name = "B"))),
        list(id = 2, tournament = "Metz", players = list(p1 = list(name = "C"), p2 = list(name = "D")))
      ),
      meta = list(next_cursor = "abc")
    ))
  })
  out <- with_key(live_matches())
  expect_s3_class(out, "tbl_df")
  expect_equal(nrow(out), 2)
  expect_equal(out$players.p1.name, c("A", "C"))
  expect_equal(lta_meta(out)$next_cursor, "abc")
})

test_that("an empty list is an empty tibble", {
  httr2::local_mocked_responses(function(req) json_response(list(data = list(), meta = list())))
  out <- with_key(list_fixtures())
  expect_s3_class(out, "tbl_df")
  expect_equal(nrow(out), 0)
})

test_that("errors raise typed conditions with the API's code", {
  cases <- list(
    list(401L, "unauthorized", "lta_auth_error"),
    list(403L, "upgrade_required", "lta_plan_error"),
    list(404L, "not_found", "lta_not_found"),
    list(400L, "bad_tour", "lta_bad_request"),
    list(429L, "rate_limited", "lta_rate_limited")
  )
  for (cs in cases) {
    httr2::local_mocked_responses(function(req) {
      json_response(list(error = cs[[2]], detail = "why"), status = cs[[1]])
    })
    err <- tryCatch(with_key(get_match(1)), lta_error = function(e) e)
    expect_s3_class(err, cs[[3]])
    expect_equal(err$status, cs[[1]])
    expect_equal(err$code, cs[[2]])
    expect_match(conditionMessage(err), "why")
  }
})

test_that("5xx and the per-minute 429 are transient; the daily cap and abuse block are not", {
  expect_true(lta_transient(httr2::response(status_code = 500L)))
  expect_true(lta_transient(httr2::response(status_code = 503L)))
  expect_true(lta_transient(json_response(list(error = "rate_limited"), status = 429L)))
  expect_false(lta_transient(json_response(list(error = "rate_limited", scope = "day"),
                                           status = 429L)))
  expect_false(lta_transient(json_response(list(error = "abuse_throttled"), status = 429L)))
  for (code in c(400L, 401L, 403L, 404L, 410L)) {
    expect_false(lta_transient(httr2::response(status_code = code)))
  }
})

test_that("Retry-After is honoured and capped at a minute", {
  hdr <- function(v) httr2::response(status_code = 429L, headers = list(`Retry-After` = v))
  expect_equal(lta_retry_after(hdr("7")), 7)
  expect_equal(lta_retry_after(hdr("3600")), 60)
  expect_true(is.na(lta_retry_after(hdr("soon"))))
  expect_true(is.na(lta_retry_after(httr2::response(status_code = 429L))))
  expect_lte(lta_backoff(10), 10)
  expect_gte(lta_backoff(1), 0.5)
})

test_that("a per-minute 429 is retried and the next answer is returned", {
  waits <- numeric()
  local_mocked_bindings(lta_sleep = function(seconds) waits <<- c(waits, seconds))
  calls <- 0L
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    if (calls == 1L) {
      json_response(list(error = "rate_limited"), status = 429L,
                    headers = list(`Retry-After` = "7"))
    } else {
      json_response(list(data = list(list(id = 5)), meta = list(has_more = FALSE)))
    }
  })
  out <- with_key(live_matches())
  expect_equal(calls, 2L)
  expect_equal(waits, 7)
  expect_equal(out$id, 5)
})

test_that("the daily-cap 429 is raised at once with its Retry-After", {
  local_mocked_bindings(lta_sleep = function(seconds) stop("must not wait"))
  calls <- 0L
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    json_response(list(error = "rate_limited", scope = "day"), status = 429L,
                  headers = list(`Retry-After` = "3600"))
  })
  err <- tryCatch(with_key(live_matches()), lta_error = function(e) e)
  expect_equal(calls, 1L)
  expect_s3_class(err, "lta_rate_limited")
  expect_equal(err$retry_after, "3600")
})

test_that("a 5xx is tried three times, then raised", {
  waits <- numeric()
  local_mocked_bindings(lta_sleep = function(seconds) waits <<- c(waits, seconds))
  calls <- 0L
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    json_response(list(error = "upstream"), status = 503L)
  })
  expect_error(with_key(get_match(1)), class = "lta_http_error")
  expect_equal(calls, 3L)
  expect_length(waits, 2L)
})

test_that("a 4xx is never retried", {
  local_mocked_bindings(lta_sleep = function(seconds) stop("must not wait"))
  calls <- 0L
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    json_response(list(error = "bad_tour"), status = 400L)
  })
  expect_error(with_key(get_match(1)), class = "lta_bad_request")
  expect_equal(calls, 1L)
})

test_that("a dropped connection is retried, then raised as lta_connection_error", {
  local_mocked_bindings(lta_sleep = function(seconds) NULL)
  calls <- 0L
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    stop(structure(class = c("httr2_failure", "httr2_error", "error", "condition"),
                   list(message = "Could not resolve host", call = NULL)))
  })
  err <- tryCatch(with_key(get_match(1)), lta_error = function(e) e)
  expect_s3_class(err, "lta_connection_error")
  expect_equal(calls, 3L)
  expect_match(conditionMessage(err), "Could not resolve host")
})

test_that("round-number ids never go out in scientific notation", {
  seen <- NULL
  httr2::local_mocked_responses(function(req) {
    seen <<- req
    json_response(list(id = 100000))
  })
  with_key(get_player(100000))
  expect_match(seen$url, "/players/100000$")
  with_key(list_matches(player = 1e5))
  expect_match(seen$url, "player=100000")
})

test_that("list rows keep full numeric precision", {
  httr2::local_mocked_responses(function(req) {
    json_response(list(data = list(list(id = 1, p = 0.123456789)), meta = list()))
  })
  out <- with_key(live_matches())
  expect_equal(out$p, 0.123456789)
})

test_that("rows with different shapes still make one data frame", {
  httr2::local_mocked_responses(function(req) {
    json_response(list(data = list(
      list(id = 1, surface = "clay", players = list(p1 = list(name = "A"))),
      list(id = 2, players = list(p1 = list(name = "B"), p2 = list(name = "C")))
    ), meta = list(has_more = FALSE)))
  })
  out <- with_key(live_matches())
  expect_equal(nrow(out), 2)
  expect_true(is.na(out$surface[2]))
  expect_false(attr(out, "meta")$has_more)
})

test_that("odd error bodies still raise lta_error", {
  bodies <- list(
    httr2::response(status_code = 502L, headers = list(`Content-Type` = "text/html"),
                    body = charToRaw("<html>bad gateway</html>")),
    json_response("oops", status = 500L)
  )
  local_mocked_bindings(lta_sleep = function(seconds) NULL)
  for (b in bodies) {
    httr2::local_mocked_responses(function(req) b)
    err <- tryCatch(with_key(get_match(1)), lta_error = function(e) e)
    expect_s3_class(err, "lta_http_error")
    expect_false(grepl("  |: NA|NA:", conditionMessage(err)))
  }
})

test_that("every 403 is a plan error, as the spec defines it, and 410 is lta_gone", {
  httr2::local_mocked_responses(function(req) {
    httr2::response(status_code = 403L, headers = list(`Content-Type` = "text/html"),
                    body = charToRaw("<html>forbidden</html>"))
  })
  expect_error(with_key(get_match(1)), class = "lta_plan_error")
  httr2::local_mocked_responses(function(req) {
    json_response(list(error = "merged", detail = "now 99"), status = 410L)
  })
  expect_error(with_key(get_match(1)), class = "lta_gone")
})

test_that("tier joins with commas and logicals pass through ...", {
  seen <- NULL
  httr2::local_mocked_responses(function(req) {
    seen <<- req
    json_response(list(data = list(), meta = list()))
  })
  with_key(list_matches(tier = c("atp_500", "atp_250"), is_qualifying = FALSE))
  expect_match(seen$url, "tier=atp_500%2Catp_250|tier=atp_500,atp_250")
  expect_match(seen$url, "is_qualifying=false")
})

test_that("NA elements are dropped from a vector", {
  expect_equal(lta_query(list(player = c(1, NA, 3))), list(player = c("1", "3")))
})

test_that("wrappers hit the documented paths", {
  paths <- character()
  httr2::local_mocked_responses(function(req) {
    paths <<- c(paths, sub("\\?.*$", "", sub("^https://[^/]+/api/public/v1", "", req$url)))
    json_response(list(data = list(), meta = list()))
  })
  with_key({
    get_match(7); match_score(7); search_players("abc"); get_player(3)
    player_stats(3, surface = "clay"); list_tournaments(tier = c("atp_500", "atp_250"))
    get_tournament(9); archive_matches(tour = "atp"); archive_players(name = "abc")
    archive_career("federer"); head_to_head("djokovic", "nadal"); rankings(system = "atp")
  })
  expect_equal(paths, c("/matches/7", "/matches/7/score", "/players", "/players/3",
                        "/players/3/stats", "/tournaments", "/tournaments/9",
                        "/history/archive/matches", "/history/archive/players",
                        "/history/archive/career", "/h2h", "/rankings"))
})

test_that("fixtures, players and rankings come back as tibbles", {
  httr2::local_mocked_responses(function(req) {
    json_response(list(data = list(list(id = 1, name = "A")), meta = list(has_more = TRUE)))
  })
  with_key({
    for (out in list(list_fixtures(), search_players("abc"), rankings(system = "atp"),
                     list_tournaments(), archive_matches(), archive_players())) {
      expect_s3_class(out, "tbl_df")
      expect_true(lta_meta(out)$has_more)
    }
  })
})

test_that("rankings sends as_of, offset and repeated systems", {
  seen <- NULL
  httr2::local_mocked_responses(function(req) {
    seen <<- req
    json_response(list(data = list(), meta = list()))
  })
  with_key(rankings(system = c("atp", "wta"), as_of = as.Date("2024-01-01"), offset = 100))
  expect_match(seen$url, "system=atp&system=wta")
  expect_match(seen$url, "as_of=2024-01-01")
  expect_match(seen$url, "offset=100")
})

test_that("lta_meta is NULL on something that is not a list result", {
  expect_null(lta_meta(data.frame(a = 1)))
})

test_that("times go out in UTC whether POSIXct or POSIXlt", {
  ct <- as.POSIXct("2026-11-01 12:00:00", tz = "Asia/Jerusalem")
  lt <- as.POSIXlt("2026-11-01 12:00:00", tz = "Asia/Jerusalem")
  expect_equal(lta_value(ct), "2026-11-01T10:00:00Z")
  expect_equal(lta_value(lt), "2026-11-01T10:00:00Z")
})

test_that("numbers are formatted one by one, with no padding or rounding", {
  expect_equal(lta_value(c(1, 100000, 2.5)), c("1", "100000", "2.5"))
  expect_equal(lta_value(1234567.891), "1234567.891")
})

test_that("a NULL, NA or empty id is refused before any request", {
  httr2::local_mocked_responses(function(req) stop("no request should be sent"))
  for (bad in list(NULL, NA, NA_real_, "", c(1, 2))) {
    expect_error(with_key(get_match(bad)), "one value")
  }
})

test_that("a key is trimmed and an empty key counts as missing", {
  seen <- NULL
  httr2::local_mocked_responses(function(req) {
    seen <<- req
    json_response(list(principal = "x"))
  })
  api_usage(key = "  twjp_pad\n")
  expect_equal(auth_header(seen), "Bearer twjp_pad")
  expect_error(api_usage(key = ""), class = "lta_auth_error")
  expect_error(with_key(lta_key(), key = "   "), class = "lta_auth_error")
})

test_that("abuse_throttled has its own class under lta_rate_limited", {
  httr2::local_mocked_responses(function(req) {
    json_response(list(error = "abuse_throttled"), status = 429L)
  })
  err <- tryCatch(with_key(get_match(1)), lta_error = function(e) e)
  expect_s3_class(err, "lta_abuse_throttled")
  expect_s3_class(err, "lta_rate_limited")
})

test_that("every request carries a 30-second timeout", {
  seen <- NULL
  httr2::local_mocked_responses(function(req) {
    seen <<- req
    json_response(list(status = "ok"))
  })
  api_health()
  expect_equal(seen$options$timeout_ms, 30000)
})

test_that("wrappers pass extra query parameters through ...", {
  seen <- character()
  httr2::local_mocked_responses(function(req) {
    seen <<- c(seen, req$url)
    json_response(list(data = list(), meta = list()))
  })
  with_key({
    match_score(7, sequence = 12)
    search_players(restated_since = "2026-11-01")
    archive_players(player_id = 5)
    list_tournaments(country = "fra")
  })
  expect_match(seen[1], "sequence=12")
  expect_match(seen[2], "restated_since=2026-11-01")
  expect_false(grepl("search=", seen[2]))
  expect_match(seen[3], "player_id=5")
  expect_match(seen[4], "country=fra")
})
