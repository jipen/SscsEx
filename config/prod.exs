# use Mix.Config
# Elixir 1.9.0 =>
import Config

config :logger, :file_log,
  path: System.get_env("SSCS_LOG_FILE") || "log/sscs_ex.log",
  level: :info

config :logger, :console,
  level: :info