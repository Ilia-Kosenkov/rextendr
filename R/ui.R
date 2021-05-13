bullet <- function(text = "", cli_f = cli::cli_alert_success, env = parent.frame()) {
  cli::cli_format_method(cli_f(text, .envir = env))
}

bullet_x <- function(text = "", env = parent.frame()) {
  bullet(text, cli::cli_alert_danger, env = env)
}

bullet_i <- function(text = "", env = parent.frame()) {
  bullet(text, cli::cli_alert_info, env = env)
}

bullet_v <- function(text = "", env = parent.frame()) {
  bullet(text, cli::cli_alert_success, env = env)
}

bullet_o <- function(text = "", env = parent.frame()) {
  bullet(text, cli::cli_ul, env = env)
}

bullet_w <- function(text = "", env = parent.frame()) {
  bullet(text, cli::cli_alert_warning, env = env)
}

ui_bullet <- function(text) {
  if (getOption("usethis.quiet", FALSE)) {
    return(invisible())
  }

  rlang::inform(text)
}

#' Formats text as an error message.
#'
#' Prepends `text` with red cross (`x`).
#' Supports {cli}'s inline styles and string interpolation.
#' @param text String to format.
#' @noRd
ui_x <- function(text = "", env = parent.frame()) {
  ui_bullet(bullet_x(text, env = env))
}

#' Formats text as an information message.
#'
#' Prepends `text` with cyan info sign (`i`).
#' Supports {cli}'s inline styles and string interpolation.
#' @inheritParams ui_x
#' @noRd
ui_i <- function(text = "", env = parent.frame()) {
  ui_bullet(bullet_i(text, env = env))
}

#' Formats text as a success message.
#'
#' Prepends `text` with green check mark (`v`).
#' Supports {cli}'s inline styles and string interpolation.
#' @inheritParams ui_x
#' @noRd
ui_v <- function(text = "", env = parent.frame()) {
  ui_bullet(bullet_v(text, env = env))
}

#' Formats text as a bullet point
#'
#' Prepends `text` with red bullet point
#' Supports {cli}'s inline styles and string interpolation.
#' @inheritParams ui_x
#' @noRd
ui_o <- function(text = "", env = parent.frame()) {
  ui_bullet(bullet_o(text, env = env))
}

#' Formats text as a warning message.
#'
#' Prepends `text` with yellow exclamation mark (`!`).
#' Supports {cli}'s inline styles and string interpolation.
#' @inheritParams ui_x
#' @noRd
ui_w <- function(text = "", env = parent.frame()) {
  ui_bullet(bullet_w(text, env = env))
}

#' Throws an error with formatted message.
#'
#' Creates a styled error message that is then thrown
#' using [`rlang::abort()`]. Supports {cli} formatting.
#' @param message \[`string`\] The primary error message.
#' @param details \[`character(n)`\] An optional vector of error details.
#'   Can be formatted with `bullet()`.
#' @param additional_data \[`list()` or `NULL`\] A list of additional objects that
#'   will be attached to the error object and can be retrieved with e.g. [rlang::last_error()].
#' @param env \[`environment`\] Environment of the caller used in string interpolation.
#' @param trace \[`rlang::rlang_trace`\] A trace object created by [rlang::trace_back()].
#' @param parent \[`condition`\] Parent condition (useful for error aggregation or in `tryCatch` blocks).
#' @examples
#' \dontrun{
#' ui_throw(
#'   "Something bad has happened!",
#'   c(
#'     bullet_x("This thing happened."),
#'     bullet_x("That thing happened."),
#'     bullet_o("Are you sure you did it right?")
#'   )
#' )
#' # Error: Something bad has happened!
#' # x This thing happened.
#' # x That thing happened.
#' # o Are you sure you did it right?
#' }
#' @noRd
ui_throw <- function(message = "Internal error", 
                     details = character(0), 
                     additional_data = list(),
                     env = parent.frame(),
                     trace = NULL,
                     parent = NULL) {
  message <- cli_format_text(message, env = env)

  if (length(details) != 0L) {
    details <- glue::glue_collapse(details, sep = "\n")
    message <- glue::glue(message, details, .sep = "\n")
  }

  rlang::abort(
    message,
    class = "rextendr_error",
    trace = trace,
    parent = parent,
    !!!additional_data
  )
}

#' Formats text using \pkg{cli} interpolation syntax.
#'
#' @param message \[`string`\] Message to format.
#' @param env \[`environment`\] Environment of the caller where interpolation is performed.
#' @return \[`string`\] Interpolated `ANSI` string.
#' @noRd
cli_format_text <- function(message, env = parent.frame()) {
  cli::cli_format_method(cli::cli_text(message, .envir = env))
}

#' Pads every line of character vector with some `pad`
#'
#' This method is used to shift all output of cargo by one `pad` when writing to console.
#' @param x \[`character(n)`\] Vector of messages captured from `cargo`.
#'   Each message can be a multiline string.
#' @param pad \[string\] Padding string.
#' @return \[`character(n)`] Vector of the same length and type,
#'   in which each occurence of `\n` is suffixed with `pad`.
#'   An additional `pad` is prefixed to the beginning of each string.
#' @noRd
prepare_cargo_messages <- function(x, pad = "\t", 
                                   trim = TRUE, indent = 2L,
                                   n = 3L) {
  if (rlang::is_empty(x)) {
    return (character(0))
  }
  
  result <- glue("{seq_along(x)}. {x}") %>% 
    stringi::stri_split_lines() %>%
    purrr::map(
      stringi::stri_wrap,
        width = floor(0.8 * getOption("width")),
        initial = strrep(" ", indent),
        prefix = strrep(" ", 2 * indent),
        normalize = FALSE
    )

  if (isTRUE(trim)) {
    result <- purrr::flatten_chr(
      purrr::map_if(
        result,
        ~length(.x) > n,
        ~paste0(
          paste(.x[seq_len(n)], collapse = "\n"), 
          "..."
        ),
        .else = ~.x[1]
      )
    )
  } else {
    result <- purrr::map_chr(result, paste, collapse = "\n")
  }

  result
}

cargo_message_template <- function(i, type = c("error", "warning"),
                                   suffix_colon = TRUE) {
  type <- rlang::arg_match(type)
  if (rlang::is_null(i) || rlang::is_missing(i))  {
    i <- 0
  } else if (is.numeric(i)) {
    i <- length(i)
  }
  colon <- ifelse(
    isTRUE(suffix_colon),
     cli_format_text("{cli::qty(i)}{?/:/:}"),
     ""
  )
  txt <- cli_format_text(
    "{.code cargo} emitted {.val {cli::no({cli::qty(i)})}} {type}{cli::qty(i)}{?s}{colon}"
  )
  if(type == "error") {
    txt <- bullet_x(txt)
  } else {
    txt <- bullet_w(txt)
  }

  txt
}

rextendr_error_format_impl <- function(x, ..., trim = TRUE, indent = 2L) {
  trim <- isTRUE(trim)

  output <- c()
  # `cargo` errors are passed in `$cargo_errors` list,
  # which contains `$errors` and `$warnings`.
  if (!rlang::is_null(x$cargo_errors)) {
    err <- x$cargo_errors$errors
    wrn <- x$cargo_errors$warnings
    # `cargo` emitted `n` error(s):
    #   1.: Compilation failed
    #   2.: File not found
    #     in the folder specified
    if (!rlang::is_null(err) && !rlang::is_empty(err)) {
      err <- prepare_cargo_messages(err, indent = indent, trim = trim)
      err_header <- cargo_message_template(err, "error")

      output <- c(output, err_header, err)
    }

    # Warnings are formatted similarly
    if (!rlang::is_null(wrn) && !rlang::is_empty(wrn)) {
      wrn <- prepare_cargo_messages(wrn, indent = indent, trim = trim)
      wrn_header <- cargo_message_template(wrn, "warning")
      output <- c(output, wrn_header, wrn)
    }
  }

  paste(output, collapse = "\n")
}

#' @export
format.rextendr_error <- function(x, ..., backtrace = TRUE, child = NULL,
                                  simplify = c("branch", "collapse", "none"),
                                  fields = FALSE,
                                  indent = 2L) {

  trim <- !isTRUE(rlang::arg_match(simplify) == "none")
  rxt_format <- rextendr_error_format_impl(x, trim = trim, ident = ident, ...)

  # We need to trick S3 dispatcher to dispatch all inner calls
  # using `rlang_error` type rather than `rextendr_error`.
  # If not done, it enters infinite recursion because {rlang} calls
  # `conditionMessage`, which resolves to `conditionMessage.rextendr_error`,
  # which calls `format` which resolves to this method...
  cls <- class(x)
  withr::defer(class(x) <- cls)

  # If we temporarily remove all `rextendr_`-prefixed classes from `x`,
  # it will be processed as `rlang_error` and no infinite recursion will occur.
  # Doing so offloads all formatting to {rlang} and 
  # we write only information that we want.
  class(x) <- stringi::stri_subset_regex(cls, "^rextendr_", negate = TRUE)
  paste(
    NextMethod(x),
    "",
    rxt_format,
    sep = "\n"
  )
}

#' @export
conditionMessage.rextendr_error <- function(x) {
  paste(
    NextMethod(x),
    rextendr_error_format_impl(x),
    sep = "\n"
  )
}



# tryCatch(
  # ui_throw(
  #   "Error in cargo",
  #   bullet_i("See additional info"),
  #   additional_data = list(
  #     cargo_errors = list(
  #       errors = c(
  #         "First error",
  #         "Lorem ipsum dolor \nsit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. \nExcepteur sint occaecat \n cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."
  #       ),
  #       warnings = c("First warning", "Second warning")
  #     )
  #   )
  # )#,
#   error = identity
# ) -> captured_err

# print(captured_err)
# print(format(captured_err))
# print(summary(captured_err))