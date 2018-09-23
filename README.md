
<!--!#echo json="package.json" key="name" underline="=" -->
re:tardis
=========
<!--/#echo -->

<!--#echo json="package.json" key="description" -->
Sync time with your HTTP server, `apt-cacher-ng` or anything else that speaks
the Hapless Timestamp Transfer Protocol.
<!--/#echo -->



Options
-------

Configuration is read in this order, last value wins:
  * `$HOME/.adjtime-http.ini`
  * `$HOME/.config/adjtime-http.ini`
  * command line (`--option=value`)

CLI-options:

```text
$ adjtime-http --help
H: INI settings can be overridden with `--option=value`. To see the defaults, give `about:defaults.ini` as only argument.
H: Additional options: --quiet --verbose
```

INI options:

<!--#include file="defaults.ini" code="ini" start="" -->
<!--#verbatim lncnt="23" -->
```ini
[re:tardis]
tries       = 3
; ^-- how many attempts per server
min-delta   = 5
; ^-- [seconds] Don't adjust if time differs less than this.
max-delta   = 12 * 3600
; ^-- [seconds] If time differs more than this, assume server error.
no-timezone = GMT
; ^-- Which timezone to assume if not specified by server.
user-agent  = adjtime-http/0.2 (re:tardis)
http-method = HEAD
net-timeout = 30
default-url = /cgi-bin/date-header
noadjust-rv = 0
; ^-- Select a custom return value to indicate that time differed
;     less than min-delta. Numbers 30..69 are reserved for this.
noadjust-kw =
; ^-- In above case, print this keyword to on a line by itself.
adjusted-rv = 0
adjusted-kw =
; ^-- Like noadjust-{rv,kw} but for when time has been adjusted.
```
<!--/include-->


<!--#toc stop="scan" -->



Known issues
------------

* Needs more/better tests and docs.


Q&A
---
  * __Why the name?__ It's yet another tool among thousands for the purpose,
    built from scratch, so it's a re-invention, and it follows in the
    footsteps of the [famous][ntpv-tardis] "Tardis" shareware.




&nbsp;

  [ntpv-tardis]: https://en.wikipedia.org/w/?oldid=707712214#Tardis_and_Trinity_College.2C_Dublin

License
-------
<!--#echo json="package.json" key=".license" -->
GPL-3.0-or-later
<!--/#echo -->
