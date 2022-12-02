defmodule MetricsCake.BuiltinMetrics do
  def new(metric) do
    Telemetry.Metrics.last_value(
      "pancake_metrics_reporter.built_in.#{metric}",
      event_name: [:pancake_metrics_reporter, :built_in, metric],
      reporter_options: [poller: {15_000, fn -> gather_builtin_metric(metric) end}]
    )
  end

  def gather_builtin_metric(:cpu) do
    shell_command = 'top -b -n 5 -d 0.2 | awk /Cpu/'
    line =
      :os.cmd(shell_command)
      |> List.to_string()
      |> String.trim()
      |> String.split("\n")
      |> List.last()

    [idle_perent] = Regex.run(~r/[\d\.]+(?= id)/, line)
    100 - String.to_float(idle_perent) |> Float.round(2)
  end

  def gather_builtin_metric(:memory) do
    shell_command = ~c(free -b | sed -n '2 p' | awk '{print $2,$3,$4,$6}')
    line =
      :os.cmd(shell_command)
      |> List.to_string()
      |> String.trim()
      |> String.split("\n")
      |> List.last()

    metrics =
      Regex.named_captures(~r/(?<total>\d+) (?<used>\d+) (?<free>\d+) (?<cache>\d+)/, line)
      |> Enum.map(fn {key, value} ->
        %{
          type: key,
          value: String.to_integer(value)
        }
      end)

    metrics ++ [%{type: "beam_vm", value: :erlang.memory(:total)}]
  end

  def gather_builtin_metric(:network) do
    shell_command = ~c(sudo iftop -tB -s 2 -i eth0 | grep 'Total')
    lines =
      :os.cmd(shell_command)
      |> List.to_string()
      |> String.trim()
      |> String.split("\n")

    send_rate = Enum.find(lines, & String.contains?(&1, "Total send rate"))
    receive_rate = Enum.find(lines, & String.contains?(&1, "Total receive rate"))

    to_number = fn string ->
      if String.contains?(string, "."),
        do: String.to_float(string),
        else: String.to_integer(string)
    end

    convert_to_byte = fn
      value, "B" -> value
      value, "KB" -> value * 1024
      value, "MB" -> value * 1024 * 1024
    end

    regex = ~r/([\d\.]+)(B|KB|MB)/
    metrics = []
    metrics =
      case Regex.run(regex, send_rate) do
        [_, value, unit] ->
          metrics ++ [%{
            direction: "egress",
            interface: "eth0",
            value: to_number.(value) |> convert_to_byte.(unit)
          }]

        nil -> metrics
      end

    metrics =
      case Regex.run(regex, receive_rate) do
        [_, value, unit] ->
          metrics ++ [%{
            direction: "ingress",
            interface: "eth0",
            value: to_number.(value) |> convert_to_byte.(unit)
          }]

        nil -> metrics
      end

    metrics
  end

  def gather_builtin_metric(:beam) do
    [
      %{type: "active_tasks", value: :erlang.statistics(:total_active_tasks_all)}
    ]
  end
end
