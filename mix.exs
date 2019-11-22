defmodule Sscs.MixProject do
  use Mix.Project

  def project do
    [
      app: :sscs_ex,
      version: "0.1.0",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # Docs
    name: "SSCS Ex",
    docs: [
      main: "SscsEx", # The main page in the docs
      logo: "logo/SSCS_Ex.png",
      extras: ["README.md"],
      authors: ["Jipen"]
    ]
  ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      applications: [:elixir_uuid],
      extra_applications: [:logger, :ssh, :logger_file_backend],
      mod: {SscsEx, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:elixir_uuid, "~> 1.2" },
      {:logger_file_backend, "~> 0.0.10"}, # writes log messages to a file
      {:ex_doc, "~> 0.21", only: :dev, runtime: false}
    ]
  end
end
