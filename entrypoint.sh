#!/bin/bash

# Hand PID 1 to NetBird's entrypoint so it receives SIGTERM and shuts down
# cleanly, and reshape its logs into the structure Railway expects
exec /usr/local/bin/netbird-entrypoint.sh > >(jq -c -R --unbuffered '
  def level: ascii_downcase
    | if . == "warning" then "warn"
      elif . == "fatal" or . == "panic" then "error"
      elif . == "trace" then "debug"
      else . end;

  # gRPC library logs are passed through as a message with their own
  # timestamp and level, e.g. "2026/09/30 02:09:33 WARNING: [core] ..."
  def grpc: . as $log
    | ([$log.message | capture("^[0-9/]+ [0-9:]+ (?<level>[A-Z]+): (?<message>.*)$")] | first) as $match
    | if $match then $log + {level: ($match.level | level), message: $match.message} else $log end;

  . as $line
  | (try fromjson catch null) as $json
  | if ($json | type) == "object" then
      ($json | del(.msg, .level, .time, .file, .func)) + {
        level: ($json.level // "info" | level),
        message: ($json.msg // ""),
      }
      | grpc
    else
      # The entrypoint script logs as "<timestamp> <LEVEL> <source>: <message>"
      ([$line | capture("^[0-9T:+-]+Z? (?<level>[A-Z]+) (?<message>.*)$")] | first) as $match
      | if $match then
          {level: ($match.level | level), message: $match.message}
        else
          {
            level: (
              if ($line | test("error|failed|fatal"; "i")) then "error"
              elif ($line | test("^warning"; "i")) then "warn"
              else "info" end
            ),
            message: $line,
          }
        end
    end') 2>&1
