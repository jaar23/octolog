# octolog

octolog is a logging library built on top of `std/logging` for multi-threaded logging, it is used `Channel` to queue log message between different thread. 

`start` proc is required to initialize octolog, underneath it will spawn a single thread to listen for log message, then write it to file / stdout / stderr.

```
                                     
[ start log channel ] --> [ log ] --> [ queue in log channel ] ----> [ stdout / stderr ]
                                                                |
                                                                |--> [ file]
 

```

### Install

octolog is not publised to nimble yet. the best way to install now is via github.

```shell
git clone https://github.com/jaar23/octolog.git

cd octolog && nimble install

```

### Getting started

A simple example on how to use library.

``` nim
import octolog, os

# start octolog
start()

info "hello octolog!"
debug "hello octolog!"
warn "hello octolog!"
error "hello octolog!"
notice "hello octolog!"
fatal "hello octolog!"

# stop octolog
stop()
```

you are allow to use `info("some info")` or `info "some info"`.

example output 
```text
[2023-09-03T21:15:03] [INFO] test1:octolog started
[2023-09-03T21:15:03] [INFO] test1:hello octolog!
[2023-09-03T21:15:03] [DEBUG] test1:hello octolog!
[2023-09-03T21:15:03] [WARN] test1:hello octolog!
[2023-09-03T21:15:03] [ERROR] test1:hello octolog!
[2023-09-03T21:15:03] [NOTICE] test1:hello octolog! 
[2023-09-03T21:15:03] [FATAL] test1:hello octolog!
[2023-09-03T21:15:04] [INFO] test1:octolog stopped    
```

### Filelogger

octolog used std filelogger to do file logging, as octolog only running in single thread, it is thread safe for using std/logging here. `start` proc have default `FileLogger` configure for all level. You can modify the behavior like below:


```nim
import octolog

var logLevel: seq[Level] = @[lvlInfo, lvlDebug, lvlError]
start(fileName="octolog", fileloggerlvl=logLevel)

info "hello octolog!!"
debug "hello octolog!!"
error "hello octolog!!"

stop()
```

the example above will write log into 3 different files, info.log. debug.log, and error.log.

- info.log consists of info level log.

- debug.log consists of info, debug, warn, notice, fatal, error log.

- error.log consists of error log.


More configuration on filelogger level, refer to the code example below:

```nim
# default start
start()

# start logging with log file name "octolog.log"
start(fileName="octolog")

# start logging with log file name "octolog.log" but disable file logger, it will not write log into file
start(fileName="octolog", usefilelogger=false)

# start with log level defined and with log file name "octolog.info.log, octolog.xxx.log, ..."
var logLevel: seq[Level] = @[lvlInfo, lvlDebug, lvlError, lvlWarn, lvlFatal, lvlNotice]
start(fileName="octolog", fileloggerlvl=logLevel)
```
