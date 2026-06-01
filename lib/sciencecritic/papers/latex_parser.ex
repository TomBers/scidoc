defmodule Sciencecritic.Papers.LatexParser do
  @moduledoc """
  A deliberately small LaTeX parser for paper-reading prototypes.

  This does not attempt to compile or fully understand TeX. It resolves local
  `\input{...}` calls and extracts enough structure for a selectable semantic
  paper view: title, abstract, section headings, paragraphs, figures, tables,
  and equations.
  """

  @heading_regex ~r/\\(section|subsection|subsubsection)\*?\{([^{}]+)\}/
  @environment_regex ~r/\\begin\{(figure|table|equation|equation\*|align|align\*)\}(.*?)\\end\{\1\}/s

  @macros %{
    "dmodel" => "d_model",
    "dff" => "d_ff",
    "dffn" => "d_ffn",
    "kq" => "q",
    "km" => "k",
    "vq" => "o",
    "vm" => "m",
    "Wkq" => "W_q",
    "Wkm" => "W_k",
    "Wvq" => "W_o",
    "Wvm" => "W_m"
  }

  def parse_directory(root_dir, main_file \\ "ms.tex") do
    with {:ok, source} <- expanded_source(root_dir, main_file) do
      title = source |> capture(~r/\\title\{(.*?)\}/s) |> clean_inline()
      abstract_source = capture(source, ~r/\\begin\{abstract\}(.*?)\\end\{abstract\}/s)

      paper_source =
        source
        |> strip_preamble()
        |> remove_abstract()
        |> remove_bibliography()

      {:ok,
       %{
         id: "attention-is-all-you-need",
         title: blank_default(title, "Untitled Paper"),
         source_root: root_dir,
         abstract_blocks: parse_blocks(abstract_source, root_dir, "abstract"),
         sections: parse_sections(paper_source, root_dir)
       }}
    end
  end

  def expanded_source(root_dir, main_file \\ "ms.tex") do
    read_tex(root_dir, main_file, MapSet.new())
  end

  defp read_tex(root_dir, file, seen) do
    normalized_file = normalize_tex_file(file)
    path = Path.expand(normalized_file, root_dir)

    cond do
      not String.starts_with?(path, Path.expand(root_dir)) ->
        {:error, {:unsafe_path, normalized_file}}

      MapSet.member?(seen, path) ->
        {:ok, ""}

      true ->
        case File.read(path) do
          {:ok, content} ->
            seen = MapSet.put(seen, path)

            content
            |> strip_comments()
            |> resolve_inputs(root_dir, seen)

          {:error, reason} ->
            {:error, {reason, normalized_file}}
        end
    end
  end

  defp normalize_tex_file(file) do
    file = String.trim(file)

    if Path.extname(file) == "" do
      file <> ".tex"
    else
      file
    end
  end

  defp resolve_inputs(source, root_dir, seen) do
    input_regex = ~r/\\(?:input|subfile)\{([^{}]+)\}/

    parts = Regex.split(input_regex, source, include_captures: true, trim: false)

    resolved =
      Enum.map(parts, fn part ->
        case Regex.run(input_regex, part) do
          [_, input_file] ->
            case read_tex(root_dir, input_file, seen) do
              {:ok, input_source} -> input_source
              {:error, _reason} -> ""
            end

          _ ->
            part
        end
      end)

    {:ok, Enum.join(resolved)}
  end

  defp strip_comments(source) do
    source
    |> String.split("\n")
    |> Enum.map(&strip_comment_from_line/1)
    |> Enum.join("\n")
  end

  defp strip_comment_from_line(line) do
    line
    |> String.graphemes()
    |> Enum.reduce_while({[], 0}, fn
      "%", {chars, slash_count} ->
        if rem(slash_count, 2) == 0 do
          {:halt, {chars, slash_count}}
        else
          {:cont, {["%" | chars], 0}}
        end

      "\\", {chars, slash_count} ->
        {:cont, {["\\" | chars], slash_count + 1}}

      char, {chars, _slash_count} ->
        {:cont, {[char | chars], 0}}
    end)
    |> elem(0)
    |> Enum.reverse()
    |> Enum.join()
  end

  defp strip_preamble(source) do
    case String.split(source, "\\maketitle", parts: 2) do
      [_before, after_title] -> after_title
      _ -> source
    end
  end

  defp remove_abstract(source) do
    Regex.replace(~r/\\begin\{abstract\}.*?\\end\{abstract\}/s, source, "\n")
  end

  defp remove_bibliography(source) do
    source
    |> String.split("\\bibliographystyle", parts: 2)
    |> List.first()
    |> String.split("\\begin{thebibliography}", parts: 2)
    |> List.first()
  end

  defp parse_sections(source, root_dir) do
    marked =
      Regex.replace(@heading_regex, source, fn _full, kind, title ->
        "\n\n@@PAPER_HEADING|#{kind}|#{clean_inline(title)}@@\n\n"
      end)

    {sections, current} =
      marked
      |> String.split(~r/^@@PAPER_HEADING\|/m, trim: true)
      |> Enum.reduce({[], nil}, fn chunk, {sections, current} ->
        case String.split(chunk, "@@", parts: 2) do
          [heading, body] ->
            if String.contains?(heading, "|") do
              if current == nil do
                {sections, new_section(heading, body)}
              else
                finalized = finalize_section(current, root_dir)
                {[finalized | sections], new_section(heading, body)}
              end
            else
              {sections, append_body(current, chunk)}
            end

          _ ->
            {sections, append_body(current, chunk)}
        end
      end)

    sections = if current, do: [finalize_section(current, root_dir) | sections], else: sections

    sections
    |> Enum.reverse()
    |> number_sections()
  end

  defp new_section(heading, body) do
    [kind, title] = String.split(heading, "|", parts: 2)
    title = String.trim(title)

    %{
      id: slug(title),
      level: heading_level(kind),
      title: title,
      raw_body: body
    }
  end

  defp append_body(nil, _chunk), do: nil
  defp append_body(section, chunk), do: Map.update!(section, :raw_body, &(&1 <> "\n" <> chunk))

  defp finalize_section(section, root_dir) do
    section
    |> Map.put(:blocks, parse_blocks(section.raw_body, root_dir, section.id))
    |> Map.delete(:raw_body)
  end

  defp heading_level("section"), do: 1
  defp heading_level("subsection"), do: 2
  defp heading_level("subsubsection"), do: 3

  defp number_sections(sections) do
    {numbered_sections, _counters} =
      Enum.map_reduce(sections, {0, 0, 0}, fn section,
                                              {section_count, subsection_count,
                                               subsubsection_count} ->
        case section.level do
          1 ->
            section_count = section_count + 1

            {Map.put(section, :number, Integer.to_string(section_count)), {section_count, 0, 0}}

          2 ->
            section_count = max(section_count, 1)
            subsection_count = subsection_count + 1

            {Map.put(section, :number, "#{section_count}.#{subsection_count}"),
             {section_count, subsection_count, 0}}

          3 ->
            section_count = max(section_count, 1)
            subsection_count = max(subsection_count, 1)
            subsubsection_count = subsubsection_count + 1

            {Map.put(
               section,
               :number,
               "#{section_count}.#{subsection_count}.#{subsubsection_count}"
             ), {section_count, subsection_count, subsubsection_count}}
        end
      end)

    numbered_sections
  end

  defp parse_blocks(source, root_dir, prefix) do
    {source_with_placeholders, environment_blocks} =
      extract_environment_blocks(source, root_dir, prefix)

    source_with_placeholders
    |> String.split(~r/\n\s*\n/, trim: true)
    |> Enum.flat_map(fn chunk ->
      chunk = String.trim(chunk)

      case Regex.run(~r/^@@PAPER_BLOCK:(\d+)@@$/, chunk) do
        [_, index] ->
          [Map.fetch!(environment_blocks, String.to_integer(index))]

        _ ->
          paragraph = clean_inline(chunk)

          if paragraph == "" or ignorable_paragraph?(paragraph) do
            []
          else
            [
              %{
                id: stable_block_id(prefix, paragraph),
                type: :paragraph,
                text: paragraph
              }
            ]
          end
      end
    end)
  end

  defp extract_environment_blocks(source, root_dir, prefix) do
    matches = Regex.scan(@environment_regex, source, return: :index)

    {reversed_parts, blocks, cursor, _index} =
      Enum.reduce(matches, {[], %{}, 0, 0}, fn [
                                                 {start, length},
                                                 {env_start, env_length},
                                                 {body_start, body_length}
                                               ],
                                               {parts, blocks, cursor, index} ->
        before_env = binary_part(source, cursor, start - cursor)
        env = binary_part(source, env_start, env_length)
        body = binary_part(source, body_start, body_length)
        full = binary_part(source, start, length)
        block = parse_environment_block(env, body, full, root_dir, prefix, index)

        {["\n\n@@PAPER_BLOCK:#{index}@@\n\n", before_env | parts], Map.put(blocks, index, block),
         start + length, index + 1}
      end)

    tail = binary_part(source, cursor, byte_size(source) - cursor)
    {Enum.reverse([tail | reversed_parts]) |> Enum.join(), blocks}
  end

  defp parse_environment_block(env, body, full, root_dir, prefix, index) do
    cond do
      env == "figure" ->
        %{
          id: "#{prefix}-figure-#{index + 1}",
          type: :figure,
          caption: full |> capture(~r/\\caption\{(.*?)\}/s) |> clean_inline(),
          image_src: figure_src(full, root_dir),
          latex: String.trim(full)
        }

      env == "table" ->
        %{
          id: "#{prefix}-table-#{index + 1}",
          type: :table,
          caption: full |> capture(~r/\\caption\{(.*?)\}/s) |> clean_inline(),
          rows: full |> parse_table_rows(),
          text: full |> clean_table_text(),
          latex: String.trim(full)
        }

      true ->
        %{
          id: "#{prefix}-equation-#{index + 1}",
          type: :equation,
          text: body |> clean_equation_text(),
          latex: String.trim(full)
        }
    end
  end

  defp figure_src(source, root_dir) do
    with [_, include_path] <- Regex.run(~r/\\includegraphics(?:\[[^\]]*\])?\{([^{}]+)\}/, source),
         {:ok, static_path} <- resolve_static_asset(include_path, root_dir) do
      static_path
    else
      _ -> nil
    end
  end

  defp resolve_static_asset(include_path, root_dir) do
    candidates =
      if Path.extname(include_path) == "" do
        Enum.map([".png", ".jpg", ".jpeg", ".pdf"], &(include_path <> &1))
      else
        [include_path]
      end

    case Enum.find(candidates, &(root_dir |> Path.join(&1) |> File.exists?())) do
      nil -> {:error, :not_found}
      found -> {:ok, "/papers/attention/#{found}"}
    end
  end

  defp parse_table_rows(source) do
    source
    |> extract_tabular_body()
    |> normalize_table_source()
    |> String.split(~r/\\\\/, trim: true)
    |> Enum.map(fn row ->
      row
      |> String.split("&")
      |> Enum.map(&clean_inline/1)
      |> Enum.reject(&(&1 == ""))
    end)
    |> Enum.reject(&(&1 == []))
  end

  defp extract_tabular_body(source) do
    case Regex.run(~r/\\begin\{tabular\}\{[^{}]*\}(.*?)\\end\{tabular\}/s, source) do
      [_, body] -> body
      _ -> source
    end
  end

  defp normalize_table_source(source) do
    source
    |> String.replace(~r/\\(?:toprule|midrule|bottomrule|hline)/, "")
    |> String.replace(~r/\\cmidrule(?:\([^)]*\))?\{[^{}]+\}/, "")
    |> String.replace(~r/\\specialrule\{[^{}]+\}\{[^{}]+\}\{[^{}]+\}/, "")
    |> String.replace(~r/\\rule\{[^{}]+\}\{[^{}]+\}/, "")
    |> unwrap_table_span_commands()
  end

  defp unwrap_table_span_commands(source) do
    Enum.reduce(1..6, source, fn _, acc ->
      acc
      |> String.replace(~r/\\multicolumn\{[^{}]+\}\{[^{}]+\}\{([^{}]*)\}/, "\\1")
      |> String.replace(~r/\\multirow\{[^{}]+\}\{[^{}]+\}\{([^{}]*)\}/, "\\1")
    end)
  end

  defp clean_table_text(source) do
    source
    |> parse_table_rows()
    |> Enum.map(&Enum.join(&1, " | "))
    |> Enum.join("\n")
  end

  defp clean_equation_text(source) do
    source
    |> String.replace(~r/\\label\{[^{}]+\}/, "")
    |> clean_math_text(:display)
  end

  defp clean_inline(nil), do: ""

  defp clean_inline(source) do
    source
    |> replace_citations()
    |> replace_refs()
    |> replace_macros()
    |> replace_inline_math()
    |> unwrap_text_commands()
    |> unwrap_frac_like_commands()
    |> String.replace(~r/\\url\{([^{}]+)\}/, "\\1")
    |> String.replace(~r/\\label\{[^{}]+\}/, "")
    |> String.replace("~", " ")
    |> String.replace("\\&", "&")
    |> String.replace("\\%", "%")
    |> String.replace("{\\L}", "Ł")
    |> String.replace(~r/\\[a-zA-Z]+\*?(?:\[[^\]]*\])?/, "")
    |> String.replace(~r/[{}]/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp replace_inline_math(source) do
    source =
      Regex.replace(~r/\$([^$]+)\$/, source, fn _, math -> clean_math_text(math, :inline) end)

    source =
      Regex.replace(~r/\\\((.*?)\\\)/s, source, fn _, math -> clean_math_text(math, :inline) end)

    Regex.replace(~r/\\\[(.*?)\\\]/s, source, fn _, math -> clean_math_text(math, :display) end)
  end

  defp clean_math_text(source, _mode) do
    source
    |> replace_macros()
    |> unwrap_text_commands()
    |> unwrap_frac_like_commands()
    |> String.replace(~r/\\sqrt\{([^{}]+)\}/, "√(\\1)")
    |> String.replace(~r/\^\{([^{}]+)\}/, "^(\\1)")
    |> String.replace(~r/_\{([^{}]+)\}/, "_\\1")
    |> String.replace(~r/\\(?:left|right)/, "")
    |> String.replace(~r/\\(?:cdot|times)/, "·")
    |> String.replace(~r/\\(?:parallel)/, "∥")
    |> String.replace(~r/\\(?:infty)/, "∞")
    |> String.replace(~r/\\[a-zA-Z]+\*?/, "")
    |> String.replace(~r/[{}]/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp unwrap_frac_like_commands(source) do
    Enum.reduce(1..6, source, fn _, acc ->
      acc
      |> String.replace(~r/\\(?:frac|nicefrac)\{([^{}]+)\}\{([^{}]+)\}/, "(\\1)/(\\2)")
      |> String.replace(~r/\\text\{([^{}]*)\}/, "\\1")
    end)
  end

  defp replace_citations(source) do
    Regex.replace(~r/\\cite[t|p|alp|author|year|yearpar]*\{([^{}]+)\}/, source, fn _, keys ->
      "[#{String.replace(keys, ",", ", ")}]"
    end)
  end

  defp replace_refs(source) do
    source
    |> String.replace(~r/\\(?:ref|pageref)\{([^{}]+)\}/, "\\1")
    |> String.replace(~r/\\autoref\{([^{}]+)\}/, "\\1")
  end

  defp replace_macros(source) do
    Enum.reduce(@macros, source, fn {macro, replacement}, acc ->
      String.replace(acc, "\\#{macro}", replacement)
    end)
  end

  defp unwrap_text_commands(source) do
    Enum.reduce(1..5, source, fn _, acc ->
      String.replace(
        acc,
        ~r/\\(?:textbf|emph|textit|texttt|mathbf|mathrm|mathcal|boldmath)\{([^{}]*)\}/,
        "\\1"
      )
    end)
  end

  defp capture(source, regex) do
    case Regex.run(regex, source) do
      [_, value | _] -> String.trim(value)
      _ -> ""
    end
  end

  defp ignorable_paragraph?(paragraph) do
    paragraph in ["", "maketitle", "begincenter", "endcenter"] or
      String.starts_with?(paragraph, "Provided proper attribution")
  end

  defp stable_block_id(prefix, text) do
    suffix = :erlang.phash2(text, 1_000_000) |> Integer.to_string()
    "#{prefix}-block-#{suffix}"
  end

  defp slug(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp blank_default("", default), do: default
  defp blank_default(value, _default), do: value
end
