defmodule SscsEx.PreTransfer do
@moduledoc """
Check pre-conditions according to the type of the transfer (Upload/Download/Resume upload/Resume download).
"""
    alias SscsEx.SFTP
    alias SscsEx.Files
    alias SscsEx.Client

  #####################################
  # Prerequisites tests for transfers #
  #####################################

  # pre_transfer_test(_connection, _transfer_type, _is_local_file?, _is_remote_file?, _local_path, _remote_path)

  # Prerequisites tests for Download (transfer type = :get) transfers.

  # No local file, remote file ok
  defp test(_connection, :get, :error, :ok, _local_path, _remote_path), do: {:ok, nil}

  # Local file exists. 
  # IMPORTANT: the presence of substring "NO RETRY" is tested afterward !
  defp test(_connection,:get, :ok, _remote_is_file, local_path, _remote_path) do
    case Application.get_env(:sscs_ex, :transfer_conf)[:overwrite] do
      :false -> {:error, "Download error: Local file #{local_path} already exists - NO RETRY permitted !"}
      _ -> Files.remove(local_path) # To clean the mess...
    end
  end

  # No remote file
  defp test(_connection,:get, _local_is_file, :error, _local_path, remote_path),
    do: {:error, "Download error: Remote file #{remote_path} does not exists."}
 
  # Prerequisites tests for Resume download (transfer type = :reget) transfers.

  # defp test(_connection,:reget, :error, _remote_is_file, local_path, _remote_path),
  #   do: {:error, "Resume download error: Local file #{local_path} does not exists..."}

  # No remote file
  defp test(_connection, :reget, _local_is_file, :error, _local_path, remote_path),
    do: {:error, "Resume download error: Remote file #{remote_path} does not exists."}

  # Compare files sizes
  defp test(connection, :reget, _local_is_file, :ok, local_path, remote_path) do
    with {:ok, local_size} <- Files.size2(local_path),
         {:ok, remote_size} <- SFTP.file_size2(connection, remote_path) do
      if remote_size > local_size do 
      {:ok, nil}
      else
        {:error, "Size of remote file #{remote_path} is < or = to the size of local file #{local_path}"}  
      end
    else
      {:error, reason} -> {:error, "#{inspect(reason)}"}
    end
  end

  # Prerequisites tests for Upload (transfer type = :send) transfers.

  # Local file ok, no remote file
  defp test(_connection, :send, :ok, :error, _local_path, _remote_path), do: {:ok, nil}

  # No local file
  defp test(_connection, :send, :error, _remote_is_file, local_path, _remote_path),
    do: {:error, "Upload error: Local file #{local_path} does not exist or is not a regular file."}

  # Remote file exists.
  # IMPORTANT: the presence of substring "NO RETRY" is tested afterward !
  defp test(connection, :send, _local_is_file, :ok, _local_path, remote_path) do
    case Application.get_env(:sscs_ex, :transfer_conf)[:overwrite] do
      :false -> {:error, "Upload error: Remote file #{remote_path} already exists - NO RETRY permitted !"}
      _ -> SFTP.remove_file(connection, remote_path) # To clean the mess...
    end
  end


  # Prerequisites tests for Resume upload (transfer type = :resend) transfers.

  # No local file.
  defp test(_connection, :resend, :error, _remote_is_file, local_path, _remote_path),
    do: {:error, "Resume upload error: Local file #{local_path} does not exist or is not a regular file."}

  # defp test(_connection, :resend, _local_is_file, :error, _local_path, remote_path),
  #   do: {:error, "Resume upload error: Remote file #{remote_path} does not exist."}

  # Local file exists.
  defp test(connection, :resend, :ok, _remote_is_file, local_path, remote_path) do
    with {:ok, local_size} <- Files.size2(local_path),
         {:ok, remote_size} <- SFTP.file_size2(connection, remote_path) do
      if local_size > remote_size do 
      {:ok, nil}
      else
        {:error, "Size of local file #{local_path} is < or = to the size of remote file #{remote_path}"}  
      end
  else
    {:error, reason} -> {:error, "#{inspect(reason)}"}
  end
  end

  # Otherwise...
  defp test(
         _connection, 
         transfer_type,
         _local_is_file,
         _remote_is_file,
         _local_path,
         _remote_path
       ),
       do: {:error, "Transfer type: #{transfer_type} unknown..."}

  @doc """ 
  Checks prerequisites for the transfer.
  Create connection and test(_connection, _transfer_type, _is_local_file?, _is_remote_file?, _local_path, _remote_path)
  ## Inputs: 
    - transfer_type (:get, :send, :reget, :resend),
    - conn_opts (SSH connection options),
    - local_path (path of local file)
    - remote_path (path of remote file)
  ## Output:
    - {:ok, _connection_} |  {:error, _message_} | {:error, _reason_}
  """
  def requisites(transfer_type, conn_opts, local_path, remote_path) do
    with {:ok, connection} <- Client.connect(conn_opts) do
      case test(
             connection,
             transfer_type,
             Files.is_file(local_path),
             SFTP.is_file(connection, remote_path),
             local_path,
             remote_path
           ) do
        {:ok, _} -> {:ok, connection}
        any -> Client.disconnect(connection)
               any   #{:error, msg}
      end
    else
      {:error, reason} -> {:error, "Connection error - Reason: #{inspect(reason)}"}
    end
  end
end