## octolog is a logging library built on top of `std/logging` for multi-threaded logging, it is used `channels` to queue log message between different thread, then write to file or stdout.
##
## `start` proc is required to initialize octolog, underneath it will spawn a single thread to listen for log message, then write it to file / stdout / stderr.
## 
## .. note::
##    you should activate thread support when using this library, include `--threads:on` in config.nims or build command
##
## ## Basic usage
##
## A simple example on how to use library.
##
## ```nim
## import octolog, os
##
## # start octolog
## octologStart()
##
## info "hello octolog!"
## debug "hello octolog!"
## warn "hello octolog!"
## error "hello octolog!"
## notice "hello octolog!"
## fatal "hello octolog!"
##
## # stop octolog
## octologStop()
## ```
##
## you are allow to use `info("some info")` or `info "some info"`.
##
## In this example, a log file with current datetime will be created, for example, `202404052020.log`, you can initialize `octologStart` with different configuration.
##
##

import colors, terminal, strutils, times
import malebolgia
from logging import 
  Filelogger, Level, newFileLogger, substituteLog, log, LevelNames, 
  RollingFileLogger, newRollingFileLogger


var
  # Threading
  threadMaster = createMaster()
  logChannel: Channel[string]
  threadId: int
  # configuration
  useStderr: bool = false
  printToConsole: bool = true
  writeToLogfile: bool = true
  isRunning: bool = true
  # File Logger config
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


proc configureFileLogger(fileName: string, levelThreshold: Level, fmt = "";
                          rolling: bool = false; maxLines: Positive = 1000; bufSize: int = -1;) =
  if levelThreshold == lvlInfo:
    infoFileLogger = if rolling: newRollingFileLogger(fileName, levelThreshold = lvlInfo, 
                                                      maxLines=maxLines, bufSize=bufSize, 
                                                      fmtStr = fmt, flushThreshold = lvlInfo) 
      else: newFileLogger(fileName, levelThreshold = lvlInfo, flushThreshold = lvlInfo, fmtStr = fmt)
    enableInfoFileLogger = true
  elif levelThreshold == lvlDebug:
    debugFileLogger = if rolling: newRollingFileLogger(fileName, levelThreshold = lvlDebug, 
                                                       maxLines=maxLines, bufSize=bufSize, 
                                                       fmtStr = fmt, flushThreshold = lvlDebug) 
      else: newFileLogger(fileName, levelThreshold = lvlDebug, flushThreshold = lvlDebug, fmtStr = fmt)
    enableDebugFileLogger = true
  elif levelThreshold == lvlError:
    errorFileLogger = if rolling: newRollingFileLogger(fileName, levelThreshold = lvlError, 
                                                       maxLines=maxLines, bufSize=bufSize, 
                                                       fmtStr = fmt, flushThreshold = lvlError) 
      else: newFileLogger(fileName, levelThreshold = lvlError, flushThreshold = lvlError, fmtStr = fmt)
    enableErrorFileLogger = true
  elif levelThreshold == lvlFatal:
    fatalFileLogger = if rolling: newRollingFileLogger(fileName, levelThreshold = lvlFatal, 
                                                       maxLines=maxLines, bufSize=bufSize, 
                                                       fmtStr = fmt, flushThreshold = lvlFatal) 
      else: newFileLogger(fileName, levelThreshold = lvlFatal, flushThreshold = lvlFatal, fmtStr = fmt)
    enableFatalFileLogger = true
  elif levelThreshold == lvlNotice:
    noticeFileLogger = if rolling: newRollingFileLogger(fileName, levelThreshold = lvlNotice, 
                                                        maxLines=maxLines, bufSize=bufSize, 
                                                        fmtStr = fmt, flushThreshold = lvlNotice) 
      else: newFileLogger(fileName, levelThreshold = lvlNotice, flushThreshold = lvlNotice, fmtStr = fmt)
    enableNoticeFileLogger = true
  elif levelThreshold == lvlWarn:
    warnFileLogger = if rolling: newRollingFileLogger(fileName, levelThreshold = lvlWarn, 
                                                      maxLines=maxLines, bufSize=bufSize, 
                                                      fmtStr = fmt, flushThreshold = lvlWarn) 
      else: newFileLogger(fileName, levelThreshold = lvlWarn, flushThreshold = lvlWarn, fmtStr = fmt)
    enableWarnFileLogger = true
  elif levelThreshold == lvlAll:
    fileLogger = if rolling: newRollingFileLogger(fileName, levelThreshold = lvlAll, 
                                                  fmtStr = fmt,
                                                  maxLines=maxLines, bufSize=bufSize) 
      else: newFileLogger(fileName, levelThreshold = lvlAll, fmtStr = fmt)
    enableFileLogger = true
  else:
    fileLogger = if rolling: newRollingFileLogger(fileName, levelThreshold = lvlNone, 
                                                  fmtStr = fmt,
                                                  maxLines=maxLines, bufSize=bufSize) 
      else: newFileLogger(fileName, levelThreshold = lvlNone, fmtStr = fmt)
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


proc fmtLine(fmt: string = "[$datetime] [$levelname] $[$threadid] $appname : ",
    level: Level, msgs: varargs[string, `$`]): string =
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



proc log2Channel(level: Level, msg: string) =
  let line = LevelNames[level] & "|@|" & msg
  let sent = logChannel.trySend(line)
  if not sent:
    let line = fmtLine(level = lvlInfo, msgs = "octolog unable to queue log message.")
    stdout.writeLine line


proc octolog*(level: Level, msg: string) =
  ## **Example**
  ## .. code-block::
  ##   octolog(lvlInfo, "hello, there...")
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


proc collector(fmt: string = "[$datetime] [$levelname] $[$threadid] $appname : ") {.thread.} =
  try:
    while isRunning:
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
      let line = fmtLine(fmt = fmt, level = level, msgs = msg)
      if printToConsole:
        if useStderr:
          stderr.writeLine line
        else:
          stdout.writeLine line
      if writeToLogfile:
        {.cast(gcsafe).}:
          log2File(line)
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


proc octologStart*(fileName = now().format("yyyyMMddHHmm"); 
                   useFileLogger = true;
                   fileLoggerLvl: seq[Level] = @[lvlNone];
                   useConsoleLogger = true;
                   skipInitLog = false; 
                   fileRolling = false;
                   maxLines = 1000;
                   bufSize = -1;
                   fmt = "[$datetime] [$levelname] $[$threadid] $appname : "): void =
  ## Start octolog thread with default configuration in background. 
  ## 
  ## **Example:**
  ##
  ##
  ## .. code-block::
  ##   octologStart()
  ##
  ## Start octolog thread without using file logger.
  ##
  ## **Example:**
  ##
  ##
  ## .. code-block::
  ##   octologStart(useFileLogger=false)
  ## 
  ## Start octolog thread using rolling file logger.
  ##
  ## **Example:**
  ##
  ##
  ## .. code-block::
  ##   octologStart(fileRolling=true)
  ## Start octolog thread with a different log format. Default format is \"\[$datetime\] \[$levelname\] \[$threadid\] \$appname : \"
  ## 
  ## **Example:**
  ##
  ##
  ## .. code-block::
  ##   octologStart(fmt="[$datetime] [$levelname]: ")
  ##
  ## Start octolog thread with logging different log level file.
  ##
  ## **Example:**
  ##
  ##
  ## .. code-block::
  ##   octologStart(fileLoggerLvl=@[lvlInfo, lvlDebug, lvlError])
  ##
  logChannel.open()
  threadId = getThreadId()
  var logfile = fileName.replace(".log", "")

  writeToLogfile = usefilelogger
  printToConsole = useconsolelogger

  if usefileLogger:
    if lvlInfo in fileloggerlvl:
      configureFileLogger(logfile & ".info" & ".log", levelThreshold = lvlInfo, 
                          rolling = fileRolling, maxLines = maxLines, bufSize = bufSize)

    if lvlDebug in fileloggerlvl:
      configureFileLogger(logfile & ".debug" & ".log", levelThreshold = lvlAll,
                          rolling = fileRolling, maxLines = maxLines, bufSize = bufSize)

    if lvlError in fileloggerlvl:
      configureFileLogger(logfile & ".error" & ".log", levelThreshold = lvlError,
                          rolling = fileRolling, maxLines = maxLines, bufSize = bufSize)

    if lvlFatal in fileloggerlvl:
      configureFileLogger(logfile & ".fatal" & ".log", levelThreshold = lvlFatal,
                          rolling = fileRolling, maxLines = maxLines, bufSize = bufSize)

    if lvlNotice in fileloggerlvl:
      configureFileLogger(logfile & ".notice" & ".log", levelThreshold = lvlNotice,
                          rolling = fileRolling, maxLines = maxLines, bufSize = bufSize)

    if lvlWarn in fileloggerlvl:
      configureFileLogger(logfile & ".warn" & ".log", levelThreshold = lvlWarn,
                          rolling = fileRolling, maxLines = maxLines, bufSize = bufSize)

    if lvlAll in fileloggerlvl or lvlNone in fileloggerlvl:
      configureFileLogger(logfile & ".log", levelThreshold = lvlAll,
                          rolling = fileRolling, maxLines = maxLines, bufSize = bufSize)

  threadMaster.spawn collector(fmt)
  if not skipInitLog:
    let line = fmtLine(level = lvlInfo, msgs = "octolog started")
    stdout.write line


proc octologStop*(skipEndLog = false): void =
  ## When stopping octolog thread, it will wait for all the log message clear in the channel before exit.
  ## If there are too many message inside it, it may take some time before it is really exiting it.
  # grace period before shutting down
  if logChannel.peek() > 0:
    let line = fmtLine(level = lvlInfo, msgs = "write pending log before exit octolog")
    stdout.writeLine line
  while logChannel.peek() > 0:
    if logChannel.peek() == 0:
      logChannel.close()
      break
  isRunning = false
  if not skipEndLog:
    let line = fmtLine(level = lvlInfo, msgs = "octolog stopped!")
    stdout.writeLine line
  threadMaster.cancel()


template info*(msg: string) =
  ## 
  ## Logging your message with template style.
  ## 
  ## **Example:**
  ##
  ##
  ## .. code-block::
  ##   info "hello, there..."
  ## 
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

