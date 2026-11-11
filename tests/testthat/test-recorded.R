# The vignette is built from these recorded responses. Their fields follow the
# Fixture and Match schemas of the published OpenAPI document, and the players
# and tournaments in them are made up.
recorded_response <- function(file) {
  path <- system.file("extdata", file, package = "livetennisapi", mustWork = TRUE)
  function(req) {
    httr2::response(
      status_code = 200L,
      headers = list(`Content-Type` = "application/json"),
      body = readBin(path, "raw", file.size(path))
    )
  }
}

test_that("the recorded fixtures carry every Fixture field", {
  httr2::local_mocked_responses(recorded_response("fixtures.json"))
  fx <- with_key(list_fixtures(limit = 200))
  expect_s3_class(fx, "tbl_df")
  expect_setequal(names(fx), c(
    "id", "event_date", "start_time", "player1_id", "player2_id", "tour",
    "tournament", "round", "round_code", "surface", "player1_name",
    "player2_name", "status"
  ))
  expect_equal(nrow(fx), lta_meta(fx)$count)
  expect_false(lta_meta(fx)$has_more)
  expect_true(all(fx$status %in% c("scheduled", "live", "finished", "cancelled", "postponed")))
  # Earliest day first. Some fixtures have a date and no start time yet.
  expect_false(is.unsorted(fx$event_date))
  expect_true(anyNA(fx$start_time))
  timed <- as.POSIXct(fx$start_time, format = "%Y-%m-%dT%H:%M:%S", tz = "UTC")
  expect_false(anyNA(timed[!is.na(fx$start_time)]))
})

test_that("the recorded live matches flatten into the columns the vignette reads", {
  httr2::local_mocked_responses(recorded_response("matches-live.json"))
  live <- with_key(live_matches())
  expect_s3_class(live, "tbl_df")
  expect_true(all(c("tour", "tournament", "players.p1.name", "players.p2.name",
                    "score.sets") %in% names(live)))
  expect_true(all(live$status == "live"))
  expect_true(all(live$tour %in% c("atp", "wta", "challenger", "itf", "juniors")))
})
