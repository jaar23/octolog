# This is just an example to get you started. You may wish to put all of your
# tests into a single file, or separate them into multiple `test1`, `test2`
# etc. files (better names are recommended, just make sure the name starts with
# the letter 't').
#
# To run these tests, simply execute `nimble test`.

import unittest
from logging import Level
import octolog, os

test "log test":
  start()
  info("hello octolog~")
  info "hello octolog!"
  debug "hello octolog!"
  warn "hello octolog!"
  error "hello octolog!"
  notice "hello octolog!"
  fatal "hello octolog!"
  stop()
  sleep(2000)


test "log test all level":
  var logLevel: seq[Level] = @[lvlInfo, lvlDebug, lvlError, lvlWarn, lvlFatal, lvlNotice]
  start(fileName="octolog", fileloggerlvl=logLevel)
  info "hello octolog!!"
  debug "hello octolog!!"
  error "hello octolog!!"
  warn "hello octolog!!"
  fatal "fatal fatal!!"
  notice "notice here!!"
  stop()
  sleep(2000)


test "disable filelogger":
  start(usefilelogger=false)
  info "hello world!!"
  stop()
