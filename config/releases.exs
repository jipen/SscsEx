import Config

config :logger, :file_log,
  path: System.get_env("SSCS_LOG_FILE") || System.get_env("RELEASE_ROOT") <> "/log/sscs_ex.log",
  level: :debug

config :logger, :console,
  level: :info

config :sscs_ex, :ssh_conf,
  # Port for the sftp server
  port: String.to_integer(System.get_env("SSCS_PORT") || "5555"),
  #root dir for <username>:
  root_dir: System.get_env("SSCS_ROOT_DIR") || System.get_env("RELEASE_ROOT") <> "/sftp",
  #look for authorized_keys at :
  user_dir: System.get_env("SSCS_AUTH_DIR") ||  System.get_env("RELEASE_ROOT") <> "/sftp/.ssh",
  #Where to look for ssh host keys :
  system_dir: System.get_env("SSCS_SYSTEM_DIR") || System.get_env("RELEASE_ROOT") <> "/sftp/ssh_daemon"

  config :sscs_ex, :transfer_conf,
  # Size in bytes of chunks when transfers are done by streaming - default = 2 MB :
  stream_bytes: String.to_integer(System.get_env("SSCS_STREAM_BYTES") || "2097152"),
  # Verify integrity of files ?
  integrity_check: String.to_existing_atom(System.get_env("SSCS_INTEGRITY_CHECK") || "true"),
  # Type of checksum (used by functions *_streamed_checksum):
  # Type can be : "sha", "sha224" "sha256","sha384","sha512","sha3_224", "sha3_256","sha3_384","sha3_512",
  # "blake2b", "blake2s", "md5", "md4".
  crc_type: String.to_atom(System.get_env("SSCS_CHECKSUM_TYPE") || "sha256"),
  # Overwrite file when downloading/uploading ?
  # Value should be "true" or "false"
  overwrite: String.to_existing_atom(System.get_env("SSCS_OVERWRITE") || "false"),
  # Max number of retries when a transfer fails - Default = 3 times:
  max_retries: String.to_integer(System.get_env("SSCS_RETRIES") || "3"),
  # Time between two retries in milliseconds - Default = 3 minutes:
  temp_retry: String.to_integer(System.get_env("SSCS_TEMP_RETRY") || "180000")