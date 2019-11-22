defmodule SscsEx.Append do
  require Logger
  alias SscsEx.SFTP
  alias SscsEx.Files
  alias SscsEx.Client

  @doc """
  Append the excess part of the remote_file to the local_file, accounting their respectives sizes..
  If the local file doesn't exist, it is created and the remote file is fully downloaded in it.

  ## Inputs:
  - connection: SSH connection, 
  - local_path: path of the local file,
  - remote_path: path of the remote file, 
  - checksum_type: can be :sha, :sha224, :sha256, :sha384, :sha512, :sha3_224, :sha3_256, :sha3_384, :sha3_512, :blake2b, :blake2s, :md5 or :md4

  ## Outputs:
  - {:ok, "Checksum (type: _checksum_type_) for both files = _checksum_"},  
  - {:error, "Couldn't resume downloading local file _local_path_ from remote file _remote_path_: reason: _reason_"
  """

  def remote_file(connection, local_path, remote_path, checksum_type) do
    with {:ok, local_size} <- Files.size2(local_path),
         {:ok, remote_size} <- SFTP.file_size2(connection, remote_path),
         {:ok, data} <- SFTP.read_part_file(connection, remote_path, local_size, remote_size),
         {:ok, _} <- Files.append_part(local_path, data),
         {:ok, local_crc, _remote_crc} <-
           Client.test_checksum(connection, local_path, remote_path, checksum_type) do
      {:ok, "Checksum (type: #{checksum_type}) for both files = #{local_crc}"}
    else
      {:error, reason} ->
        {:error, "Reason: #{inspect(reason)}"}

      {:error, local_crc, remote_crc} ->
        {:error,
         "Bad checksum (type: #{checksum_type}) : local file checksum = #{local_crc} , remote file checksum = #{
           remote_crc
         }"}
    end
  end

  @doc """
  Append the excess part of the local_file to the remote file, accounting their respectives sizes.
  If the remote file doesn't exist, it is created and the local file is fully downloaded in it.
  NB: checksum_type could be: 
  :sha, :sha224, :sha256, :sha384, :sha512, :sha3_224, :sha3_256, :sha3_384, :sha3_512, :blake2b, :blake2s, :md5 or :md4
   ## Inputs:
  - connection: SSH connection, 
  - local_path: path of the local file,
  - remote_path: path of the remote file, 
  - checksum_type: can be :sha, :sha224, :sha256, :sha384, :sha512, :sha3_224, :sha3_256, :sha3_384, :sha3_512, :blake2b, :blake2s, :md5 or :md4
  ## Outputs:
  - {:ok, "Checksum (type: _checksum_type_) for both files = _checksum_"} |  {:error, "Couldn't resume uploading local file _local_path_ to remote file _remote_path_: reason: _reason_"
  """
  def local_file(connection, local_path, remote_path, checksum_type) do
    with {:ok, local_size} <- Files.size2(local_path),
         {:ok, remote_size} <- SFTP.file_size2(connection, remote_path),
         {:ok, data} <- Files.read_part(local_path, remote_size, local_size),
         {:ok, _} <- SFTP.append_part_file(connection, remote_path, data),
         {:ok, local_crc, _remote_crc} <-
           Client.test_checksum(connection, local_path, remote_path, checksum_type) do
      {:ok, "Checksum (type: #{checksum_type} ) for both files = #{local_crc}"}
    else
      {:error, reason} ->
        {:error, "Reason: #{inspect(reason)}"}

      {:error, local_crc, remote_crc} ->
        {:error,
         "Bad checksum (type: #{checksum_type}) : local file checksum = #{local_crc} , remote file checksum = #{
           remote_crc
         }"}
    end
  end

  @doc """
  Append "streamingly" the excess part of the remote_file to the local_file, accounting their respectives sizes ..
  If the local file doesn't exist, it is created and the remote file is fully appended to it (ie downloaded).

  ## Inputs:
  - connection: SSH connection, 
  - local_path: path of the local file,
  - remote_path: path of the remote file, 
  - checksum_type: can be :sha, :sha224, :sha256, :sha384, :sha512, :sha3_224, :sha3_256, :sha3_384, :sha3_512, :blake2b, :blake2s, :md5 or :md4,
  - bytes_size: size of the chunks used in streaming.

  ## Outputs:
  - {:ok, "Checksum (type: _checksum_type_) for both files = _checksum_"} | {:error, "Bad checksum (type: _checksum_type_}) : local file checksum = _local checksum_} , remote file checksum = _remote checksum_"} | {:error, _reason_}
  """

  def remote_file_streamed(connection, local_path, remote_path, checksum_type, bytes_size) do
    with {:ok, local_size} <- Files.size2(local_path),
         {:ok, stream} <-
           SFTP.read_part_file_to_stream(connection, remote_path, local_size, bytes_size),
         {:ok, _} <- Files.append_part_from_stream(local_path, stream, bytes_size),
         {:ok, local_crc, _remote_crc} <-
           Client.test_checksum(connection, local_path, remote_path, checksum_type) do
      {:ok, "Checksum (type: #{checksum_type}) for both files = #{local_crc}"}
    else
      {:error, reason} ->
        {:error, "Reason: #{inspect(reason)}"}

      {:error, local_crc, remote_crc} ->
        {:error,
         "Bad checksum (type: #{checksum_type}) : local file checksum = #{local_crc} , remote file checksum = #{
           remote_crc
         }"}
    end
  end

  @doc """
  Append "streamingly" the excess part of a local file to a remote file, accounting their respectives sizes ..
  If the remote file doesn't exist, it is created and the local file is fully appended to it (ie uploaded).

  ## Inputs:
  - connection: SSH connection, 
  - local_path: path of the local file,
  - remote_path: path of the remote file, 
  - checksum_type: can be :sha, :sha224, :sha256, :sha384, :sha512, :sha3_224, :sha3_256, :sha3_384, :sha3_512, :blake2b, :blake2s, :md5 or :md4,
  - bytes_size: size of the chunks used in streaming.

  ## Outputs:
  - {:ok, "Checksum (type: _checksum_type_) for both files = _checksum_"} | {:error, "Bad checksum (type: _checksum_type_}) : local file checksum = _local checksum_} , remote file checksum = _remote checksum_"} | {:error, _reason_}
  """

  def local_file_streamed(connection, local_path, remote_path, checksum_type, bytes_size) do
    with {:ok, remote_size} <- SFTP.file_size2(connection, remote_path),
         {:ok, stream} <- Files.read_part_to_stream(local_path, remote_size, bytes_size),
         {:ok, _} <-
           SFTP.append_part_file_from_stream(connection, remote_path, stream, bytes_size),
         {:ok, local_crc, _remote_crc} <-
           Client.test_checksum(connection, local_path, remote_path, checksum_type) do
      {:ok, "Checksum (type: #{checksum_type} ) for both files = #{local_crc}"}
    else
      {:error, reason} ->
        {:error, "Reason: #{inspect(reason)}"}

      {:error, local_crc, remote_crc} ->
        {:error,
         "Bad checksum (type: #{checksum_type}) : local file checksum = #{local_crc} , remote file checksum = #{
           remote_crc
         }"}
    end
  end
end
