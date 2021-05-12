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
pad_cargo_messages <- function(x, pad = "\t") {
  paste0(
    pad,
    stringi::stri_replace_all_regex(
      as.character(x),
      "\n",
      paste0("\n", pad)
    )
  )
}

#' Summary output for errors thrown by \pkg{rextendr}.
#'
#' Extends [rlang:::summary.rlang_error()] by also printing
#'   detailed information about `cargo` errors if such information
#'   is included in the `condition` passed to `object`.
#' @param object \[rextendr::rextendr_error\] 
#'   An instance of `condition` thrown by \pkg{rextendr}.
#' @param ... For compatibility or future use.
#'
#' @noRd
#' @export
summary.rextendr_error <- function(object, ...) {
  print(object, simplify = "none", fields = TRUE)

  # `cargo` errors are passed in `$cargo_errors` list,
  # which contains `$errors` and `$warnings`.
  if (!rlang::is_null(object$cargo_errors)) {
    cat("\n")
    err <- object$cargo_errors$errors
    wrn <- object$cargo_errors$warnings

    # `cargo` failed with `n` error(s):
    #     error1: Compilation failed
    #     error2: File not found
    #     in the folder specified
    if (!rlang::is_null(err)) {
      err <- pad_cargo_messages(err)
      cat(cli_format_text(
        "{.code cargo} failed with {.val {cli::no({cli::qty(err)})}} error{?s}{cli::qty(err)}{? /:/:}"
        )
        , sep = "\n"
      )
      cat(err, sep = "\n")
    }

    # Warnings are formatted similarly
    if (!rlang::is_null(wrn)) {
      wrn <- pad_cargo_messages(wrn)
      cat(cli_format_text(
        "{.code cargo} emitted {.val {cli::no({cli::qty(wrn)})}} warning{?s}{cli::qty(wrn)}{? /:/:}"
        ),
        sep = "\n"
      )
      cat(wrn, sep = "\n")
    }
  }
}
