defmodule SscsEx.Client do
  @moduledoc """
Functions for the client side of the SscsEx server.
"""

  alias SscsEx.SFTP
  require Logger
  alias SscsEx.PreTransfer
  alias SscsEx.Files
  alias SscsEx.SFTP
  alias UUID
  alias SscsEx.Append

  # NEVER SET module attributes for runtime use as they are set once at compile time and NEVER changed after !!! 
  # https://ropig.com/blog/be-careful-when-using-elixirs-module-attributes/
  # In our case, do not set: 
  # @stream_bytes Application.get_env(:sscs_ex, :transfer_conf)[:stream_bytes] 
  # As Application.get_env(:sscs_ex, :transfer_conf) refers to System.get_env("SSCS_STREAM_BYTES"), which can be modified !!!


   @doc """ 
  Test if a local file and a remote file have the same checksum.
  ## Inputs:
  - connection: the SSH connection,
  - local_path: the path of the local file,
  - remote_path: the path of the remote file,
  - crc_type: Type of checksum choosen (:sha, :sha224, :sha256, :sha384, :sha512, :sha3_224, :sha3_256, :sha3_384, :sha3_512, :blake2b, :blake2s, :md5 or :md4)
  ## Outputs:
   - {:ok, <local file checksum>, <remote file checksum>} | {:error, <local file checksum>, <remote file checksum>}
  """

  def test_checksum(connection, local_path, remote_path, crc_type) do
    {:ok, remote_crc} = SFTP.file_checksum(connection, remote_path, crc_type)
    {:ok, local_crc} = Files.checksum(local_path, crc_type)

    cond do
      local_crc == remote_crc -> {:ok, local_crc, remote_crc}
      true -> {:error, local_crc, remote_crc}
    end
  end

  # Public key authentification ONLY:
  # The directory which contains keys (env[:user_dir]) MUST be defined !

  @doc """ 
  Establish a connection.
  ## Input:
  - conn_opts: connection options (Keywords List)
  ## Outputs:
  - {:ok, <connection>} | {:error, _reason_}
  """

  def connect(conn_opts) do
   
    # Needed to expose the SSH key:
    user_dir = Application.get_env(:sscs_ex, :ssh_conf)[:user_dir]
              |> String.to_charlist()

    SFTP.connect(Keyword.merge(conn_opts, user_dir: user_dir))
    
  end

  @doc """ 
  Close a connection.
  ## Input: 
  - connection: SSH connection (Map)
  ## Outputs: 
  - {:ok, <connection>} | {:error, _reason_}
  """

  def disconnect(connection) do
    SFTP.disconnect(connection)
  end

  # defp disconnect_and_reply(connection, reply) do
  #   if connection do
  #    disconnect(connection)
  #   end
  #   reply
  # end

  
  #############################################
  # Entry point for the  SscsEx.Server module #
  #############################################

  # def transfer_file(conn_opts, transfer_func_atom, local_file, remote_file)
  #     when transfer_func_atom in @allowed_transfer_func do
  #   apply(__MODULE__, transfer_func_atom, [conn_opts, local_file, remote_file])
  # end

  # def transfer_file(_conn_opts, transfer_func_atom, _local_file, _remote_file) do
  #   {:error, 0, "The transfer function #{to_string(transfer_func_atom)} is unknown..."}
  # end

  @doc """ 
  Transfer a file using the transfer_func.
  ## Inputs: 
  - conn_opts: connection options (Keywords List),
  - transfer_func: transfer function name (atom),
  - local_file: path of the local file (String), 
  - remote_file: path of the remote file (String)
  ## Outputs: 
  - {:ok, _message_} | {:error, "The transfer function <transfer_func> is unknown..."}
  """

  def transfer_file(conn_opts, transfer_func, local_file, remote_file) do
      if Kernel.function_exported?(__MODULE__, transfer_func, 3) do
        apply(__MODULE__, transfer_func, [conn_opts, local_file, remote_file])
      else
        {:error, "The transfer function #{to_string(transfer_func)} is unknown..."}
      end
  end

   # Prerequisites tests => connection + transfer function call + disconnection

  defp transfer(transfer_type, transfer_func, conn_opts, local_path, remote_path) do

    with {:ok, connection} <-
           PreTransfer.requisites(transfer_type, conn_opts, local_path, remote_path) do
      result = transfer_func.(connection, local_path, remote_path)
      disconnect(connection)
      result
    else
      {:error, reason} -> {:error, "#{inspect(reason)}"}
    end
  end

  ##########################
  # Download/Get functions #
  ##########################

  # Download with stream:

   # Download/Resume download: 
   # append the missing part from the remote file to the local file.
   # If no local file then full download...

   defp get_file_append_core(connection,  local_path, remote_path) do

    crc_type = Application.get_env(:sscs_ex, :transfer_conf)[:crc_type]
    stream_bytes = Application.get_env(:sscs_ex, :transfer_conf)[:stream_bytes]

    with {:ok, msg} <- Append.remote_file_streamed(connection, local_path, remote_path, crc_type, stream_bytes) do
      {:ok,  msg}
    else
      {:error, reason} -> {:error,  "#{inspect(reason)}"}
    end

  end

  # Public function:
  
  @doc """ 
  Download a remote file.
  ## Inputs: 
  - conn_opts: connection options (Keywords List),
  - local_file: path of the local file (String), 
  - remote_file: path of the remote file (String)
  ## Outputs: 
  - {:ok, _message_} | {:error, _reason_}
  """

  def get_file(conn_opts, local_path, remote_path),
    do: transfer(:get, &get_file_append_core/3, conn_opts, local_path, remote_path)

@doc """ 
  Resume the download of a remote file.
  ## Inputs: 
  - conn_opts: connection options (Keywords List),
  - local_file: path of the local file (String),
  - remote_file: path of the remote file (String).
  ## Outputs: 
  - {:ok, _message_} | {:error, _reason_}.
  """

  def get_file_append(conn_opts, local_path, remote_path),
    do: transfer(:reget, &get_file_append_core/3, conn_opts, local_path, remote_path)

  #########################  
  # Upload/Send Functions #  
  #########################

  
  # Upload with stream:

  # Upload/Resume upload: 
  # append the missing part from the local file to the remote file.
  # If no remote file then full upload...

  defp send_file_append_core(connection,  local_path, remote_path) do

    crc_type = Application.get_env(:sscs_ex, :transfer_conf)[:crc_type]
    stream_bytes = Application.get_env(:sscs_ex, :transfer_conf)[:stream_bytes]

    with {:ok, msg} <- Append.local_file_streamed(connection, local_path, remote_path, crc_type, stream_bytes) do
      {:ok,  msg}
    else
      {:error, reason} -> {:error,  "#{inspect(reason)}"}
    end

  end

  # Public function:

  @doc """ 
  Upload/send a local file.
  ## Inputs: 
  - conn_opts: connection options (Keywords List),
  - local_file: path of the local file (String), 
  - remote_file: path of the remote file (String)
  ## Outputs: 
  - {:ok, _message_} | {:error, _reason_}
  """

  def send_file(conn_opts, local_path, remote_path),
    do: transfer(:send, &send_file_append_core/3, conn_opts, local_path, remote_path)

  @doc """ 
  Resume the upload of a local file.
  ## Inputs: 
  - conn_opts: connection options (Keywords List),
  - local_file: path of the local file (String), 
  - remote_file: path of the remote file (String)
  ## Outputs: 
  - {:ok, _message_} | {:error, _reason_}
  """

  def send_file_append(conn_opts, local_path, remote_path),
    do: transfer(:resend, &send_file_append_core/3, conn_opts, local_path, remote_path)
end
