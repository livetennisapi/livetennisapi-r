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
#' # TRUE when a key is set; the key itself is never printed here.
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
#' higher plan), `lta_rate_limited` (429), `lta_not_found` (404) or
#' `lta_bad_request` (400) or `lta_gone` (410: the record was merged into
#' another, and the body says which). The condition carries `status`, `code`
#' (the API's machine-readable error) and `body`.
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
  # Retry only failures that are worth retrying. A 429 is not one: the daily
  # quota does not come back in a few seconds.
  req <- httr2::req_retry(
    req, max_tries = 3,
    is_transient = function(resp) httr2::resp_status(resp) %in% c(502L, 503L, 504L)
  )
  req <- httr2::req_error(req, is_error = function(resp) FALSE)
  resp <- httr2::req_perform(req)
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
# `meta` is kept as an attribute for paging.
lta_frame <- function(body) {
  out <- body$data
  if (!is.data.frame(out)) out <- data.frame()
  attr(out, "meta") <- body$meta
  out
}

# GET a list endpoint and return its rows as a data frame.
lta_list <- function(path, query, key) {
  lta_frame(lta_get(path, query, key = key, simplify = TRUE))
}
