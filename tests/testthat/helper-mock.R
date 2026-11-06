# Every test runs against a mocked transport: nothing reaches the network.
json_response <- function(body, status = 200L, headers = list()) {
  httr2::response(
    status_code = status,
    headers = c(list(`Content-Type` = "application/json"), headers),
    body = charToRaw(jsonlite::toJSON(body, auto_unbox = TRUE, null = "null", digits = NA))
  )
}

with_key <- function(code, key = "twjp_test") {
  withr_env <- Sys.getenv("LIVETENNISAPI_KEY", NA)
  Sys.setenv(LIVETENNISAPI_KEY = key)
  on.exit(if (is.na(withr_env)) Sys.unsetenv("LIVETENNISAPI_KEY")
          else Sys.setenv(LIVETENNISAPI_KEY = withr_env))
  force(code)
}

# httr2 redacts the Authorization header in the request object; read it back.
auth_header <- function(req) httr2::req_get_headers(req, redacted = "reveal")$Authorization
