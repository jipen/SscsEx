defmodule SscsEx.SFTP do
   @moduledoc "
 SFTP Functions for the client side of the SscsEx server.
"

 alias SscsEx.Utils

 @type str_or_charlist_t :: charlist() | String.t()
 @type connection_t :: %{ channel_pid: pid(), connection_ref: :ssh.connection_ref(), host: str_or_charlist_t(), port: non_neg_integer(), opts: keyword()}
 @type crc_t :: :sha | :sha224 | :sha256 | :sha384 | :sha512 | :sha3_224 | :sha3_256 | :sha3_384 | :sha3_512 | :blake2b | :blake2s | :md5 | :md4

  @default_opts [
    user_interaction: false,
    silently_accept_hosts: true,
    rekey_limit: 1_000_000_000_000
  ]

  @doc """
  Creates an SFTP channel
  ## Inputs:
  - opts: SSH options,
  ## Outputs:
  - {:ok, _connection_}, or {:error, _reason_}
  """
  @spec connect(keyword) :: {:ok, connection_t()} | {:error, String.t()} | {:error, any}
  def connect(opts) do
    host = Keyword.get(opts, :host) |> Utils.get_charlist()
    port = Keyword.get(opts, :port)

    if host && port do
      opts = @default_opts |> Keyword.merge(opts)
      ssh_opts = Keyword.drop(opts, [:host, :port])

      with {:ok, channel_pid, connection_ref} <- :ssh_sftp.start_channel(host, port, ssh_opts) do
        {:ok,
         %{
           channel_pid: channel_pid,
           connection_ref: connection_ref,
           host: host,
           port: port,
           opts: ssh_opts
         }}
      else
        # {:error, reason}
        any -> any
      end
    else
      {:error, "Missing Host or Port from connections options"}
    end
  end

  @doc """
  Stops a SFTP channel and closes the SSH connection.
  ## Inputs: 
  - connection: SFTP connection
  ## Output:
  - :ok | {:error, _reason_}
  """
  @spec disconnect(connection_t()) :: {:error, any()} | :ok
  def disconnect(connection) do
    :ssh_sftp.stop_channel(connection.channel_pid) 
    :ssh.close(connection.connection_ref)
  end

  @doc """
  Closes an opened remote file.
  ## Inputs: 
  - Connection: SFTP connection, 
  - handle: file handle.
  ## Outputs: :ok | {:error, _reason_}
  """
  @spec close_file_handle(connection_t(), any()) :: :ok | {:error, :ssh_sftp.reason()}
  def close_file_handle(connection, handle) do
    :ssh_sftp.close(connection.channel_pid, handle)
  end

  @doc """
  get the file info of a remote file
  ## Inputs: 
  - Connection: SFTP connection,
  - path: path of the file (String)
  ## Outputs: 
  - {:ok, _File.Stat_} | {:error, _reason_}
  """
  @spec file_info(connection_t(), str_or_charlist_t()) :: {:ok, File.Stat.t()} | {:error, any()}
  def file_info(connection, path) do
    erl_path = Utils.get_charlist(path)

    with {:ok, file_info} <- :ssh_sftp.read_file_info(connection.channel_pid, erl_path) do
      {:ok, File.Stat.from_record(file_info)}
    else
      # {:error, reason}
      any -> any
    end
  end

   @doc """
    Gives the type of a remote file given a channel PID and path.
    ## Inputs: 
    - Connection: SFTP connection,
    - path: path of the file
    ## Outputs: 
    - (boolean) true | false
  """
  @spec file_exists?(connection_t(), str_or_charlist_t()) :: boolean()
  def file_exists?(connection, path) do
    case file_info(connection, path) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
    Gives the type of a remote file given a channel PID and path.
    ## Inputs: 
    - Connection: SFTP connection,
    - path: path of the remote file.
     ## Outputs: 
    - {:ok, _type_} | {:error, _reason_}
  """
  @spec file_type(connection_t(), str_or_charlist_t()) :: {:ok, atom()} | {:error, any()}
  def file_type(connection, path) do
    with {:ok, info} <- file_info(connection, path) do
      {:ok, info.type}
    else
      # {:error, reason}
      any -> any
    end
  end

  @doc """
  Test if a remote file is of the regular type.
  ## Inputs: 
    - Connection: SFTP connection,
    - path: path of the remote file.
   ## Outputs: 
    - :ok | :error
  """
  @spec is_file(connection_t(), str_or_charlist_t()) :: :error | :ok
  def is_file(connection, path) do
    with {:ok, :regular} <- file_type(connection, path) do
      :ok
    else
      _ -> :error
    end
  end

  @doc """
    Gives the type of a remote file given a connection and path.
    ## Inputs: 
    - Connection SFTP connection, 
    - path: path of the remote file.
     ## Outputs: 
    - {:ok, _type_} | {:error, _reason_}
  """
  @spec file_size(connection_t(), str_or_charlist_t()) :: {:ok, non_neg_integer()} | {:error, String.t()} | {:error, any()}
  def file_size(connection, path) do
    with {:ok, info} <- file_info(connection, path) do
      if info.type == :regular do
      {:ok, info.size}
      else
        {:error, "#{path} is not a regular file"}
      end
    else
      # {:error, reason}
      any -> any
    end
  end

  @doc """
Return the size of a remote file or 0 if the file doesn't exist:
## Inputs: 
- connection: SFTP connection),
- path: path of the remote file.
 ## Outputs: 
  - {:ok, _size_} _if the remote file exists and is actually a file,_ 
    | {:ok, 0} _if the remote file doesn't exist,_ 
    | {:error, _reason_} _if the remote file is not a file._
"""
@spec file_size2(connection_t(), any()) :: {:error, String.t()} | {:ok, non_neg_integer()}
def file_size2(connection, path) do
  with {:ok, info} <- file_info(connection, path) do
      if info.type == :regular do
      {:ok, info.size}
      else
        {:error, "#{path} is not a regular file"}
      end
    else
      # {:error, reason}
      _any -> {:ok, 0}
    end
end

  @doc """
    Opens a remote file given a connection and path.
    ## Inputs: 
    - connection: SFTP connection,
    - path: path of the remote file,
    - mode: open modes ([:creat, :write, ...]).
     ## Outputs: 
    - {:ok, _handle_} | {:error, _reason_}
  """
  @spec open_file(connection_t(), str_or_charlist_t(), [atom()]) :: {:ok, any()} | {:error, :ssh_sftp.reason()}
  def open_file(connection, path, mode) do
    erl_path = Utils.get_charlist(path)
    :ssh_sftp.open(connection.channel_pid, erl_path, mode)
  end

   @doc """
    Create an empty remote file given a connection and path.
    ## Inputs: 
    - Connection: SFTP connection,
    - path: path of the remote file .
     ## Outputs: 
    - {:ok, nil} | {:error, _reason_}
  """
  @spec create_file(connection_t(), str_or_charlist_t()) :: {:ok, nil} | {:error, any()}
  def create_file(connection, path) do
    erl_path = Utils.get_charlist(path)
    with {:ok, handle} <- open_file(connection, erl_path, [:creat, :binary]) do
      close_file_handle(connection, handle)
      {:ok, nil}
    else
      # {:error, reason}
      any -> any
    end
  end

  @doc """
  Remove a remote file.
  ## Inputs: 
    - Connection: SFTP connection,
    - path: path of the remote file.
   ## Outputs: 
    - {:ok, _message_} or {:error, _message_}
  """
  @spec remove_file(connection_t(), str_or_charlist_t()) ::
          {:error, String.t()} | {:ok, String.t()}
  def remove_file(connection, path) do
    erl_path = Utils.get_charlist(path)

    with :ok <- :ssh_sftp.delete(connection.channel_pid, erl_path) do
      {:ok, "Remote file #{path} removed"}
    else
      {:error, reason} ->
        {:error, "Remote file #{path} NOT removed. Reason: #{inspect(reason)}"}
    end
  end

  @doc """
  Read a bitstream from a file (handle).
  ## Inputs: 
    - Connection: SFTP connection, 
    - handle: file handle,
    - byte_length: number of bytes to read
   ## Outputs: 
    - {:halt, _handle_} | {[_data_], _handle_} | {:error, _reason_}
  """

  @spec each_binstream(connection_t(), any, non_neg_integer()) :: {:halt | [...], any}
  def each_binstream(connection, handle, byte_length) do
    case :ssh_sftp.read(connection.channel_pid, handle, byte_length) do
      :eof ->
        {:halt, handle}

      {:error, reason} ->
        raise(IO.StreamError, reason: reason)

      {:ok, data} ->
        {[data], handle}
    end
  end

  @doc """
    Writes data to a open file using the channel PID
    ## Inputs: 
    - Connection: SFTP connection, 
    - handle: handle of the file,
    - data: data to write
   ## Outputs: 
    - :ok | :error
  """
  @spec write_handle(connection_t(), any(), iodata()) :: :ok | {:error, :ssh_sftp.reason()}
  def write_handle(connection, handle, data) do
    :ssh_sftp.write(connection.channel_pid, handle, data)
  end

  @doc """
    Open a stream on a file to write
    ## Inputs: 
    - connection: SFTP connection), 
    - path: path of the file (String),
    - byte_size: stream chunks size (integer)
    ## Outputs: 
    -  StreamFile | {:error, _reason_}
  """
  
  @spec stream_write!(connection_t(), str_or_charlist_t(), non_neg_integer()) :: any
  def stream_write!(connection, path, byte_size \\ 32768) do
    case open_file(connection, path, [:write, :binary]) do
      {:ok, handle} -> stream_handle!(connection, handle, byte_size)
      # {:error, reason}
      any -> any
    end
  end

  @doc """
    Open a stream on a file for create and write
    ## Inputs: 
    - connection: SFTP connection), 
    - path: path of the file (String),
    - byte_size: stream chunks size (integer)
    ## Outputs: 
    - StreamFile or {:error, _reason_}
  """
  @spec stream_create!(connection_t(), str_or_charlist_t(), non_neg_integer()) :: any
  def stream_create!(connection, path, byte_size \\ 32768) do
    case open_file(connection, path, [:write, :binary, :creat]) do
      {:ok, handle} -> stream_handle!(connection, handle, byte_size)
      # {:error, reason}
      any -> any
    end
  end

  @doc """
    Open a stream on a file for reading
    ## Inputs: 
    - connection: SFTP connection), 
    - path: path of the file (String),
    - byte_size: stream chunks size (integer)
    ## Output: 
     - StreamFile | {:error, _reason_}
  """
  @spec stream_read!(connection_t(), str_or_charlist_t(), non_neg_integer()) :: any
  def stream_read!(connection, path, byte_size \\ 32768) do
    case open_file(connection, path, [:read, :binary]) do
      {:ok, handle} -> stream_handle!(connection, handle, byte_size)
      # {:error, reason}
      any -> any
    end
  end

  # Open a stream on the part of a file
  #   Types:
  #    connection = Connection
  #    remote_path = string()
  #   Returns SscsEx.SFTP.Stream
 
  defp stream_handle!(connection, handle, byte_size) do
    SscsEx.StreamFile.__build__(connection, handle, byte_size)
  end

  # Byte_size to compute checksums.
  @checksum_chunk 1_048_576

  @doc """
  Return the checksum of a remote file.
  ## Inputs: 
    - connection: SFTP connection), 
    - path: path of the file (String),
    - crc_type: checksum type = :sha, :sha224, :sha256, :sha384, :sha512, :sha3_224, :sha3_256, :sha3_384, :sha3_512, :blake2b, :blake2s, :md5 or :md4.
  ## Outputs: 
  - {:ok, _checksum_} | {:error, _message_}
  """
  @spec file_checksum(connection_t(), str_or_charlist_t(), crc_t()) ::
          {:error, charlist() | String.t()} | {:ok, binary}
  def file_checksum(connection, path, crc_type) do
    case is_file(connection, path) do
      :ok ->
        crc =
          stream_read!(connection, path, @checksum_chunk)
          |> Utils.stream_checksum(crc_type)

        {:ok, crc}

      :error ->
        {:error, "Wrong remote file #{path}..."}
    end
  end

  @doc """
  Read 'length' bytes from the remote file part, starting at 'start' position.
  ## Inputs: 
    - connection: SFTP connection), 
    - path: path of the file (String),
    - start: start position (integer), 
    - length: number of bytes to read (integer)
  ## Outputs: 
   - {:ok, _data_} | {:error, _reason_}
  """
  @spec read_part_file(connection_t(), str_or_charlist_t(), non_neg_integer(), non_neg_integer()) :: {:ok,any()} | {:error, any()}
  def read_part_file(connection, path, start, length) do
    with {:ok, file_handle} <- open_file(connection, path, [:read, :binary]) do
      res = :ssh_sftp.pread(connection.channel_pid, file_handle, start, length)
      close_file_handle(connection, file_handle)
      # {:ok, data} or {:error, reason}
      res
    else
      any ->
        # {:error, reason} 
        any
    end
  end

  # If file exists then append else create...
  # defp append_or_create_file(connection, remote_path) do
  #   case is_file(connection, remote_path) do
  #     :ok -> :append
  #     _ -> :creat
  #   end
  # end

  @doc """
  Read the remote file part from position 'start' and stream it.
  ## Inputs: 
    - connection: SFTP connection, 
    - path: path of the remote file,
    - start: start position, 
    - bytes_size: size of stream chunks.
  ## Outputs: 
  - {:ok, stream} | {:error, reason}
  """
  @spec read_part_file_to_stream(connection_t(), str_or_charlist_t(), non_neg_integer(), non_neg_integer()) :: {:ok, any()} | {:error, any()}
  def read_part_file_to_stream(connection, path, start, bytes_size) do
    channel_pid = connection.channel_pid

    with {:ok, file_handle} <- open_file(connection, path, [:read, :binary]),
         {:ok, _} <- :ssh_sftp.position(channel_pid, file_handle, start) do
      {:ok, stream_handle!(connection, file_handle, bytes_size)}
    else
      # {:error, reason} 
      any -> any
    end
  end

  @doc """
  Append data to the end of remote file.
  ## Inputs: 
    - connection: SFTP connection), 
    - path: path of the file (String),
    - data: data to append.
  ## Outputs:
  - {:ok, nil} | {:error, _reason_}
  """
  @spec append_part_file(connection_t(), str_or_charlist_t(), iodata()) :: {:ok, any()} | {:error, any()}
  def append_part_file(connection, path, data) do
    with {:ok, file_handle} <- open_file(connection, path, [ :append, :binary ]) do
      # :ssh_sftp.write returns :ok or {:error, reason}
      res =
        write_handle(connection, file_handle, data)
        |> Utils.force_tuple_result()

      close_file_handle(connection, file_handle)
      # {:ok, nil} or {:error, reason}
      res
    else
      # {:error, reason} 
      any -> any
    end
  end

  @doc """
  Append stream data to the end of remote file stream.
  ## Inputs: 
    - connection: SFTP connection, 
    - path: path of the file,
    - stream_data: datas from stream, 
    - bytes_size: size of stream chunks. 
  ## Outputs:
  - {:ok, nil} | {:error, _reason_}
  """
  @spec append_part_file_from_stream(connection_t(), str_or_charlist_t(), Enumerable.t(), non_neg_integer()) :: {:ok, nil} | {:error, any()}
  def append_part_file_from_stream(connection, path, stream_data, bytes_size) do
    channel_pid = connection.channel_pid

    # IO.puts("Connection = #{inspect(connection)}, remote path = #{inspect(erl_remote_path)}, mode = #{mode}")

    with {:ok, file_handle} <- open_file(connection, path, [:append, :binary]),
         {:ok, _} <- :ssh_sftp.position(channel_pid, file_handle, :eof) do
      stream_data
      |> Stream.into(stream_handle!(connection, file_handle, bytes_size))
      |> Stream.run()

      close_file_handle(connection, file_handle)
      {:ok, nil}
    else
      # {:error, reason} 
      any -> any
    end
  end
end
