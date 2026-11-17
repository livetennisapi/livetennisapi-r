#' @keywords internal
"_PACKAGE"

# httr2::resp_body_json() parses every response with jsonlite, but httr2 lists
# jsonlite only under Suggests. Importing it here makes it a hard dependency,
# so a clean install can read the API's answers.
#' @importFrom jsonlite fromJSON
NULL
