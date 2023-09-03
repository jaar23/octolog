import logging, colors, terminal, strutils, times
import threadpool, locks


var
  runningLock: Lock
  logChannel: Channel[string]
  useStderr: bool = false
  threadId: int
  isRunning {.guard: runningLock.}: bool = true
  infoFileLogger: FileLogger
  debugFileLogger: FileLogger
  errorFileLogger: FileLogger
  fileLogger: FileLogger
  enableFileLogger = true
  enableInfoFileLogger = false
  enableErrorFileLogger = false
  enableDebugFileLogger = false

const LogColors: array[Level, Color] = [colWhiteSmoke, colWhiteSmoke, colLightBlue, colLimeGreen, colOrange, colOrangeRed, colRed, colWhite]

proc configureFileLogger*(fileName: string, levelThreshold: Level) =
  if levelThreshold == lvlInfo:
    infoFileLogger = newFileLogger(fileName, levelThreshold=lvlInfo)
    enableInfoFileLogger = true
  elif levelThreshold == lvlDebug:
    debugFileLogger = newFileLogger(fileName, levelThreshold=lvlDebug)
    enableDebugFileLogger = true
  elif levelThreshold == lvlError:
    errorFileLogger = newFileLogger(fileName, levelThreshold=lvlError)
    enableErrorFileLogger = true
  else:
    fileLogger = newFileLogger(fileName, levelThreshold=lvlAll)
    enableFileLogger = true


proc enableFileLoggerLevel*(levelThreshold: Level) =
  if levelThreshold == lvlInfo:
    enableInfoFileLogger = true
  elif levelThreshold == lvlDebug:
    enableDebugFileLogger = true
  elif levelThreshold == lvlError:
    enableErrorFileLogger = true
  else:
    enableFileLogger = true


proc disableFileLoggerLevel*(levelThreshold: Level) =
  if levelThreshold == lvlInfo:
    enableInfoFileLogger = false
  elif levelThreshold == lvlDebug:
    enableDebugFileLogger = false
  elif levelThreshold == lvlError:
    enableErrorFileLogger = false
  else:
    enableFileLogger = false


proc fmtLine(fmt: string = "[$datetime] [$levelname] $appname:", level: Level, msgs: varargs[string, `$`]): string =
  let
    color = ansiForegroundColorCode(LogColors[level])
    cdef = ansiForegroundColorCode(fgDefault)
    #lvlname = LevelNames[level]
    #spaces = " ".repeat("NOTICE".len - lvlname.len)
    spaces = ""
    fmt = fmt.multiReplace(("$levelname", color & "$levelname" & cdef & spaces), ("$levelid", color & "$levelid" & cdef))
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

  if enableFileLogger:
    fileLogger.log(lvlAll, unfmtLine(lvlAll, msg))



proc log*(level: Level, msgs: varargs[string, `$`]) =
  let line = fmtLine(level=level, msgs=msgs)
  let sent = logChannel.trySend(line)
  if not sent:
    logChannel.send(line)
  #log2File($msgs)


proc info*(msg: varargs[string, `$`]) =
  log(lvlInfo, msg)


proc debug*(msg: varargs[string, `$`]) =
  log(lvlDebug, msg)


proc notice*(msg: varargs[string, `$`]) =
  log(lvlNotice, msg)


proc warn*(msg: varargs[string, `$`]) =
  log(lvlWarn, msg)


proc error*(msg: varargs[string, `$`]) =
  log(lvlError, msg)


proc fatal*(msg: varargs[string, `$`]) =
  log(lvlFatal, msg)


proc collector() {.thread.} =
  try:
    var running = true
    withLock runningLock:
      running = isRunning
    while running:
      let (hasData, msg) = logChannel.tryRecv()
      if hasData:
        if octolog.useStderr: 
          stderr.writeLine msg
        else: 
          stdout.writeLine msg
        {.cast(gcsafe).}:
          log2File(msg)
      withLock runningLock:
        running = isRunning
  except:
    {.cast(gcsafe).}:
      log(lvlError, getCurrentExceptionMsg())
  finally:
   {.cast(gcsafe).}:
      log(lvlInfo, "octolog collector stopped")


proc start*(fileName = now().format("yyyyMMddHHmm"), filelogger:bool = true, fileloggerlvl: seq[Level] = @[lvlAll]): void =
  logChannel.open()
  threadId = getThreadId()
  var logfile = fileName
  if fileLogger:
    if ".log" in fileName:
      logfile = fileName.replace(".log", "")

    logfile = logfile & ".log"
    if lvlInfo in fileloggerlvl:
      configureFileLogger(logfile, levelThreshold=lvlInfo)
    
    if lvlDebug in fileloggerlvl:
      configureFileLogger(logfile, levelThreshold=lvlDebug)

    if lvlError in fileloggerlvl:
      configureFileLogger(logfile, levelThreshold=lvlError)

    if lvlAll in fileloggerlvl:
      configureFileLogger(logfile, levelThreshold=lvlAll)

  spawn collector()
  info("octolog started")


proc stop*(): void =
  withLock runningLock:
    isRunning = false
  logChannel.close()
  let line = fmtLine(level=lvlInfo, msgs="octolog stopped")
  stdout.writeLine line


