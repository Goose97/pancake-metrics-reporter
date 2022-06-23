defmodule MetricsCake.PrometheusAdapter do
  use Plug.Router

  plug Plug.Parsers, parsers: [:urlencoded, :multipart]
  plug :match
  plug :dispatch

  get "/" do
    callback = :persistent_term.get(:report_callback)
    response = Jason.encode!(%{
      name: :os.cmd('hostname') |> List.to_string() |> String.trim(),
      payload: callback.()
    })
    send_resp(conn, 200, response)
  end

  def start(opts) do
    report_callback = Keyword.get(opts, :report_callback, fn -> [] end)
    adapter_port = Keyword.get(opts, :adapter_port, 4001)
    :persistent_term.put(:report_callback, report_callback)
    Plug.Cowboy.http(__MODULE__, [], port: adapter_port)
  end
end
