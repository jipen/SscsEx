defmodule SscsEx.Supervisor do
    use Supervisor
    require Logger

    def start_link do
      Supervisor.start_link(__MODULE__, :ok)
    end
  
    def init(:ok) do
      options = Application.get_env(:sscs_ex, :ssh_conf)
      children = [
        # Supervisor.child_spec({SscsEx.Server, options}, shutdown: 123_456)
        {SscsEx.Server, options}
      ]
      Supervisor.init(children, strategy: :one_for_one)
  
    end
  
  end