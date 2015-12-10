defmodule Kaguya.Module do
  use Behaviour

  @moduledoc """
  When  this module is used, it will create wrapper
  functions which allow it to be automatically registered
  as a module and include all macros. It can be included like:
  `use Kaguya.Module, "module name here"`
  """

  defmacro __using__(module_name) do
    # Module.put_attribute Kaguya, :modules, __MODULE__ 
    quote bind_quoted: [module_name: module_name] do
      @module_name module_name
      use GenServer
      import Kaguya.Module

      # modules = Application.get_env(:kaguya, :modules, [])
      # new_modules = [__MODULE__|modules]
      # Application.put_env(:kaguya, :modules, new_modules, persist: true)

      def start_link(opts \\ []) do
        {:ok, _pid} = GenServer.start_link(__MODULE__, :ok, [])
      end

      defoverridable start_link: 1

      def init(:ok) do
        require Logger
        Logger.log :debug, "Started module #{@module_name}!"
        :pg2.join(:modules, self)
        {:ok, {}}
      end

      defoverridable init: 1

      def handle_cast({:msg, message}, state) do
        require Logger
        Logger.log :debug, "Running module #{@module_name}'s dispatcher!"
        try do
          handle_message({:msg, message}, {true})
        rescue
          e in FunctionClauseError ->
            Logger.log :debug, "Message fell through for #{@module_name}!"
            {:noreply, state}
        end
      end
    end
  end

  @doc """
  Defines a group of matchers which will handle all messages of the corresponding
  IRC command.

  ## Example
  ```
  handle "PING" do
    match_all :pingHandler
    match_all :pingHandler2
  end
  ```

  In the example, all IRC messages which have the PING command
  will be matched against `:pingHandler` and `:pingHandler2`
  """
  defmacro handle(command, do: body) do
    quote do
      def handle_message({:msg, %{command: unquote(command)} = var!(message)}, state) do
        unquote(body)
        {:noreply, state}
      end
    end
  end

  @doc """
  Defines a matcher which always calls its corresponding
  function. Example: `match_all :pingHandler`
  """
  defmacro match_all(function) do
    quote do
      unquote(function)(var!(message))
    end
  end

  @doc """
  Defines a matcher which will match a regex againt the trailing portion
  of an IRC message. Example: `match_re ~r"me|you", :meOrYouHandler`
  """
  defmacro match_re(re, function) do
    quote do
      if Regex.match?(unquote(re), var!(message).trailing) do
        unquote(function)(var!(message))
      end
    end
  end

  @doc """
  Defines a matcher which will match a string defining
  various capture variables against the trailing portion
  of an IRC message.

  ## Example
  ```
  handle "PRIVMSG" do
    match_all "!rand :low :high", :genRand
  end
  ```

  In this example, the geRand function will be called
  when a user sends a message to a channel saying something like
  `!rand 0 10`. The genRand function will be passed the messages,
  and a map which will look like `%{low: 0, high: 10}`.

  Available match params are `:param` and `~param`. The former
  will match a specific space separated parameter, whereas the latter matches
  an unlimited number of characters.
  """
  defmacro match(match_str, function) do
    re = match_str |> extract_vars |> Macro.escape
    if String.contains? match_str, [":", "~"] do
      quote do
        case Regex.named_captures(unquote(re), var!(message).trailing) do
          nil -> :ok
          res -> unquote(function)(var!(message), res)
        end
      end
    else
      quote do
        if var!(message).trailing == unquote(match_str) do
          unquote(function)(var!(message))
        end
      end
    end
  end

  defp extract_vars(match_str) do
    parts = String.split(match_str)
    l = for part <- parts, do: gen_part(part)
    expr = Enum.join(l, " ")
    Regex.compile!(expr)
  end

  defp gen_part(part) do
    case part do
      ":" <> param -> "(?<#{param}>[a-zA-Z0-9]+)"
      "~" <> param -> "(?<#{param}>.+)"
      text -> Regex.escape(text)
    end
  end

  @doc """
  Creates a validation stack for use in a handler.

  ## Example:
  ```
  validator :is_me do
    :check_nick_for_me
  end

  def check_nick_for_me(%{user: %{nick: "me"}}), do: true
  def check_nick_for_me(_message), do: false
  ```

  In the example, a validator named :is_me is created.
  In the validator, any number of function can be defined
  with atoms, and they will be all called. Every validator
  function will be given a message, and should return either
  true or false.
  """
  defmacro validator(name, do: body) do
    if is_atom(body) do
      create_validator(name, [body])
    else
      {:__block__, [], funcs} = body
      create_validator(name, funcs)
    end
  end

  defp create_validator(name, funcs) do
    quote do
      def unquote(name)(message) do
        res = for func <- unquote(funcs), do: apply(__MODULE__, func, [message])
        !Enum.member?(res, false)
      end
    end
  end

  @doc """
  Creates a scope in which only messages that succesfully pass through
  the given will be used.

  ## Example:
  ```
  handle "PRIVMSG" do
    validate :is_me do
      match "Hi", :hiHandler
    end
  end
  ```

  In the example, only messages which pass through the is_me validator,
  defined prior will be matched within this scope.
  """
  defmacro validate(validator, do: body) do
    quote do
      if unquote(validator)(var!(message)) do
        unquote(body)
      end
    end
  end

  @doc """
  Sends a response to the sender of the PRIVMSG with a given message.
  Example: `reply "Hi"`
  """
  defmacro reply(response) do
    quote do
      [chan] = var!(message).args
      Kaguya.Util.sendPM(unquote(response), chan)
    end
  end
end
