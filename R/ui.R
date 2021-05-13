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
    class = c("rextendr_error"),
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
#' @param trim \[`logical(1)`\] Indicates whether to limit the output of
#'   each error to at most `n` lines.
#' @param indent \[`integer(1)`\] Indents first line of each error by
#'   `indent` spaces (`" "`). Each subsequent line is indented by `2 * indent`.
#' @param n \`[integer(1)\]` Number of separate lines to include in the output
#'   for each error. Does nothing if `trim = FALSE`.
#' @return \[`character(n)`] Vector of the same length and type,
#'   each element of which is a multi-line, wrapped, trimmed and padded string.
#'   Suitable for printing with [`cat`].
#' @noRd
prepare_cargo_messages <- function(x, trim = TRUE, indent = 2L, n = 3L) {
  if (rlang::is_empty(x)) {
    return (character(0))
  }

  result <- purrr::map(
    stringi::stri_split_lines(
      glue("{seq_along(x)}. {x}")
    ),
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
        .else = ~paste(.x, collapse = "\n")
      )
    )
  } else {
    result <- purrr::map_chr(result, paste, collapse = "\n")
  }

  result
}

#' Creates a special message used for formatting `rextendr_error`.
#'
#' Counts objects in `i` and generates a correctly pluralized messages
#'   similar to the following one:
#'    ```"`cargo` emitted `3` errors:"```
#' @param i \[`vector(n)` | `list(n)`\] A collection used for pluralization.
#'   E.g., `i = 1:5` will produce ```"`5` errors"```, `i = 0` -- ```"`no` errors"```.
#' @param type \[`"error"`|`"warning"`\] Determines the type of message.
#' @param suffix \[`logical(1)`\] If `TRUE`, appends `":"` character if `length(i) != 0`.
#' @return \[`string`\] Formatted string.
#' @noRd
cargo_message_template <- function(i, type = c("error", "warning"),
                                   suffix_colon = TRUE) {
  type <- rlang::arg_match(type)
  # Handling empty input.
  if (rlang::is_null(i) || rlang::is_missing(i))  {
    i <- 0
  # Special case of `cli::qty()`: it treats `integer()` as quantity,
  # so if `i` is an `integer(n)`, it will fail.
  # If replaced by the size of `i`, `cli::qty()` will work correctly.
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
  if (type == "error") {
    txt <- bullet_x(txt)
  } else {
    txt <- bullet_w(txt)
  }

  txt
}

#' Implements formatting of `rextendr_error` objects.
#' 
#' This function provides different ways of formatting
#'   `rextendr_error`'s additional fields and data.
#'   It is called from generic printing/formatting methods.
#'   It does not call any generics itself.
#' @param x \[`rextendr::rextendr_error`\] Error generated by [`rextendr::ui_throw()`].
#' @param trim \[`logical(1)`\] Controls if error messages should be trimmed.
#'   Passed to `rextendr:::prepare_cargo_messages`.
#' @param indent \[`integer(1)`\] Controls error messages' indentation.
#'   Passed to `rextendr:::prepate_cargo_messages()`.
#' @param ... For compatibilty.
#' @return \[`string`\] A multi-line string containing formatted error messages.
#' @noRd
rextendr_error_format_impl <- function(x, trim = TRUE, indent = 2L, ...) {
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
  if (rlang::is_null(output) || rlang::is_empty(output)) {
    result <- NULL
  } else {
    result <- paste(output, collapse = "\n")
  }
}

#' An implementation of generic [`format`] method for `rextendr::rextendr_error`.
#'
#' Implements formatting for `rextendr_error`, offloading formatting of standard fields
#'   to [`format`] of the base type (which should be `rlang::rlang_error`).
#' @param x \[`rextendr::rextendr_error\] Object to format.
#' @param ... For compatibility. Passed to [`format`] of the base type.
#' @param backtrace \[`logical`\] Controls printing of backtrace.
#'   Passed to [`format`] of the base type.
#' @param child \[`?`\] Passed to [`format`] of the base type.
#' @param simplify \[`"branch"`|`"collapse"`|`"none"`\] Wether to simplify the output.
#'   If `simplify = "none"`, no trimming is performed for `rextendr_error` fields.
#'   Passed to [`format`] of the base type.
#' @param fields \[`logical(1)`\] Controls formatting of fields.
#'   Passed to [`format`] of the base type.
#' @param indent \[`integer(1)`\] How much the error messages (e.g., from `cargo`),
#'   should be indented.
#'   Passed to `rextendr:::prepate_cargo_messages()`.
#' @return \[`string`\] Formatted representation of `x`.
#' @noRd
#' @export
format.rextendr_error <- function(x, ..., backtrace = TRUE, child = NULL,
                                  simplify = c("branch", "collapse", "none"),
                                  fields = FALSE,
                                  indent = 2L) {

  trim <- !isTRUE(rlang::arg_match(simplify) == "none")
  withr::local_options(
    rextendr.internal_error_print_options = list(
      trim = trim,
      indent = indent
     )
  )
  if (rlang::is_null(x[["rlang"]])) {
    x$rlang <- NULL
  }
  NextMethod("format", x)
}


#' @export
cnd_header.rextendr_error <- function(cnd, ...) {
  opts <- getOption("rextendr.internal_error_print_options")
  trim <- opts$trim %||% TRUE
  indent <- opts$indent %||% 2L

  paste0("\n", rextendr_error_format_impl(cnd, trim = trim, indent = indent, ...))
}
