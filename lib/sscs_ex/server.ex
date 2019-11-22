defmodule SscsEx.Server do
  @moduledoc """
  Functions for the server side of the SscsEx server.
  """

  use GenServer, restart: :transient
  require Logger
  alias SscsEx.Utils
  alias SscsEx.Files
  alias SscsEx.Client
  alias SscsEx.TransferDb

  ##############################################
  # Private utilitary functions.               #
  ##############################################

  @required_ssh_keys [:port, :root_dir, :user_dir, :system_dir]
  @transfer_db_file 'sscs_tranfers.db'

  # Force the root_dir

  defp full_local_path(file_name) do
    Application.get_env(:sscs_ex, :ssh_conf)[:root_dir]
    |> Path.join(file_name)
  end

  # Check SSH options 

  defp are_ssh_options(opts) do
    case Utils.are_options(opts, @required_ssh_keys) do
      {:ok, _} -> {:ok, ""}
      {:error, msg} -> {:error, "Bad SSH options: " <> msg}
    end
  end

  defp is_dir(strdir, error_msg), do: {Files.is_dir(strdir), error_msg}
  defp is_port(strnum, error_msg), do: {Utils.is_port(strnum), error_msg}

  defp test_ssh_options(opts) do
    with {:ok, _} <- are_ssh_options(opts),
         {:ok, _} <- is_port(opts[:port], "Bad port number: #{inspect(opts[:port])}"),
         {:ok, _} <- is_dir(opts[:root_dir], "Bad root directory: #{inspect(opts[:root_dir])}"),
         {:ok, _} <-
           is_dir(opts[:system_dir], "Bad system directory: #{inspect(opts[:system_dir])}"),
         {:ok, _} <- is_dir(opts[:user_dir], "Bad user directory: #{inspect(opts[:user_dir])}") do
      {:ok, opts}
    else
      # {:error, error_msg} 
      any -> any
    end
  end

  # Callbacks runned by the remote SSCS server when:
  # - Disconnection,
  # - Connection,
  # - Fail,
  # - Unknown SSH message.
  # - SSH debug (doesn't seem to work...)
  # happens.
  # Logger.info messages are simultaneously displayed in the console and in the log file of the remote server.

  defp log_disconnect(reason), do: Logger.info("Disconnection: reason = #{inspect(reason)}")

  defp log_connect(user, address, method) do
    Logger.info(
      "Connection ok for user = #{inspect(user)} from = #{inspect(address)}, method = #{
        inspect(method)
      }"
    )

    :ok
  end 

  defp log_fail(user, address, reason) do
    Logger.info(
      "Connection failed for user = #{inspect(user)} from = #{inspect(address)}, reason = #{
        inspect(reason)
      }"
    )

    :error
  end

  defp log_unexpected(message, {host, port}) do
    Logger.info(
      "Unexpected message: #{inspect(message)} , received from #{inspect(host)}:#{inspect(port)}."
    )

    :report
  end

  defp log_ssh_msg_debug(_connection_ref, true, msg, _language_tag) do
    Logger.debug("SSH debug: #{inspect(msg)}")
  end

  # SSH daemons management

  defp find_daemon_by_pid(daemons, pid) do
    daemons |> Enum.find(&(&1.pid == pid))
  end

  defp remove_daemon(daemons, pid) do
    daemons |> Enum.filter(&(&1.pid != pid))
  end

  defp stop_daemons(daemons) do
    daemons
    |> Enum.each(fn d ->
      :ssh.stop_daemon(d.pid)
    end)
  end

  defp init_daemon(opts) do
    root_dir = String.to_charlist(opts[:root_dir])
    user_dir = String.to_charlist(opts[:user_dir])
    system_dir = String.to_charlist(opts[:system_dir])

    subsystem_spec = :ssh_sftpd.subsystem_spec(cwd: root_dir, root: root_dir)

    case :ssh.daemon(opts[:port],
           system_dir: system_dir,
           user_dir: user_dir,
           auth_methods: 'publickey',
           subsystems: [subsystem_spec],
           disconnectfun: &log_disconnect/1,
           connectfun: &log_connect/3,
           failfun: &log_fail/3,
           unexpectedfun: &log_unexpected/2,
           ssh_msg_debug_fun: &log_ssh_msg_debug/4
         ) do
      {:ok, pid} ->
        ref = Process.monitor(pid)

        Logger.info("SSCS server started on port #{opts[:port]}.")

        {:ok, pid, ref, opts}

      any ->
        any
    end
  end

  # Transfer functions:

  # Switch the transfer type to its Resume version when retrying

  defp retry_change(transfer_type) do
    case transfer_type do
      :get_file -> :get_file_append
      :send_file -> :send_file_append
      # No change
      any -> any
    end
  end

  defp max_retries?(retries) do
    max_retries = Application.get_env(:sscs_ex, :transfer_conf)[:max_retries]
    min(retries, max_retries) == max_retries
  end

  defp msg_retry(retries) do
    cond do
      retries == 0 -> ""
      max_retries?(retries) -> "Max retries (#{retries}) attempted"
      true -> "(Retry #{retries})"
    end
  end

  # Forwarded messages:

  defp msg_to_log(transfer_type, result, conn_opts, local_path, remote_path) do
    ok = (result == :error && "WAS NOT") || ""

    verb =
      cond do
        String.starts_with?(to_string(transfer_type), "send") -> ok <> " sent to "
        String.starts_with?(to_string(transfer_type), "get") -> ok <> " received from "
        true -> " Don't know (!)"
      end

    "Local file = #{local_path} #{verb}: Remote file = #{remote_path} : Remote server = #{
      inspect(conn_opts[:host])
    }:#{inspect(conn_opts[:port])}"
  end

  defp transfer_core(transfer_id, transfer_type, conn_opts, local_path, remote_path, retries) do
    with {duration, {:ok, msg_client}} <-
           :timer.tc(&Client.transfer_file/4, [conn_opts, transfer_type, local_path, remote_path]) do
      msg = msg_to_log(transfer_type, :ok, conn_opts, local_path, remote_path)
      {_response, rate} = Files.transfer_rate(local_path, duration / 1_000_000, :mb)

      {:ok,
       "SUCCESS #{msg_retry(retries)}: Transfer_id = #{inspect(transfer_id)} : #{msg} : Average transfer rate = #{
         rate
       } : #{msg_client}"}
    else
      {_duration, {:error, msg_client}} ->
        msg = msg_to_log(transfer_type, :error, conn_opts, local_path, remote_path)

        {:error,
         "FAILURE #{msg_retry(retries)}: Transfer_id = #{inspect(transfer_id)} : #{msg}} : #{
           msg_client
         }"}
    end
  end

  defp transfer_or_retry(
         ets,
         transfer_id,
         transfer_type,
         local_path,
         remote_path,
         conn_opts,
         retries
       ) do
    new_transfer_type =
      if retries > 0 do
        # Switch the transfer type to its Resume version
        retry_change(transfer_type)
      else
        transfer_type
      end

    with {:ok, msg} <-
           transfer_core(
             transfer_id,
             new_transfer_type,
             conn_opts,
             local_path,
             remote_path,
             retries
           ) do
      # In all cases...
      TransferDb.remove(ets, transfer_id)
      {:ok, msg}
    else
      {:error, msg} ->
        if max_retries?(retries) || String.contains?(msg, "NO RETRY") do
          TransferDb.remove(ets, transfer_id)
          {:error, msg}
        else
          Logger.error(msg <> " Retrying later...")

          tempo_retry = Application.get_env(:sscs_ex, :transfer_conf)[:temp_retry]

          :timer.sleep(tempo_retry)

          transfer_or_retry(
            ets,
            transfer_id,
            new_transfer_type,
            local_path,
            remote_path,
            conn_opts,
            retries + 1
          )
        end

      # {:error, msg}
      any ->
        any
    end
  end

  defp transfer(
         transfer_type,
         conn_opts,
         local_file,
         remote_path,
         ets
       ) do
    # Append ROOT_DIR to the path    
    local_path = full_local_path(local_file)
    transfer_id = UUID.uuid4()
    # retries = Application.get_env(:sscs_ex, :transfer_conf)[:max_retries]

    TransferDb.add(
      ets,
      transfer_id,
      transfer_type,
      local_path,
      remote_path,
      conn_opts
    )

    transfer_or_retry(ets, transfer_id, transfer_type, local_path, remote_path, conn_opts, 0)
  end

  # Fonctions Tasks:

  # defp connect_task(conn_opts) do
  #   with {:ok, connection} <- Client.connect(conn_opts) do
  #     {:ok, "Connected to  #{connection.config.host}, port #{inspect(connection.config.port)}"}
  #   else
  #     {:error, reason} ->
  #       {:error, "Cannot connect to #{inspect(conn_opts[:host])}, reason: #{inspect(reason)}"}
  #   end
  # end

  defp ping_task(conn_opts) do
    with {:ok, connection} <- Client.connect(conn_opts) do
      Client.disconnect(connection)

      {:ok,
       "SSH Host #{inspect(conn_opts[:host])}, port #{inspect(conn_opts[:port])} is reachable"}
    else
      {:error, reason} ->
        {:error,
         "SSH Host #{inspect(conn_opts[:host])}, reason: #{inspect(reason)} is unreachable"}
    end
  end

  ##############################################
  # Fonctions Client:
  ##############################################

  def start_link(options) do
    # you may want to register your server with `name: __MODULE__`
    # as a third argument to `start_link`
    GenServer.start_link(__MODULE__, options, name: __MODULE__)
  end

  # @doc """
  # Start SSH daemon associé au serveur.
  # """
  # def start_daemon(pid, options \\ nil) do
  #   GenServer.call(pid, {:start_daemon, options})
  # end

  ##################################
  # Send (upload) public functions #
  ##################################

  @doc """
  Resume the upload of a local file.
  ## Inputs: 
  - local_file: path of the local file, 
  - remote_file: path of the remote file,
  - host: host name of remote server,
  - port: port number of listening remote server
  ## Outputs: 
  - {:ok, _message_} | {:error, _reason_}
  """

  def send_file_append(local_path, remote_path, host, port) do
    conn_opts = [host: host, port: port]
    GenServer.cast(__MODULE__, {:send_file_append, conn_opts, local_path, remote_path})
  end

  @doc """
  Upload of a local file.
  ## Inputs: 
  - local_file: path of the local file, 
  - remote_file: path of the remote file,
  - host: host name of remote server,
  - port: port number of listening remote server
  ## Outputs: 
  - {:ok, _message_} | {:error, _reason_}
  """

  def send_file(local_path, remote_path, host, port) do
    conn_opts = [host: host, port: port]
    GenServer.cast(__MODULE__, {:send_file, conn_opts, local_path, remote_path})
  end

  ###################################
  # Get (download) public functions #
  ###################################

  @doc """
  Resume the download of a remote file.
  ## Inputs: 
  - local_file: path of the local file, 
  - remote_file: path of the remote file,
  - host: host name of remote server,
  - port: port number of listening remote server
  ## Outputs: 
  - {:ok, _message_} | {:error, _reason_}
  """

  def get_file_append(local_path, remote_path, host, port) do
    conn_opts = [host: host, port: port]
    GenServer.cast(__MODULE__, {:get_file_append, conn_opts, local_path, remote_path})
  end

  @doc """
  Download of a remote file.
  ## Inputs: 
  - local_file: path of the local file, 
  - remote_file: path of the remote file,
  - host: host name of remote server,
  - port: port number of listening remote server
  ## Outputs: 
  - {:ok, _message_} | {:error, _reason_}
  """

  def get_file(local_path, remote_path, host, port) do
    conn_opts = [host: host, port: port]
    GenServer.cast(__MODULE__, {:get_file, conn_opts, local_path, remote_path})
  end

  #####################
  # Service functions #
  #####################

  @doc """
  Display the content of failed transfers table:
  """

  def display_table() do
    GenServer.cast(__MODULE__, {:transfer_table_display})
  end

  @doc """
  Clean up the content of failed transfers table:
  """

  def clean_table() do
    GenServer.cast(__MODULE__, {:transfer_table_clean})
  end

  @doc """
  Ping a remote server:
  ## Inputs:
  - host: nale of remote host,
  - port: port of remote host.
  ## Outputs:
  - {:ok, "SSH Host _host_, _port_ is reachable"} | {:error, "SSH Host _host_, _port_ is unreachable" }
  """

  def ping(host, port) do
    GenServer.cast(__MODULE__, {:ping, [host: host, port: port]})
  end

  ####################
  # Server functions #
  ####################

  @doc """
  Initialize the SSCS server:
  ## Inputs: 
  _ options: SSH options
  ## Outputs: 
  - {:ok, _state_} | {:error, _reason_}
  """

  def init(options) do
    :ok = :ssh.start()

    # To call the terminate function when the GenServer is stopped...
    Process.flag(:trap_exit, true)

    with {:ok, right_options} <- test_ssh_options(options),
         {:ok, pid, ref, options} <- init_daemon(right_options),
         {:ok, sscs_ets} <- TransferDb.dets_to_ets(@transfer_db_file) do
      # Using handle_continue to avoid being stuck by a long init 
      {:ok,
       %{options: options, daemons: [%{pid: pid, ref: ref, options: options}], ets: sscs_ets},
       {:continue, :init_retries}}
    else
      {:error, reason} ->
        :ssh.stop()
        Logger.error("Can't run the SSCS server: #{reason}")
        {:stop, :shutdown}

      any ->
        any
    end
  end

  def handle_continue(:init_retries, %{options: options, daemons: daemons, ets: sscs_ets}) do
    Logger.info("Attempting to recover preceeding failed transfers...")

    TransferDb.tab2list(sscs_ets)
    |> Utils.tuple_to_response([])
    |> Enum.each(&transfer_retry/1)

    Logger.info("...Done with failed transfers !")
    {:noreply, %{options: options, daemons: daemons, ets: sscs_ets}}
  end

  defp transfer_retry(
         {id,
          %TransferDb{
            function: function,
            local_path: local_path,
            remote_path: remote_path,
            conn_opts: conn_opts
          }}
       ) do
    GenServer.cast(__MODULE__, {:retry, id, function, conn_opts, local_path, remote_path})
  end

  # Functions handle_cast:

  def handle_cast({:start_daemon, options}, state) do
    opts = options || state.options

    case init_daemon(opts) do
      {:ok, pid, ref, options} ->
        Logger.info("Restarting SSCS server with options: #{inspect(options)}")

        {
          :noreply,
          state |> Map.put(:daemon, %{pid: pid, ref: ref, options: options})
        }

      _any ->
        Logger.error("Can't restart the SSCS server: unable to start the SSH daemon.")
        {:stop, :shutdown, state}
    end
  end

  # Tasks...

  def handle_cast({:transfer_table_display}, state) do
    Task.async(fn -> TransferDb.display(state.ets) end)
    {:noreply, state}
  end

  def handle_cast({:transfer_table_clean}, state) do
    Task.async(fn -> TransferDb.clean(state.ets) end)
    Logger.info("Failed transfers table cleaned up.")
    {:noreply, state}
  end

  def handle_cast({:ping, conn_opts}, state) do
    Task.async(fn -> ping_task(conn_opts) end)
    {:noreply, state}
  end

  def handle_cast({:retry, id, function, conn_opts, local_path, remote_path}, state) do
    Task.async(fn ->
      transfer_or_retry(state.ets, id, function, local_path, remote_path, conn_opts, 1)
    end)

    {:noreply, state}
  end

  def handle_cast({transfer_type, conn_opts, local_path, remote_path}, state)
      when is_atom(transfer_type) do
    Task.async(fn ->
      transfer(
        transfer_type,
        conn_opts,
        local_path,
        remote_path,
        state.ets
      )
    end)

    {:noreply, state}
  end

  # def handle_cast({transfer_type, _conn_opts, _local_path, _remote_path}, state) do
  #   Logger.error("Handle_cast - Transfer type unknown:  #{inspect(transfer_type)}")
  #   {:noreply, state}
  # end

  # Functions handle_call

  def handle_call({:start_daemon, options}, _from, state) do
    opts = options || state.options

    case init_daemon(opts) do
      {:ok, pid, ref, options} ->
        {:reply, {:ok, pid},
         state |> Map.put(:daemons, [%{pid: pid, ref: ref, options: options} | state.daemons])}

      any ->
        {:reply, any, state}
    end
  end

  # def handle_call(msg, _from, state) do
  #   Logger.error("Handle_call - Unknown message:  #{inspect(msg)}")
  #   {:reply, :unknown, state}
  # end

  # Functions handle_info(s)

  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    daemon = find_daemon_by_pid(state.daemons, pid)

    # Daemon SSH is DOWN !
    if daemon do
      Logger.info("SSH Daemon is going DOWN (reason = #{inspect(reason)}): Restarting it...")
      GenServer.cast(self(), {:start_daemon, daemon.options})
      {:noreply, state |> Map.put(:daemons, remove_daemon(state.daemons, pid))}
    else
      {:noreply, state}
    end
  end

  # Result of a transfer task:

  def handle_info({task_ref, {result, msg}}, state) do
    if msg do
      case result do
        :ok -> Logger.info(msg)
        :error -> Logger.error(msg)
      end
    end

    # To avoid the :DOWN message
    Process.demonitor(task_ref, [:flush])
    {:noreply, state}
  end

  # :EXIT of a transfer task:

  # ... Nothing !
  def handle_info({:EXIT, _task_pid, :normal}, state) do
    {:noreply, state}
  end

  # Others info messages :

  def handle_info(msg, state) do
    Logger.error("Handle_info - Unknown message:  #{inspect(msg)}")
    {:noreply, state}
  end

  @doc """
  (Gracefully) Terminate the SSCS server:
  - Save the failed transfers database to disk,
  - Stop the SSH daemon.
  """
  def terminate(_reason, state) do
    Logger.info("Gracefully terminating the SSCS server...")
    TransferDb.ets_to_dets(state.ets, @transfer_db_file)
    stop_daemons(state.daemons)
  end
end
