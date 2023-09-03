import colors, terminal, strutils, times
import threadpool, locks, os
from logging import Filelogger, Level, newFileLogger, substituteLog, log


var
  runningLock: Lock
  logChannel: Channel[string]
  useStderr: bool = false
  threadId: int
  isRunning {.guard: runningLock.}: bool = true
  infoFileLogger: FileLogger
  debugFileLogger: FileLogger
  errorFileLogger: FileLogger
  fatalFileLogger: FileLogger
  warnFileLogger: FileLogger
  noticeFileLogger: FileLogger
  fileLogger: FileLogger
  enableFileLogger = false
  enableInfoFileLogger = false
  enableErrorFileLogger = false
  enableDebugFileLogger = false
  enableFatalFileLogger = false
  enableWarnFileLogger = false
  enableNoticeFileLogger = false

const LogColors: array[Level, Color] = [colWhiteSmoke, colWhiteSmoke,
    colLightBlue, colLimeGreen, colOrange, colOrangeRed, colRed, colWhite]

proc configureFileLogger*(fileName: string, levelThreshold: Level) =
  if levelThreshold == lvlInfo:
    infoFileLogger = newFileLogger(fileName, levelThreshold = lvlInfo,
        flushThreshold = lvlInfo)
    enableInfoFileLogger = true
  elif levelThreshold == lvlDebug:
    debugFileLogger = newFileLogger(fileName, levelThreshold = lvlDebug,
        flushThreshold = lvlDebug)
    enableDebugFileLogger = true
  elif levelThreshold == lvlError:
    errorFileLogger = newFileLogger(fileName, levelThreshold = lvlError,
        flushThreshold = lvlError)
    enableErrorFileLogger = true
  elif levelThreshold == lvlFatal:
    fatalFileLogger = newFileLogger(fileName, levelThreshold = lvlError)
    enableFatalFileLogger = true
  elif levelThreshold == lvlNotice:
    noticeFileLogger = newFileLogger(fileName, levelThreshold = lvlNotice)
    enableNoticeFileLogger = true
  elif levelThreshold == lvlWarn:
    warnFileLogger = newFileLogger(fileName, levelThreshold = lvlWarn)
    enableWarnFileLogger = true
  else:
    fileLogger = newFileLogger(fileName, levelThreshold = lvlAll)
    enableFileLogger = true


proc enableFileLoggerLevel*(levelThreshold: Level) =
  if levelThreshold == lvlInfo:
    enableInfoFileLogger = true
  elif levelThreshold == lvlDebug:
    enableDebugFileLogger = true
  elif levelThreshold == lvlError:
    enableErrorFileLogger = true
  elif levelThreshold == lvlFatal:
    enableFatalFileLogger = true
  elif levelThreshold == lvlNotice:
    enableNoticeFileLogger = true
  elif levelThreshold == lvlWarn:
    enableWarnFileLogger = true
  else:
    enableFileLogger = true


proc disableFileLoggerLevel*(levelThreshold: Level) =
  if levelThreshold == lvlInfo:
    enableInfoFileLogger = false
  elif levelThreshold == lvlDebug:
    enableDebugFileLogger = false
  elif levelThreshold == lvlError:
    enableErrorFileLogger = false
  elif levelThreshold == lvlFatal:
    enableFatalFileLogger = false
  elif levelThreshold == lvlNotice:
    enableNoticeFileLogger = false
  elif levelThreshold == lvlWarn:
    enableWarnFileLogger = false
  else:
    enableFileLogger = false


proc fmtLine(fmt: string = "[$datetime] [$levelname] $appname: ", level: Level,
    msgs: varargs[string, `$`]): string =
  let
    color = ansiForegroundColorCode(LogColors[level])
    cdef = ansiForegroundColorCode(fgDefault)
    #lvlname = LevelNames[level]
    #spaces = " ".repeat("NOTICE".len - lvlname.len)
    spaces = ""
    fmt = fmt.multiReplace(("$levelname", color & "$levelname" & cdef & spaces),
        ("$levelid", color & "$levelid" & cdef))
    line = substituteLog(fmt, level, msgs)
  return line


proc unfmtLine(level: Level, msg: string): string =
  var line = msg
  let cdef = ansiForegroundColorCode(fgDefault)
  line = line.replace(cdef)
  for lvl in LogColors:
    line = line.replace(ansiForegroundColorCode(lvl))
  return line


proc log2File(msg: string): void =
  if enableInfoFileLogger and "INFO" in msg:
    infoFileLogger.log(lvlInfo, unfmtLine(lvlInfo, msg))

  if enableDebugFileLogger and "DEBUG" in msg:
    debugFileLogger.log(lvlDebug, unfmtLine(lvlDebug, msg))

  if enableErrorFileLogger and "ERROR" in msg:
    errorFileLogger.log(lvlError, unfmtLine(lvlError, msg))

  if enableFatalFileLogger and "FATAL" in msg:
    fatalFileLogger.log(lvlFatal, unfmtLine(lvlFatal, msg))

  if enableNoticeFileLogger and "NOTICE" in msg:
    noticeFileLogger.log(lvlNotice, unfmtLine(lvlNotice, msg))

  if enableWarnFileLogger and "WARN" in msg:
    warnFileLogger.log(lvlWarn, unfmtLine(lvlWarn, msg))

  if enableFileLogger:
    fileLogger.log(lvlAll, unfmtLine(lvlAll, msg))



proc log2Channel*(level: Level, msgs: varargs[string, `$`]) =
  let line = fmtLine(level = level, msgs = msgs)
  let sent = logChannel.trySend(line)
  if not sent:
    logChannel.send(line)


proc olog*(level: Level, msgs: varargs[string, `$`]) =
  log2Channel(level, msgs)

proc info(msg: varargs[string, `$`]) =
  log2Channel(lvlInfo, msg)


proc debug(msg: varargs[string, `$`]) =
  log2Channel(lvlDebug, msg)


proc notice(msg: varargs[string, `$`]) =
  log2Channel(lvlNotice, msg)


proc warn(msg: varargs[string, `$`]) =
  log2Channel(lvlWarn, msg)


proc error(msg: varargs[string, `$`]) =
  log2Channel(lvlError, msg)


proc fatal(msg: varargs[string, `$`]) =
  log2Channel(lvlFatal, msg)


proc collector() {.thread.} =
  try:
    var running = true
    withLock runningLock:
      running = isRunning
    while running:
      let (hasData, msg) = logChannel.tryRecv()
      if hasData:
        if useStderr:
          stderr.writeLine msg
        else:
          stdout.writeLine msg
        {.cast(gcsafe).}:
          log2File(msg)
      withLock runningLock:
        running = isRunning
  except:
    let line = fmtLine(level = lvlInfo, msgs = getCurrentExceptionMsg())
    stdout.writeLine line
    {.cast(gcsafe).}:
      log2File(line)
  finally:
    let line = fmtLine(level = lvlInfo, msgs = "octolog collector stopped\n")
    stdout.writeLine line
    {.cast(gcsafe).}:
      log2File(line)


proc start*(fileName = now().format("yyyyMMddHHmm"), usefilelogger: bool = true,
    fileloggerlvl: seq[Level] = @[lvlAll]): void =
  logChannel.open()
  threadId = getThreadId()
  var logfile = fileName.replace(".log", "")
  if usefileLogger:
    if lvlInfo in fileloggerlvl:
      configureFileLogger(logfile & ".info" & ".log", levelThreshold = lvlInfo)

    if lvlDebug in fileloggerlvl:
      configureFileLogger(logfile & ".debug" & ".log", levelThreshold = lvlAll)

    if lvlError in fileloggerlvl:
      configureFileLogger(logfile & ".error" & ".log",
          levelThreshold = lvlError)

    if lvlFatal in fileloggerlvl:
      configureFileLogger(logfile & ".fatal" & ".log",
          levelThreshold = lvlFatal)

    if lvlNotice in fileloggerlvl:
      configureFileLogger(logfile & ".notice" & ".log",
          levelThreshold = lvlNotice)

    if lvlWarn in fileloggerlvl:
      configureFileLogger(logfile & ".warn" & ".log", levelThreshold = lvlWarn)

    if lvlAll in fileloggerlvl:
      configureFileLogger(logfile & ".log", levelThreshold = lvlAll)

  spawn collector()
  info("octolog started")


proc stop*(): void =
  # grace period before shutting down
  sleep(1000)
  withLock runningLock:
    isRunning = false
  while logChannel.peek() == 0:
    logChannel.close()
  let line = fmtLine(level = lvlInfo, msgs = "octolog stopped")
  stdout.writeLine line


template info*(msg: varargs[string, `$`]) =
  info(msg)

template debug*(msg: varargs[string, `$`]) =
  debug(msg)

template warn*(msg: varargs[string, `$`]) =
  warn(msg)

template error*(msg: varargs[string, `$`]) =
  error(msg)

template notice*(msg: varargs[string, `$`]) =
  notice(msg)

template fatal*(msg: varargs[string, `$`]) =
  fatal(msg)

