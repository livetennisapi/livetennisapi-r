# livetennisapi (development version)

* New vignette, "Today's tennis fixtures in R": read the schedule, reshape the
  tibble and chart fixtures by tour and hour. It builds from recorded responses
  in `inst/extdata`, so it needs no key.

# livetennisapi 0.2.0

* List functions return tibbles. `lta_meta()` reads a result's paging details.
* Retries follow the Python and JavaScript clients: dropped connections, 5xx
  and the per-minute 429 are retried, honouring `Retry-After` up to a minute. The daily-quota 429 and
  `abuse_throttled` are raised at once. Conditions carry `retry_after`, and an
  unreachable API raises `lta_connection_error`.
* `rankings()` takes `as_of`, `offset` and other query parameters through `...`.

# livetennisapi 0.1.0

* First release: wrappers for live matches, fixtures, players, tournaments, the
  results archive, head-to-head and rankings, plus `lta_get()` for any other
  endpoint. Typed error conditions for auth, plan, rate limit, not found and bad
  request.
