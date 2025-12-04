package log

import (
	"errors"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"strings"

	"github.com/DeRuina/timberjack"

	charmLog "github.com/charmbracelet/log"
	"github.com/samber/slog-multi"
)

const (
	LevelDebug = slog.LevelDebug
	LevelInfo  = slog.LevelInfo
	LevelWarn  = slog.LevelWarn
	LevelError = slog.LevelError
)

var toLogLevel = map[string]slog.Level{
	"DEBUG": LevelDebug,
	"INFO":  LevelInfo,
	"WARN":  LevelWarn,
	"ERROR": LevelError,
}

var toCharmLogLevel = map[slog.Level]charmLog.Level{
	LevelDebug: charmLog.DebugLevel,
	LevelInfo:  charmLog.InfoLevel,
	LevelWarn:  charmLog.WarnLevel,
	LevelError: charmLog.ErrorLevel,
}
var handlers []slog.Handler
var charmLoggers []*charmLog.Logger

func ParseLogLevel(value string) (slog.Level, error) {
	if level, ok := toLogLevel[strings.ToUpper(value)]; !ok {
		return level, errors.New(fmt.Sprintf("unknown log level: %s", value))
	} else {
		return level, nil
	}
}

func SetLevel(level slog.Level) (oldLevel slog.Level) {
	oldLevel = slog.SetLogLoggerLevel(level)
	for _, logger := range charmLoggers {
		logger.SetLevel(toCharmLogLevel[level])
	}
	if level != oldLevel {
		slog.Debug("changed log-level", "old", oldLevel, "new", level)
	}
	return
}

func Reconfigure(logFiles []string, logLevel string) (err error) {
	var level slog.Level
	if level, err = ParseLogLevel(logLevel); err != nil {
		return
	}
	opts := slog.HandlerOptions{
		AddSource: true,
		Level:     level,
	}
	slog.SetDefault(slog.New(slog.NewTextHandler(os.Stderr, &opts)))

	charmOptions := charmLog.Options{
		ReportTimestamp: true,
		TimeFunction:    charmLog.NowUTC,
		TimeFormat:      "2006-01-02T15:04:05.999Z07:00",
		Formatter:       charmLog.TextFormatter,
		Level:           toCharmLogLevel[level],
		ReportCaller:    opts.AddSource,
	}

	for _, logFile := range logFiles {
		switch logFile {
		case "-":
			logFile = "<stderr>"
			logger := charmLog.NewWithOptions(os.Stderr, charmOptions)
			charmLoggers = append(charmLoggers, logger)
			handlers = append(handlers, logger)
		default:
			err = os.MkdirAll(filepath.Dir(logFile), 0o750)
			if err != nil {
				return
			}
			handlers = append(handlers, slog.NewJSONHandler(&timberjack.Logger{
				Filename:    logFile,
				FileMode:    0o640,
				MaxSize:     5,
				MaxBackups:  10,
				Compression: "gzip",
				LocalTime:   false,
			}, &opts))
		}
		slog.Debug("configured logging file", "file", logFile)
	}

	slog.SetDefault(slog.New(slogmulti.Fanout(handlers...)))
	// level could have changed by loading a file
	if level, err = ParseLogLevel(logLevel); err != nil {
		return
	}
	SetLevel(level)
	slog.Debug("configured logging")
	return
}
