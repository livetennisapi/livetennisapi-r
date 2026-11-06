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

test_that("list endpoints return a flattened data frame with meta", {
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
  expect_s3_class(out, "data.frame")
  expect_equal(nrow(out), 2)
  expect_equal(out$players.p1.name, c("A", "C"))
  expect_equal(attr(out, "meta")$next_cursor, "abc")
})

test_that("an empty list is an empty data frame", {
  httr2::local_mocked_responses(function(req) json_response(list(data = list(), meta = list())))
  out <- with_key(list_fixtures())
  expect_s3_class(out, "data.frame")
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

test_that("the retry policy covers 502, 503 and 504 and never a 429", {
  seen <- NULL
  httr2::local_mocked_responses(function(req) {
    seen <<- req
    json_response(list(status = "ok"))
  })
  api_health()
  transient <- seen$policies$retry_is_transient
  expect_false(transient(httr2::response(status_code = 429L)))
  expect_false(transient(httr2::response(status_code = 500L)))
  for (code in c(502L, 503L, 504L)) expect_true(transient(httr2::response(status_code = code)))
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
  for (b in bodies) {
    httr2::local_mocked_responses(function(req) b)
    err <- tryCatch(with_key(get_match(1)), lta_error = function(e) e)
    expect_s3_class(err, "lta_http_error")
    expect_false(grepl("  |: NA|NA:", conditionMessage(err)))
  }
})

test_that("403 without upgrade_required is an auth error, 410 is lta_gone", {
  httr2::local_mocked_responses(function(req) {
    json_response(list(error = "forbidden", detail = "key revoked"), status = 403L)
  })
  expect_error(with_key(get_match(1)), class = "lta_auth_error")
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
