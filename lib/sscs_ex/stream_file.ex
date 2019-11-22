defmodule SscsEx.StreamFile do
    @moduledoc "
    A stream to download/upload file parts from a server through SFTP
    "
    alias SscsEx.SFTP

    defstruct connection: nil, handle_file: nil, byte_length: 32768
  
    @type t :: %__MODULE__{}
  
    @doc false
    def __build__(connection, handle_file, byte_length) do
      %__MODULE__{connection: connection, handle_file: handle_file, byte_length: byte_length}
    end
  
    defimpl Collectable do
      def into(%{connection: connection, handle_file: handle_file, byte_length: _byte_length} = stream) do
        {:ok, into(connection, handle_file, stream)}
      end
  
      defp into(connection, handle, stream) do
        fn
          :ok, {:cont, x} ->
            SFTP.write_handle(connection, handle, x)
  
          :ok, :done ->
            :ok = SFTP.close_file_handle(connection, handle)
            stream
  
          :ok, :halt ->
            :ok = SFTP.close_file_handle(connection, handle)
        end
      end
    end
  
    defimpl Enumerable do

      def reduce(%{connection: connection, handle_file: handle_file, byte_length: byte_length}, acc, fun) do
        start_function = fn ->
          handle_file
        end
  
        next_function = &SFTP.each_binstream(connection, &1, byte_length)
  
        close_function = &SFTP.close_file_handle(connection, &1)
  
        Stream.resource(start_function, next_function, close_function).(acc, fun)
      end
      
      def slice(_stream) do
        {:error, __MODULE__}
      end

      def count(_stream) do
        {:error, __MODULE__}
      end
  
      def member?(_stream, _term) do
        {:error, __MODULE__}
      end

      
    end
  end