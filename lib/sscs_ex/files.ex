defmodule SscsEx.Files do
@moduledoc """
Functions to manage local files.
"""

alias SscsEx.Utils

@checksum_chunk 1_048_576

@doc """ 
Compute the checksum of a file.
## Inputs:
- file_path: path of the file,
- crc_type: can be :sha, :sha224, :sha256, :sha384, :sha512, :sha3_224, :sha3_256, :sha3_384, :sha3_512, :blake2b, :blake2s, :md5 or :md4
## Outputs:
- {:ok, <checksum} | {:error, "Wrong file _path_..."}
"""

def checksum(file_path, crc_type) do
  case is_file(file_path) do
    :ok -> crc = File.stream!(file_path, [], @checksum_chunk)
                  |> Utils.stream_checksum(crc_type)
            {:ok, crc}
      _  -> {:error, "Wrong file #{file_path}..."}
  end
end

@doc """ 
Check if a path is a folder.
## Inputs:
- strdir: path of the folder.
## Outputs:
- :ok | :error
"""
def is_dir(strdir) do
  if File.dir?(to_string(strdir)) do
    :ok
  else
    :error
  end
end

@doc """ 
Check if a file is of the regular type.
## Inputs:
- path: path of the file.
## Outputs:
- :ok | :error
"""

def is_file(path) do
  if File.regular?(path) do
    :ok
  else
    :error
  end
end

@doc """ 
Give the file size of a file.
## Inputs:
- strdir: path of the file.
## Outputs:
- {:ok, _size_} | {:error, _reason_}
"""

def size(path) do
  with true <- File.exists?(path),
        :ok <- is_file(path),
        {:ok, %{size: size}} <- File.stat(path) do
    {:ok, size}
  else
    false -> {:error, "#{path} does not exist."}
    :error ->
      {:error, "#{path} is not a regular file"}

    {:error, reason} ->
      {:error, "Could not get the size of #{path}. Reason: #{inspect(reason)}"}
  end
end

@doc """ 
Give the file size of a file or 0 if the file doesn't exist.
## Inputs:
- path: path of the file.
## Outputs:
- {:ok, _size_} | {:error, "_path_ is not a regular file"} | {:error, "Could not get the size of _path_. Reason: _reason_"}}
"""

def size2(path) do
  with true <- File.exists?(path),
        :ok <- is_file(path),
        {:ok, %{size: size}} <- File.stat(path) do
    {:ok, size}
  else
    false -> {:ok, 0}
    :error ->
      {:error, "#{path} is not a regular file"}

    {:error, reason} ->
      {:error, "Could not get the size of #{path}. Reason: #{inspect(reason)}"}
    end
  end

  @doc """ 
  Compute the transfer rate of a file.
  ## Inputs:
  - path: path of the file,
  - seconds: transfer duration,
  - unit: file size unit. Can be: :mb (MB) or :kb (KB)
  ## Outputs:
  - {:ok, _transfer rate_} or {:error, _message_}
  """
  def transfer_rate(path, seconds, unit) do
      with {:ok, size} <- size(path) do
          Utils.transfer_rate(size, seconds, unit)
      else
        any -> any # {:error, message}
      end
  end

  @doc """ 
  Remove a file.
  ## Inputs:
  - path: path of the file
  ## Outputs:
  - {:ok, "Local file _path_ removed"} |  or {:error, "Local file _path_ NOT removed. Reason: _reason_}"}
  """
  def remove(path) do
    with :ok <- File.rm(path) do
      {:ok, "Local file #{path} removed"}
    else
      {:error, reason} -> {:error, "Local file #{path} NOT removed. Reason: #{inspect(reason)}"}
    end
   end

  @doc """ 
  Create an empty file.
  ## Inputs:
  - path: path of the file
  ## Outputs:
  - {:ok, nil} | {:error, _reason_}
  """
  def create(path) do
    with {:ok, io_device} <- File.open(path, [:write, :binary]) do
      File.close(io_device)
      {:ok, nil}
    else
      any -> any #{:error, reason}
    end
  end


  @doc """ 
  Read the local file part from position 'start' with the length 'length'.
  ## Inputs:
  - path: path of the file,
  - start: start position to read on,
  - length: size to read
  ## Outputs:
  - {:ok, _data_} | {:error, _reason_}
  """
  def read_part(path, start, length) do
    erl_path = Utils.get_charlist(path)

    with {:ok, io_device} <- :file.open(erl_path, [:read, :binary]) do
        res = :file.pread(io_device, {:bof, start}, length)
        :file.close(io_device)
        res  # {:ok, data} or {:error, reason}
    else
      any ->
        any   # {:error, reason} 
    end
  end

  @doc """ 
  Append data to the end of local file.
  ## Inputs:
  - path: path of the file,
  - data: datas to append.
  ## Outputs:
  Returns: {:ok, nil} or {:error, _reason_}
  """
  def append_part(path, data) do
    with {:ok, io_device} <- File.open(path, [:append, :binary]) do
        res =
          File.write(path, data) # File.write returns :ok or {:error, reason}
          |> Utils.force_tuple_result()

        File.close(io_device) # {:ok, nil} or {:error, reason}
        res
    else
      any -> any # {:error, reason} 
    end
  end

  @doc """ 
  Read the local file part from position 'start' and create a stream from it.
  ## Inputs:
  - path: path of the file
  - start: start position to read on,
  - bytes-size: size of chunks of data to be streamed
  ## Outputs:
  - {:ok, _stream_} | {:error, _reason_}
  """
  def read_part_to_stream(path, start, bytes_size) do
    erl_path = Utils.get_charlist(path)

    with {:ok, io_device} <- :file.open(erl_path, [:read, :binary]),
         {:ok, _} <- :file.position(io_device, start) do
         {:ok, IO.binstream(io_device, bytes_size)}
         else
          any -> any   # {:error, reason} 
         end
  end

  @doc """ 
  Append stream data to the end of local file.
  ## Inputs:
  - path: path of the file
  - stream_data: stream of datas to append,
  - bytes-size: size of chunks of data to be streamed
  ## Outputs:
  - {:ok, nil} | {:error, _reason_}
  """
  def append_part_from_stream(path, stream_data, bytes_size) do
    with {:ok, io_device} <- File.open(path, [:append, :binary]) do
        stream_data
        |> Stream.into(IO.binstream(io_device, bytes_size))
        |> Stream.run()
        File.close(io_device)
        {:ok, nil}
    else
      any -> any # {:error, reason} 
    end
  end
end