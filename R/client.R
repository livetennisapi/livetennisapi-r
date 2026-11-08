#' The base URL of the Live Tennis API
#'
#' Set the `LIVETENNISAPI_BASE_URL` environment variable to point the client
#' somewhere else, for example a local mock in tests.
#'
#' @return A string.
#' @keywords internal
lta_base_url <- function() {
  url <- Sys.getenv("LIVETENNISAPI_BASE_URL", "")
  if (identical(url, "")) "https://api.livetennisapi.com/api/public/v1" else url
}

#' Read the API key
#'
#' The key comes from the `LIVETENNISAPI_KEY` environment variable. Get a free
#' key, with no card, at <https://livetennisapi.com/subscribe/free>.
#'
#' @return The key as a string, or an error when it is not set.
#' @export
#' @examplesIf nzchar(Sys.getenv("LIVETENNISAPI_KEY"))
#' # TRUE when a key is set. The key itself is never printed.
#' nzchar(lta_key())
lta_key <- function() {
  key <- Sys.getenv("LIVETENNISAPI_KEY", "")
  if (identical(key, "")) {
    stop(structure(
      class = c("lta_auth_error", "lta_error", "error", "condition"),
      list(
        message = paste0(
          "No API key. Set LIVETENNISAPI_KEY, or pass `key`. ",
          "A free key needs no card: https://livetennisapi.com/subscribe/free"
        ),
        call = NULL, status = NA_integer_, code = "missing_key"
      )
    ))
  }
  key
}

# One value as the API reads it. Numbers never go out in scientific notation:
# as.character(100000) is "1e+05", which the API refuses as an id.
lta_value <- function(x) {
  if (is.logical(x)) return(ifelse(x, "true", "false"))
  if (inherits(x, "Date")) return(format(x, "%Y-%m-%d"))
  if (inherits(x, "POSIXt")) return(format(x, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
  if (is.numeric(x)) return(format(x, scientific = FALSE, trim = TRUE))
  as.character(x)
}

# A path segment, such as a match id.
lta_id <- function(x) utils::URLencode(lta_value(x), reserved = TRUE)

# Turn R values into query strings: drop NULL and NA (element by element),
# write logicals as true/false and dates as YYYY-MM-DD. Vectors longer than one
# become repeated keys, which is how the API reads its repeatable filters.
lta_query <- function(query) {
  query <- lapply(query, function(x) if (is.null(x)) NULL else x[!is.na(x)])
  query <- query[vapply(query, length, integer(1)) > 0L]
  lapply(query, lta_value)
}

# The retry policy matches the Python and JavaScript clients. A 5xx and the
# per-minute 429 are worth another try. Two 429 bodies are not: the daily cap
# (`scope: "day"`) holds for hours, and `abuse_throttled` is a 24-hour block
# that retrying makes worse. Every other 4xx is a mistake no retry can fix.
lta_transient <- function(resp) {
  status <- httr2::resp_status(resp)
  if (status >= 500L) return(TRUE)
  if (status != 429L) return(FALSE)
  body <- tryCatch(httr2::resp_body_json(resp), error = function(e) list())
  if (!is.list(body)) return(TRUE)
  !(identical(body$error, "abuse_throttled") || identical(body$scope, "day"))
}

# Wait what the API asks for in Retry-After, capped at a minute. NA hands the
# decision to the backoff below.
lta_retry_after <- function(resp) {
  raw <- httr2::resp_header(resp, "Retry-After")
  secs <- suppressWarnings(as.numeric(raw))
  if (length(secs) != 1L || is.na(secs) || secs < 0) return(NA_real_)
  min(secs, 60)
}

# Exponential with jitter, so clients that failed together do not retry
# together. `i` counts from 1.
lta_backoff <- function(i) min(0.5 * 2^(i - 1) + stats::runif(1) * 0.25, 10)

# A seam for the tests, which replace it so retries run without waiting.
lta_sleep <- function(seconds) Sys.sleep(seconds)

# Send a request, retrying what lta_transient() allows. The loop lives here
# rather than in httr2::req_retry() so the policy is the same whether the
# transport is real or mocked, and so a dropped connection is retried too.
lta_perform <- function(req, max_tries = 3L) {
  for (attempt in seq_len(max_tries)) {
    resp <- tryCatch(httr2::req_perform(req), httr2_failure = function(e) e)
    last <- attempt == max_tries
    if (inherits(resp, "error")) {
      if (last) stop(lta_connection_error(resp))
      lta_sleep(lta_backoff(attempt))
      next
    }
    if (last || !lta_transient(resp)) return(resp)
    wait <- lta_retry_after(resp)
    lta_sleep(if (is.na(wait)) lta_backoff(attempt) else wait)
  }
}

lta_connection_error <- function(parent) {
  structure(
    class = c("lta_connection_error", "lta_error", "error", "condition"),
    list(message = paste0("Could not reach the Live Tennis API: ", conditionMessage(parent)),
         call = NULL, status = NA_integer_, code = NA_character_, parent = parent)
  )
}

lta_condition <- function(resp) {
  status <- httr2::resp_status(resp)
  body <- tryCatch(httr2::resp_body_json(resp), error = function(e) list())
  if (!is.list(body)) body <- list()
  code <- if (is.null(body$error)) NA_character_ else as.character(body$error)[1]
  detail <- if (is.null(body$detail)) httr2::resp_status_desc(resp) else as.character(body$detail)[1]
  if (length(detail) == 0L || is.na(detail)) detail <- "request failed"
  subclass <- if (status %in% c(401L, 403L)) {
    if (identical(code, "upgrade_required")) "lta_plan_error" else "lta_auth_error"
  } else if (status == 429L) {
    "lta_rate_limited"
  } else if (status == 404L) {
    "lta_not_found"
  } else if (status == 400L) {
    "lta_bad_request"
  } else if (status == 410L) {
    "lta_gone"
  } else {
    "lta_http_error"
  }
  structure(
    class = c(subclass, "lta_error", "error", "condition"),
    list(
      message = paste0("Live Tennis API ", status,
                       if (is.na(code)) "" else paste0(" ", code), ": ", detail),
      call = NULL, status = status, code = code, body = body,
      retry_after = httr2::resp_header(resp, "Retry-After")
    )
  )
}

#' Call any Live Tennis API endpoint
#'
#' The other functions in this package are thin wrappers around this one. Use
#' it for an endpoint that has no wrapper yet. The full list is in the
#' reference at <https://docs.livetennisapi.com/reference.html>.
#'
#' Failures raise a condition of class `lta_error`, with a subclass you can
#' catch: `lta_auth_error` (401 or 403), `lta_plan_error` (the endpoint needs a
#' higher plan), `lta_rate_limited` (429), `lta_not_found` (404),
#' `lta_bad_request` (400), `lta_gone` (410: the record was merged into
#' another, and the body says which) or `lta_connection_error` (the API could
#' not be reached). The condition carries `status`, `code`
#' (the API's machine-readable error), `body` and `retry_after`.
#'
#' A call is tried up to three times. Dropped connections, server errors (5xx)
#' and the per-minute 429 are retried, waiting what `Retry-After` asks for (at most a minute) or
#' a short backoff. The daily-quota 429 and `abuse_throttled` are raised at
#' once, because neither clears in seconds.
#'
#' @param path The endpoint path, for example `"/matches"`.
#' @param query A named list of query parameters. `NULL` values are dropped.
#' @param key The API key. Defaults to [lta_key()].
#' @param auth Send the key. Only `/health` works without one.
#' @param simplify Simplify JSON arrays into vectors and data frames.
#' @return The parsed JSON body as a list.
#' @export
#' @examplesIf nzchar(Sys.getenv("LIVETENNISAPI_KEY"))
#' lta_get("/matches", list(status = "live", tour = "atp"))
lta_get <- function(path, query = list(), key = NULL, auth = TRUE, simplify = FALSE) {
  req <- httr2::request(lta_base_url())
  req <- httr2::req_url_path_append(req, path)
  req <- httr2::req_url_query(req, !!!lta_query(query), .multi = "explode")
  req <- httr2::req_user_agent(
    req,
    sprintf("livetennisapi-r/%s (+https://github.com/livetennisapi/livetennisapi-r)",
            utils::packageVersion("livetennisapi"))
  )
  if (isTRUE(auth)) {
    req <- httr2::req_auth_bearer_token(req, if (is.null(key)) lta_key() else key)
  }
  req <- httr2::req_error(req, is_error = function(resp) FALSE)
  resp <- lta_perform(req)
  if (httr2::resp_status(resp) >= 400L) stop(lta_condition(resp))
  if (isTRUE(simplify)) {
    httr2::resp_body_json(resp, simplifyVector = TRUE, flatten = TRUE)
  } else {
    httr2::resp_body_json(resp, simplifyVector = FALSE)
  }
}

# A list endpoint answers {data: [...], meta: {...}}. The body is parsed once
# with simplification, so `data` arrives as a data frame with nested objects
# flattened into columns such as players.p1.name, at full numeric precision.
# It goes out as a tibble, with `meta` kept as an attribute for paging.
lta_frame <- function(body) {
  out <- body$data
  out <- if (is.data.frame(out)) tibble::as_tibble(out) else tibble::tibble()
  attr(out, "meta") <- body$meta
  out
}

#' Paging details of a list result
#'
#' Every list function returns a tibble and keeps the response's `meta`
#' object as an attribute. `lta_meta()` reads it back. It holds `limit`,
#' `offset`, `count`, `total` (which can be `NULL`), `has_more` and, on the
#' change feed, `next_cursor`. Subsetting a tibble drops the attribute, so
#' read it from the result as it came back.
#'
#' @param x A tibble returned by a list function, such as [live_matches()].
#' @return A list, or `NULL` when `x` carries no paging details.
#' @export
#' @examplesIf nzchar(Sys.getenv("LIVETENNISAPI_KEY"))
#' fx <- list_fixtures(limit = 10)
#' lta_meta(fx)$has_more
lta_meta <- function(x) attr(x, "meta", exact = TRUE)

# GET a list endpoint and return its rows as a tibble.
lta_list <- function(path, query, key) {
  lta_frame(lta_get(path, query, key = key, simplify = TRUE))
}
