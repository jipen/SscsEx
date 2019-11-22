defmodule SscsEx do
  @moduledoc """
  SscsEx: A Simple Sftp Client/Server written in Elixir.
  See https://hexdocs.pm/elixir/Application.html
  for more information on OTP Applications
  """

  use Application
  require Logger


  def start() do
    SscsEx.Supervisor.start_link()
  end

  def start(_type, _args) do
    SscsEx.Supervisor.start_link()
  end

   @doc """ 
  "Gracefully" stops the SSCS server (close SSH + save failed transfers on disk):
  ## Inputs:
  - None.
  ## Outputs:
  - "Gracefully terminating the SSCS server..."
  """
  def stop() do
    :init.stop()
  end

  # Shortlink to the SscsEx.Server functions

   @doc """ 
  Upload of a local file.
  ## Inputs: 
  - local_path: path of the local file, 
  - remote_path: path of the remote file,
  - host: host name of remote server,
  - port: port number of listening remote server
  ## Outputs: 
  - {:ok, _message_} | {:error, _reason_}
  """
  def send_file(local_path, remote_path, host, port) do
    SscsEx.Server.send_file(local_path, remote_path, host, port)
   end


@doc """ 
  Download of a remote file.
  ## Inputs: 
  - local_path: path of the local file, 
  - remote_path: path of the remote file,
  - host: host name of remote server,
  - port: port number of listening remote server
  ## Outputs: 
  - {:ok, _message_} | {:error, _reason_}
  """
  def get_file(local_path, remote_path, host, port) do
    SscsEx.Server.get_file(local_path, remote_path, host, port)
  end

  @doc """ 
  Resume the upload of a local file.
  ## Inputs: 
  - local_path: path of the local file, 
  - remote_path: path of the remote file,
  - host: host name of remote server,
  - port: port number of listening remote server
  ## Outputs: 
  - {:ok, _message_} | {:error, _reason_}
  """
  def send_file_append(local_path, remote_path, host, port) do
    SscsEx.Server.send_file_append(local_path, remote_path, host, port)
  end

  @doc """ 
  Resume the download of a remote file.
  ## Inputs: 
  - local_path: path of the local file, 
  - remote_path: path of the remote file,
  - host: host name of remote server,
  - port: port number of listening remote server
  ## Outputs: 
  - {:ok, _message_} | {:error, _reason_}
  """
  def get_file_append(local_path, remote_path, host, port) do
    SscsEx.Server.get_file_append(local_path, remote_path, host, port)
  end

  @doc """ 
  Ping a remote server:
  ## Inputs:
  - host: name of remote host,
  - port: port of remote host.
  ## Outputs:
  - {:ok, "SSH Host _host_, _port_ is reachable"} | {:error, "SSH Host _host_, _port_ is unreachable" }
  """
  def ping(host, port) do
    SscsEx.Server.ping(host, port)
  end

  @doc """ 
  Display the configuration of the SSCS server (system variables SSCS_* values):
  ## Inputs:
  - None.
  ## Outputs:
  - List of SSCS_* values
  """
  def get_conf() do
    Application.get_all_env(:sscs_ex) 
    ++ Application.get_all_env(:logger)
  end

  @doc """ 
  Display the list of failed transfers:
  ## Inputs:
  - None.
  ## Outputs:
  - List of transfers
  """
  def display_failed_transfers() do
    SscsEx.Server.display_table()
  end

  @doc """ 
  Remove all failed transfers from the list:
  ## Inputs:
  - None.
  ## Outputs:
  - "Failed transfers table cleaned up."
  """
  def clean_failed_transfers() do
    SscsEx.Server.clean_table()
  end
  
end
