defmodule SscsEx.TransferDb do
  @moduledoc """
  SscsEx.TransferDb: Manage the ETS/DETS database where the transfers are recorded and the failed ones, kept.
  When the SSCS server inits, DETS (ie on disk) table is copied to the ETS (ie in memory) table. If there's some failed transfers remaining, they are then retryed.
  All operation are then done on the ETS table and when (or if) the server terminate, the ETS table is saved back to the DETS table.
  """
  @enforce_keys [
    :function,
    :local_path,
    :remote_path,
    :conn_opts
    # All keys are mandatory
  ]

  # Transfer struct
  # function = atom(ic) name of the client transfer function (example: :get_file)

  defstruct function: nil,
            local_path: nil,
            remote_path: nil,
            conn_opts: nil

  @type t() :: %__MODULE__{
          function: atom(),
          local_path: String.t(),
          remote_path: String.t(),
          conn_opts: Keyword.t()
        }
  @doc false
  def new(function, local_path, remote_path, conn_opts) do
    %__MODULE__{
      function: function,
      local_path: local_path,
      remote_path: remote_path,
      conn_opts: conn_opts
    }
  end

#   defp to_tuple(%__MODULE__{
#         function: function,
#         local_path: local_path,
#         remote_path: remote_path,
#         conn_opts: conn_opts
#       }) do
#     {function, local_path, remote_path, conn_opts}
#   end

  def elem_to_list(%__MODULE__{
    function: function,
    local_path: local_path,
    remote_path: remote_path,
    conn_opts: conn_opts
  }) do
[function, local_path, remote_path, conn_opts]
end
 
  @doc """
  Copy DETS file content to ETS Table.
  ## Inputs:
  - file_name: name of the DETS file.
  ## Outputs:
  - {:ok, _ets table_} | {:error, _message_}
  """
  def dets_to_ets(file_name) do
    with {:ok, dets} <- :dets.open_file(:dets_sscs_tranfers, [{:file, file_name}]),
         ets <- :ets.new(:ets_sscs_transfers, [:public]),
         ets <- :dets.to_ets(dets, ets) do
      :dets.close(dets)
      {:ok, ets}
    else
      {:error, reason} -> {:error, "#{inspect(reason)}"}
      _ -> {:error, "Cannot create ets table from dets file #{file_name}"}
    end
  end

  @doc """
  Copy ETS table content to DETS file.
  ## Inputs:
  - ets: ets table,
  - file_name: name of the DETS file.
  ## Outputs:
  - {:ok, nil} | {:error, _message_}
  """

  def ets_to_dets(ets, file_name) do
    with {:ok, dets} <- :dets.open_file(:dest_sscs_transfers, [{:file, file_name}]),
         dets <- :ets.to_dets(ets, dets) do
      :dets.close(dets)
      {:ok, nil}
    else
      {:error, reason} -> {:error, "#{inspect(reason)}"}
      _ -> {:error, "Cannot create ets table from dets file #{file_name}"}
    end
  end

  @doc """
  Add a transfer to ETS Table.
  ## Inputs:
  - table: name of the ETS table,
  - id: transfer Id,
  - function: transfer function,
  - local_path: path of local file, 
  - remote_path: path of remote file, 
  - host: name of remote server, 
  - port: port of remote server
  ## Outputs:
  - {:ok, nil} | {:error, _message_}
  """
  def add(table, id, function, local_path, remote_path, conn_opts) do
    with transfer_record <- new(function, local_path, remote_path, conn_opts),
         true <- :ets.insert_new(table, {id, transfer_record}) do
      {:ok, nil}
    else
      false -> {:ok, "Element already present"}
      {'error', reason} -> {:error, "#{inspect(reason)}"}
    end
  end

   @doc """
  Remove a transfer from the ETS table.
  ## Inputs:
  - table: ets table,
  - id: transfer Id.
  ## Outputs:
  - {:ok, nil} | {:error, _message_}
  """

  def remove(table, id) do
    with true <- :ets.delete(table, id) do
      {:ok, nil}
    else
      # {:error, reason}  
      any -> any
    end
  end

  @doc """
  find a transfer in the ETS table.
  ## Inputs:
  - table: ets table,
  - id: transfer Id.
  ## Outputs:
  - {:ok, _record_} | {:error, _message_}
  """

  def find(table, id) do
    with [{_id, record}] <- :ets.lookup(table, id) do
      {:ok, record}
    else
      _ -> {:error, "No such id (#{inspect(id)}) in table."}
    end
  end

  defp transfer2string({id, %__MODULE__{conn_opts: conn_opts, function: function, local_path: local_path, remote_path: remote_path }}) do
    "Id = #{id}, Host = #{conn_opts[:host]}:#{conn_opts[:port]}, Function = #{function}, Local file = #{local_path}, Remote file = #{remote_path}"
  end
 
  @doc """
  Display the ETS table content on standard output.
  ## Inputs:
  - table: ets table,
  ## Outputs:
  - {:ok, "Failed transfers table content: transfer 1 , ... , transfer n" } | {:error, "No transfer table available."}
  """
  def display(table) do
    if table do
      {:ok, :ets.tab2list(table)
            |> Enum.reduce( "Failed transfers table content:", fn obj, acc -> acc <> "\n" <> transfer2string(obj) end) }
    else
      {:error, "No transfer table available."}
    end
end

@doc """
  Remove all transfers from the ETS table.
  ## Inputs:
  - table: ets table,
  ## Outputs:
  - {:ok, nil} | {:error, "No transfer table available."}
  """

 def clean(table) do
  if table do
    :ets.delete_all_objects(table)
    {:ok, nil}
  else
    {:error, "No transfer table available."}
  end
end

@doc """
  Get the ETS table content and return it in a list.
  ## Inputs:
  - table: ets table,
  ## Outputs:
  - {:ok, _[object 1, ... , object n]_} | {:error, "No transfer table available."}
  """
def tab2list(table) do
  if table do
    {:ok,:ets.tab2list(table)}
  else
    {:error, "No transfer table available."}
  end
end

end
