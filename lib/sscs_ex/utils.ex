defmodule SscsEx.Utils do
  #alias SFTP

   @doc """ 
  Force the :ok/:error functions to return a tuple.
  ## Inputs:
  - item: :ok, :error or any.
  ## Outputs: 
  - {:ok, nil} | {:error, nil} | _any_
  """
  def force_tuple_result(:ok), do: {:ok, nil}
  def force_tuple_result(:error), do: {:error, nil}
  def force_tuple_result(any), do: any

  @doc """ 
  Force a String to be converted to a charlist (to feed the Erlang functions).
  ## Input:
  - str: String or charlist.
  ## Outputs:
  - _char list_
  """
  def get_charlist(str) when is_binary(str), do: String.to_charlist(str)
  def get_charlist(str), do: str

   @doc """ 
  Disable logging while the function 'fun' is executed.
  ## Input:
  - fun: a function.
  ## Outputs:
  - The output of the function
  """
  def log_suppress(fun) do
    #backend = Logger.remove_backend(:console, :flush)
    pid =self()
    Logger.disable(pid)
    result = fun.()
    Logger.enable(pid)
    # case backend do
    #   :ok -> Logger.add_backend(:console)
    #   {:error, _} -> nil
    # end

    result
  end

 

   @doc """ 
  Return the checksum of a stream.
  ## Input:
  - stream: the stream,
  - crc_type: type of checksum. can be: :sha, :sha224, :sha256, :sha384, :sha512, :sha3_224, :sha3_256, :sha3_384, :sha3_512, :blake2b, :blake2s, :md5 or :md4
  ## Outputs:
  - _checksum_
  """
  def stream_checksum(stream, crc_type) do
    stream
    |> Enum.reduce(:crypto.hash_init(crc_type), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16()
  end

   

  @doc """ 
  Test if num is a valid port number.
  ## Input:
  - num: an integer.
  ## Outputs:
  - :ok | :error
  """
  def is_port(num) do
    # with true <- is_binary(strnum),
    #      {num, _} <- Integer.parse(strnum),
    #      true <- is_integer(num),
    #      true <- num >= 0 && num < 65536 do
    #   :ok
    # else
    #   _ -> :error
    # end
    if is_integer(num) && num >= 0 && num < 65536 do
      :ok
    else
      :error
    end
  end

  @doc """ 
  Test if every keys of required_keys are present in the keyword list options.
   ## Input:
  - options: keyword list to test,
  - required_keys: list of keys to test.
  ## Outputs:
  - {:ok, nil} | {:error, _message_}
  """
  def are_options(options, required_keys) do
    with true <- Keyword.keyword?(options),
         #     true <- required_keys |> Enum.all?(&Keyword.has_key?(options, &1)),
         [] <-
           required_keys
           |> Enum.map(fn x -> Keyword.has_key?(options, x) || x end)
           |> Enum.filter(&(!is_boolean(&1))) do
      {:ok, nil}
    else
      false -> {:error, "#{inspect(options)} is not a list of keywords"}
      list -> {:error, "Missing keyword(s): #{inspect(list)}"}
    end
  end

  @doc """ 
  Compute a transfer rate.
   ## Input:
  - file_size: the size of the file,
  - seconds: the time elapsed in seconds,
  - unit: the unit: can be: :mb (MB) or :kb (KB).
  ## Outputs:
  - {:ok, _transfer rate_} | {:error, _message_}
  """
  def transfer_rate(file_size, seconds, unit) do
     ratio = file_size / seconds
      case unit do
        :mb -> {:ok, to_string(Float.round(ratio / 1048576, 2)) <> " Mb/s"}
        :kb -> {:ok, to_string(Float.round(ratio / 1024, 2)) <> " Kb/s"}
        any ->   {:error, "Unknown size unit: #{inspect(any)}"}
      end
  end 

  @doc """ 
  Return the second part of a response tuple ({:ok, item} or {:error, item}) when :ok. _default_ otherwise.
  (Usefull for piping !)
  ## Inputs:
  - {ok_or_error, item }: {:ok, item} | {:error, item}
  - default: default value when ok_or_error is not :ok
  ## Outputs:
  - _item_ or _default_
  """
  def tuple_to_response({ok_or_error, response }, default) do
    case ok_or_error do
      :ok -> response
      _ -> default
    end
  end

  
end
