## Problem outline
We run `cargo` in two scenarios: when a user uses public API like `rust_function` and when {knitr} is processing markdown.
https://github.com/extendr/rextendr/blob/00ce4650ee044e4b7c66ebeaecaa65c6d5ec7024/R/source.R#L281-L297
As you can see, right now we simply use `system2` with some `stderr`/`stdout` redirection and check its exit status.
If not zero, we throw a super-useful error with absolutely **no** details.

In a user session, when R has access to `stdout` and `stderr`, `cargo` displays its output in the console (unless `quiet = TRUE`).
This helps to resolve any compilation errors.
What happens if no `stdout`/`stderr` is available or if `quiet = TRUE`? Well, nothing is printed and the only useful information is the error message saying `"Compilation failed. Aborting"`. This is especially painful when running `R CMD check` or `rcmdcheck::rcmdcheck`, as it shows you errors but not `stdout`/`stderr`. 

## Proposed solution
As suggested by @dfalbel, we use `rlang::abort()` to produce an `rlang::rlang_error` when calling `rextendr::ui_throw()`.
`rlang::abort()` [allows](https://rlang.r-lib.org/reference/abort.html) attaching additional named data to the thrown error using its `...` argument. 
So, we could augment the invocation of `cargo`, capture its errors and attach them to our `rextendr::rextendr_error`. 
This way, even if we disable verbose output for `cargo`, we will be able to provide an explanation to the user of what went wrong.
Sounds simple? Well, not really, here are the details.

## Implementation details
### Capturing `cargo` output
The desired solution is to be able to **both** *display* and *capture* output of `cargo`, preserving its color scheme and formatting. We would also want to be able to 'switch off' verbose output yet still capture it for the purpose of error formatting, satisfying `quiet = TRUE`.

`cargo` is a little bit tricky. It prints to `stdout` information like passed/failed tests, but sends all compilation info, warnings and errors to `stderr` (this includes all these fancy `'Updating crates.io`', `'Compiling x'`, `'Finished'`, etc messages).
In our scenario, we run `cargo build --lib`, so there should be no `stdout` at all, but for now let us assume there may be `stdout` during compilation. Just a reminder that we are discussing runtime compilation, where we create Rust crate ourselves, so I expect no `build.rs` or any other build tricks, just plain compilation of (likely one) Rust file(s).

- Problem: [`system2`](https://rdrr.io/r/base/system2.html) cannot simultaneously print and capture output to a variable or file.
- Solution: `cargo` is a separate executable, so let's run it properly: [`processx::run()`](https://rdrr.io/cran/processx/man/run.html). We depend on {processx} through {callr}, which is used for out-of-process wrapper generation. The `processx::run()` allows to both capture and print out `stdout` and `stderr`, separately. If configured correctly, it will behave as `system2()`, but the returned value will contain not only `$status` code, but also `$stdout` and `$stderr`. 
Using additional parameters like `echo` and `echo_cmd`, we can control all of the printed output.
Instead of passing around weird `stdout`/`stderr` variables with obscure values of `""`/`NULL`, we can have one parameter `quiet = logical(1)`, in line with other functions, and switch off all printed output based on the value of this flag.
- Changes: Remove `stdout` and `stderr` from `rextendr:::invoke_cargo()`, add a single `quiet` argument. Replace call to `system2()` with call to `processx::run()` or `callr::run()` (a re-exported function), adjust parameters, record `stderr` in a separate variable.
- Drawbacks:
  -  When capturing `stderr`, on Windows the `stdout`/`stderr` interleaving may break, likely caused by `stdout` buffering.  However, because `cargo` does not write to `stdout` that much in our scenarios, this problem is unobserved. *No remedy is available.*
  - When writing and capturing `stderr`, `processx::run()` prints child process' `stderr` to R's `stdout`. As a result, when using `{knitr}`, compilation information leaks to the captured output. 
  *Temporary fix*: execute {knitr} with `quiet = TRUE`. 
  *Permanent fix*: revise `rextendr::rust_eval()`, which compiles and runs code fragment in one go. Suggested solution: make `rust_eval_fun()` which compiles fragment and returns R wrapper function, which allows to separately capture compilation `stdout` and any `stdout` printed by Rust snippet. Can be implemented together with improving {rextendr} {knitr} engine.
  
- Problem: `cargo` stdout is unstructured. However, multiple errors can be emitted alongside warnings. The same stream contains information about successful compilation, which is clearly not errors.
- Solution: The output is pretty straightforward. It can be concatenated into a single string. We can match lines on `"\nwarning:|\nerror:"` or something similar. Using this pattern we can split the input into (multi-line) substrings and trim extra spaces from both sides. If matched correctly, then all strings starting with `"^error:"` will contain information about strictly one error. Same applies to `"^warning:"`. 
Collected `errors` and `warnings` can be sent along `rextendr::rextendr_error` as `cargo_errors = list(errors = errors, warnings = warnings)`.
- Drawbacks: 
  - Parsing generally unknown and unstructured output which may change in future versions of Rust. In the worst-case scenario, we won't get any useful information from `stderr`, which is what we have right now (so no regression). In the best-case scenario, we will capture each error and warning separately, ignoring all garbage about successful compilations. This postprocessing only happens when `cargo` fails, so there should be at least one error in the output. Even if we grab everything in the `stderr`, it is still better than what we have right now.
  - {cli} does not support advanced ansi-aware regex, so for now we first strip all of the output of ansi sequences and process plain text. 
  *Permanent fix*: Investigate how to utilize {cli} ansi-aware regex and possibly simplify expressions, which may allow us to include `cargo` error messages in our `rextendr::rextendr_error`, preserving **all** formatting, including colors.
  
### Printing `rextendr_error`
In general, {rlang} does not display additional fields and metadata when printed `rlang::rlang_error`-derived errors. What we would like is to have two display modes: a shorter form which prints only part of errors/warnings, which is used everywhere (especially when the error is uncaught), and a longer form which prints all of the `cargo` errors/warnings, which should be accessed using `summary` `S3` method. 

- Problem: To print `rextendr::rextendr_error` in short form, we need to be able to carefully wrap error messages and subset `n` lines from each error message, preserving format. Otherwise, we will lose useful information like where in the source code the error occurred. It is desirable to offload as much formatting as possible to {rlang} or any other base-type methods.
- Solution:  We can achieve this by overloading two `S3` methods:
  ```
  conditionMessage.rextendr_error <- function(c) {}
  format.rextendr_error <- function(x, ...) {}
  ```
  `conditionMessage` is invoked by {rlang} when formatting its body. This method provides the output of the base class plus additional information about `cargo` errors in short form. This implementation automatically propagates to other printing methods.
`format` is invoked when formatting, e.g., for `summary` method. We can use one of the {rlang} parameters to determine if the output should be simplified or detailed. When detailed, we output `cargo` errors in the long form. This automatically enables `summary()` to print detailed information.

Drawbacks: 
  - Due to {rlang}'s [implementation](https://github.com/r-lib/rlang/blob/c2510b8574e4429ccb9eefc805054a611e68f139/R/cnd-error.R) of formatting methods, calling `NextMethod()` in `format()` results in an infninte recursion. 
  *Solution*: In `rextendr::format.rextendr_error` temporarily strip error object of all `"rextendr_*"` classes and then dispatch `S3`, which will then resolve into correct {rlang} generics, avoiding infinite recursion.
  - Wrapping and printing out error messages can be tricky. We want to preserve the structure and (possibly) theme.
    *Temporary fix*: we handle plain text only, wrap lines preserving original line breaks as well.
    *Permanent fix*: we use ansi-aware procedure to process original error messages, preserving full formatting.
    
## The best part: reproducible example:

<details>
<summary>After</summary>

``` r
# Catching error
err <- tryCatch(rextendr::rust_function("fn invalid syntax(){}", quiet = TRUE), error = identity)
# Short form
print(err)
#> <error/rlang_error>
#> Rust code could not be compiled successfully. Aborting.
#> 
#> x `cargo` emitted 3 errors:
#>   1. error: expected one of `(` or `<`, found `syntax`
#>      --> src\lib.rs:3:12
#>       |...
#>   2. error: aborting due to previous error
#>   3. error: could not compile `rextendr1`
#> Backtrace:
#>  1. base::tryCatch(...)
#>  5. rextendr::rust_function("fn invalid syntax(){}", quiet = TRUE)
#>  6. rextendr::rust_source(code = code, env = env, ...)
#>  7. rextendr:::invoke_cargo(...)
#>  8. rextendr:::ui_throw(...)
#> 
#> x `cargo` emitted 3 errors:
#>   1. error: expected one of `(` or `<`, found `syntax`
#>      --> src\lib.rs:3:12
#>       |...
#>   2. error: aborting due to previous error
#>   3. error: could not compile `rextendr1`
# Long form
summary(err)
#> <error/rlang_error>
#> Rust code could not be compiled successfully. Aborting.
#> 
#> x `cargo` emitted 3 errors:
#>   1. error: expected one of `(` or `<`, found `syntax`
#>      --> src\lib.rs:3:12
#>       |...
#>   2. error: aborting due to previous error
#>   3. error: could not compile `rextendr1`
#> Backtrace:
#>     x
#>  1. +-base::tryCatch(...)
#>  2. | \-base:::tryCatchList(expr, classes, parentenv, handlers)
#>  3. |   \-base:::tryCatchOne(expr, names, parentenv, handlers[[1L]])
#>  4. |     \-base:::doTryCatch(return(expr), name, parentenv, handler)
#>  5. \-rextendr::rust_function("fn invalid syntax(){}", quiet = TRUE)
#>  6.   \-rextendr::rust_source(code = code, env = env, ...)
#>  7.     \-rextendr:::invoke_cargo(...)
#>  8.       \-rextendr:::ui_throw(...)
#> 
#> x `cargo` emitted 3 errors:
#>   1. error: expected one of `(` or `<`, found `syntax`
#>      --> src\lib.rs:3:12
#>       |
#>     3 | fn invalid syntax(){}
#>       |            ^^^^^^ expected one of `(` or `<`
#>   2. error: aborting due to previous error
#>   3. error: could not compile `rextendr1`
```

<sup>Created on 2021-05-13 by the [reprex package](https://reprex.tidyverse.org) (v2.0.0)</sup>

![image](https://user-images.githubusercontent.com/8782986/118118759-04df4580-b3f6-11eb-98d8-f7bd0acdd93f.png)


</details>

``` r
# Catching error
err <- tryCatch(rextendr::rust_function("fn invalid syntax(){}", quiet = TRUE), error = identity)
# Short form
print(err)
#> <error/rlang_error>
#> Rust code could not be compiled successfully. Aborting.
#> 
#> x `cargo` emitted 3 errors:
#>   1. error: expected one of `(` or `<`, found `syntax`
#>      --> src\lib.rs:3:12
#>       |...
#>   2. error: aborting due to previous error
#>   3. error: could not compile `rextendr1`
#> Backtrace:
#>  1. base::tryCatch(...)
#>  5. rextendr::rust_function("fn invalid syntax(){}", quiet = TRUE)
#>  6. rextendr::rust_source(code = code, env = env, ...)
#>  7. rextendr:::invoke_cargo(...)
#>  8. rextendr:::ui_throw(...)
#> 
#> x `cargo` emitted 3 errors:
#>   1. error: expected one of `(` or `<`, found `syntax`
#>      --> src\lib.rs:3:12
#>       |...
#>   2. error: aborting due to previous error
#>   3. error: could not compile `rextendr1`
# Long form
summary(err)
#> <error/rlang_error>
#> Rust code could not be compiled successfully. Aborting.
#> 
#> x `cargo` emitted 3 errors:
#>   1. error: expected one of `(` or `<`, found `syntax`
#>      --> src\lib.rs:3:12
#>       |...
#>   2. error: aborting due to previous error
#>   3. error: could not compile `rextendr1`
#> Backtrace:
#>     x
#>  1. +-base::tryCatch(...)
#>  2. | \-base:::tryCatchList(expr, classes, parentenv, handlers)
#>  3. |   \-base:::tryCatchOne(expr, names, parentenv, handlers[[1L]])
#>  4. |     \-base:::doTryCatch(return(expr), name, parentenv, handler)
#>  5. \-rextendr::rust_function("fn invalid syntax(){}", quiet = TRUE)
#>  6.   \-rextendr::rust_source(code = code, env = env, ...)
#>  7.     \-rextendr:::invoke_cargo(...)
#>  8.       \-rextendr:::ui_throw(...)
#> 
#> x `cargo` emitted 3 errors:
#>   1. error: expected one of `(` or `<`, found `syntax`
#>      --> src\lib.rs:3:12
#>       |
#>     3 | fn invalid syntax(){}
#>       |            ^^^^^^ expected one of `(` or `<`
#>   2. error: aborting due to previous error
#>   3. error: could not compile `rextendr1`
```

<sup>Created on 2021-05-13 by the [reprex package](https://reprex.tidyverse.org) (v2.0.0)</sup>

![image](https://user-images.githubusercontent.com/8782986/118118759-04df4580-b3f6-11eb-98d8-f7bd0acdd93f.png)



# Catching error
err <- tryCatch(rextendr::rust_function("fn invalid syntax(){}", quiet = TRUE), error = identity)
# Short form
print(err)
# Long form
summary(err)



library(rextendr)
tryCatch(
  rextendr:::ui_throw(
    "Something bad", 
    rextendr:::bullet_i("Check additional info"), 
    additional_data = list(
      cargo_errors = list(
        errors = c("Simple error", "Error with enforced line\nbreak."),
        warnings = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiatnnulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."
      )
    )  
  ),
  error = identity
) -> err

# Short
print(err)
# Long
summary(err)