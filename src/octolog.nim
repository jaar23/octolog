import colors, terminal, strutils, times
import threadpool, locks, os
from logging import Filelogger, Level, newFileLogger, substituteLog, log, LevelNames


var
  runningLock: Lock
  logChannel: Channel[string]
  useStderr: bool = false
  printToConsole: bool = true
  writeToLogfile: bool = true
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


proc fmtLine(fmt: string = "[$datetime] [$levelname] $[$threadid] $appname : ", level: Level,
    msgs: varargs[string, `$`]): string =
  let
    color = ansiForegroundColorCode(LogColors[level])
    cdef = ansiForegroundColorCode(fgDefault)
    lvlname = LevelNames[level]
    spaces = " ".repeat("NOTICE".len - lvlname.len)
    #spaces = ""
    fmt = fmt.multiReplace(("$levelname", color & "$levelname" & cdef & spaces),
        ("$levelid", color & "$levelid" & cdef), ("$threadid", $getThreadId()))
  let line = substituteLog(fmt, level, msgs)

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



proc log2Channel*(level: Level, msg: string) =
  let line = LevelNames[level] & "|@|" & msg
  let sent = logChannel.trySend(line)
  if not sent:
    echo "not sent"


proc olog*(level: Level, msg: string) =
  log2Channel(level, msg)

proc info(msg: string) =
  log2Channel(lvlInfo, msg)


proc debug(msg: string) =
  log2Channel(lvlDebug, msg)


proc notice(msg: string) =
  log2Channel(lvlNotice, msg)


proc warn(msg: string) =
  log2Channel(lvlWarn, msg)


proc error(msg: string) =
  log2Channel(lvlError, msg)


proc fatal(msg: string) =
  log2Channel(lvlFatal, msg)


proc collector() {.thread.} =
  try:
    var running = true
    withLock runningLock:
      running = isRunning
    while running:
      let data = logChannel.recv()
      let tempMsg = data.split("|@|")
      if tempMsg.len < 2:
        raise newException(IOError, "log message unable to parse, |@| is a keyword")
      let lvl = tempMsg[0]
      let msg = tempMsg[1]
      var level = lvlNone
      case lvl:
        of "INFO":
          level = lvlInfo
        of "DEBUG":
          level = lvlDebug
        of "WARN":
          level = lvlWarn
        of "ERROR":
          level = lvlError
        of "FATAL":
          level = lvlFatal
        of "NOTICE":
          level = lvlNotice
        else:
          level = lvlNone
      let line = fmtLine(level=level, msgs=msg)
      if printToConsole:
        if useStderr:
          stderr.writeLine line
        else:
          stdout.writeLine line
      if writeToLogfile:
        {.cast(gcsafe).}:
          log2File(line)
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


proc octologStart*(fileName = now().format("yyyyMMddHHmm"), usefilelogger: bool = true,
                   fileloggerlvl: seq[Level] = @[lvlAll], useconsolelogger: bool = true): void =
  log_channel.open()
  threadId = getThreadId()
  var logfile = fileName.replace(".log", "")
  
  writeToLogfile = usefilelogger
  printToConsole = useconsolelogger

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


proc octologStop*(): void =
  # grace period before shutting down
  sleep(1000)
  withLock runningLock:
    isRunning = false
  while logChannel.peek() == 0:
    logChannel.close()
  let line = fmtLine(level = lvlInfo, msgs = "octolog stopped")
  stdout.writeLine line


template info*(msg: string) =
  info(msg)


template debug*(msg: string) =
  debug(msg)


template warn*(msg: string) =
  warn(msg)

template error*(msg: string) =
  error(msg)

template notice*(msg: string) =
  notice(msg)

template fatal*(msg: string) =
  fatal(msg)

