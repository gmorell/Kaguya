defmodule Kaguya do
  @moduledoc """
  Top level module responsible for starting the bot properly.

  ## Configuration

  * `server` - Hostname or IP address to connect with. String.
  * `server_ip_type` - IP version to use. Can be either `inet` or `inet6`
  * `port` - Port to connect on. Integer.
  * `bot_name` - Name to use by bot. String.
  * `channels` - List of channels to join. Format: `#<name>`. List
  * `help_cmd` - Specifies command to act as help. Defaults to `.help`. String
  * `use_ssl` - Specifies whether to use SSL or not. Boolean
  * `reconnect_interval` - Interval for reconnection in ms. Integer. Not used.
  * `server_timeout` - Timeout(ms) that determines when server gets disconnected. Integer.
                       When omitted Kaguya does not verifies connectivity with server.
                       It is recommended to set at least few minutes.
  """
  use Application

  @doc """
  Starts the bot, checking for proper configuration first.

  Raises exception on incomplete configuration.
  """
  def start(_type, _args) do
    opts = Application.get_all_env(:kaguya)
    if Enum.all?([:bot_name, :server, :port], fn k -> Keyword.has_key?(opts, k) end) do
      start_bot()
    else
      raise "You must provide configuration options for the server, port, and bot name!"
    end
  end

  defp start_bot do
    import Supervisor.Spec
    require Logger
    Logger.log :debug, "Starting bot!"

    :pg.start()
    :pg.create(:modules)
    :pg.create(:channels)

    :ets.new(:channels, [:set, :named_table, :public, {:read_concurrency, true}, {:write_concurrency, true}])
    :ets.new(:modules, [:set, :named_table, :public, {:read_concurrency, true}, {:write_concurrency, true}])

    children = [
      supervisor(Kaguya.ChannelSupervisor, [[name: Kaguya.ChannelSupervisor]]),
      supervisor(Kaguya.ModuleSupervisor, [[name: Kaguya.ModuleSupervisor]]),
      worker(Kaguya.Core, [[name: Kaguya.Core]]),
    ]

    Logger.log :debug, "Starting supervisors!"
    {:ok, _pid} = Supervisor.start_link(children, strategy: :one_for_one)
  end
end
