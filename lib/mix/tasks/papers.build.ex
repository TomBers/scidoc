defmodule Mix.Tasks.Papers.Build do
  @moduledoc """
  Builds generated paper artifacts.

      mix papers.build attention

  The `attention` build uses TeX4ht (`make4ht`) to compile the local TeX source
  into selectable HTML under `priv/static/generated_papers/attention`.
  """

  use Mix.Task

  @shortdoc "Builds generated paper HTML artifacts"

  @impl true
  def run(["attention"]) do
    app_root = File.cwd!()
    source = Path.join(app_root, "priv/static/papers/attention/ms.tex")
    source_root = Path.join(app_root, "priv/static/papers/attention")
    output_dir = Path.join(app_root, "priv/static/generated_papers/attention")

    File.rm_rf!(output_dir)
    File.mkdir_p!(output_dir)

    env = [{"TEXINPUTS", source_root <> "//:"}]

    {output, status} =
      System.cmd(
        "make4ht",
        ["-u", "-f", "html5", "-d", output_dir, source],
        cd: app_root,
        env: env,
        stderr_to_stdout: true
      )

    Mix.shell().info(output)

    output_file = Path.join(output_dir, "ms.html")

    cond do
      File.exists?(output_file) ->
        postprocess_attention_output(output_dir)

        if status == 0 do
          Mix.shell().info("Generated #{Path.relative_to_cwd(output_file)}")
        else
          Mix.shell().info(
            "make4ht exited with status #{status}, but #{Path.relative_to_cwd(output_file)} was generated."
          )
        end

      true ->
        Mix.raise("make4ht failed with status #{status} and did not generate #{output_file}")
    end
  end

  def run(_args) do
    Mix.raise("Usage: mix papers.build attention")
  end

  defp postprocess_attention_output(output_dir) do
    css_path = Path.join(output_dir, "ms.css")

    if File.exists?(css_path) do
      File.write!(css_path, compiled_reader_overrides(), [:append])
    end
  end

  defp compiled_reader_overrides do
    """

    /* Sciencecritic compiled reader overrides */
    :root {
      color-scheme: light;
      background: #ffffff;
    }

    html,
    body {
      min-height: 100%;
      background: #ffffff !important;
      color: #172033 !important;
    }

    body {
      max-width: 1040px !important;
      margin: 0 auto !important;
      padding: 2.25rem clamp(1rem, 4vw, 3rem) 4rem !important;
      font-size: 17px;
      line-height: 1.72;
    }

    body,
    p,
    div,
    td,
    th,
    li {
      color: #172033 !important;
    }

    a {
      color: #1d4ed8 !important;
    }

    div.maketitle,
    div.abstract,
    div.figure,
    figure.figure,
    div.float,
    figure.float,
    table.tabular {
      max-width: 100%;
    }

    div.figure,
    figure.figure,
    div.float,
    figure.float {
      margin-top: 1.6rem !important;
      margin-bottom: 1.6rem !important;
      padding: 1rem;
      border: 1px solid rgba(15, 23, 42, 0.08);
      border-radius: 1rem;
      background: #f8fafc;
    }

    div.figure img:not(.math):not(.frac):not(.sqrt),
    figure.figure img:not(.math):not(.frac):not(.sqrt),
    div.float img:not(.math):not(.frac):not(.sqrt),
    figure.float img:not(.math):not(.frac):not(.sqrt),
    img[src^=\"Figures/\"] {
      display: block;
      width: min(100%, 760px) !important;
      height: auto !important;
      max-height: 620px;
      margin: 0 auto;
      object-fit: contain;
    }

    img.math,
    img.frac,
    img.sqrt,
    img[class*=\"math\"] {
      max-width: 100%;
      height: auto;
      background: transparent !important;
      filter: none !important;
    }

    @media (prefers-color-scheme: dark) {
      body {
        background: #ffffff !important;
        color: #172033 !important;
      }

      img[src^=\"ms\"] {
        filter: none !important;
      }
    }
    """
  end
end
