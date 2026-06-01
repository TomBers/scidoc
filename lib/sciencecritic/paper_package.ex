defmodule Sciencecritic.PaperPackage do
  @moduledoc """
  Builds portable paper package exports from the semantic paper and captured work.
  """

  alias Sciencecritic.PaperQA
  alias Sciencecritic.Papers.LatexParser

  @attention_id "attention-is-all-you-need"

  def attention_archive do
    entries =
      attention_package_files()
      |> Enum.map(fn {path, content} -> {String.to_charlist(path), content} end)

    {:ok, {_name, archive}} = :zip.create(~c"attention.scidoc.zip", entries, [:memory])
    archive
  end

  def attention_package_files do
    context = attention_context()

    [
      {"paper.scidoc/document.json", json(document_json(context.paper))},
      {"paper.scidoc/render.html", File.read!(context.render_html_path)},
      {"paper.scidoc/render.pdf", File.read!(context.render_pdf_path)},
      {"paper.scidoc/bibliography.json", json(bibliography_json())},
      {"paper.scidoc/mappings/pdf-locations.json", json(render_mappings_json(context.paper))},
      {"paper.scidoc/annotations/llm-questions.json",
       json(llm_questions_json(context.selections))}
    ] ++ asset_files(context.assets_root)
  end

  def attention_export do
    context = attention_context()

    document_json(context.paper)
    |> Map.put("annotations", %{
      "llm_questions" => Enum.map(context.selections, &selection_summary/1)
    })
  end

  defp attention_context do
    static_root = Path.join(:code.priv_dir(:sciencecritic), "static")
    paper_root = Path.join(static_root, "papers/attention")
    {:ok, paper} = LatexParser.parse_directory(paper_root)

    %{
      paper: paper,
      selections: PaperQA.list_paper_question_selections(@attention_id),
      render_html_path: Path.join(static_root, "generated_papers/attention/ms.html"),
      render_pdf_path: Path.join(static_root, "pdfs/attention.pdf"),
      assets_root: Path.join(static_root, "generated_papers/attention")
    }
  end

  defp document_json(paper) do
    %{
      "format" => "sciencecritic.scidoc.package",
      "version" => 1,
      "exported_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      "manifest" => %{
        "root" => "paper.scidoc/",
        "files" => [
          "document.json",
          "render.html",
          "render.pdf",
          "assets/",
          "bibliography.json",
          "mappings/render-locations.json",
          "annotations/llm-questions.json"
        ]
      },
      "paper" => paper_summary(paper),
      "renderings" => %{
        "html" => "render.html",
        "pdf" => "render.pdf",
        "source" => "assets/source/ms.tex"
      },
      "semantic_graph" => %{
        "sections" => Enum.map(paper.sections, &section_summary/1),
        "abstract_blocks" => Enum.map(paper.abstract_blocks, &block_summary/1)
      },
      "annotations" => %{
        "llm_questions" => "annotations/llm-questions.json"
      }
    }
  end

  defp llm_questions_json(selections) do
    %{
      "format" => "sciencecritic.scidoc.llm_questions",
      "version" => 1,
      "paper_id" => @attention_id,
      "selections" => Enum.map(selections, &selection_summary/1)
    }
  end

  defp bibliography_json do
    %{
      "format" => "sciencecritic.scidoc.bibliography",
      "version" => 1,
      "references" => []
    }
  end

  defp render_mappings_json(paper) do
    %{
      "format" => "sciencecritic.scidoc.render_mappings",
      "version" => 1,
      "rendering" => "render.html",
      "sections" =>
        Enum.map(paper.sections, fn section ->
          %{
            "section_id" => section.id,
            "html_anchor" => "paper-section-#{section.id}",
            "blocks" =>
              Enum.map(section.blocks, fn block ->
                %{
                  "block_id" => block.id,
                  "html_anchor" => block.id
                }
              end)
          }
        end)
    }
  end

  defp paper_summary(paper) do
    blocks = paper.abstract_blocks ++ Enum.flat_map(paper.sections, & &1.blocks)

    %{
      "id" => paper.id,
      "title" => paper.title,
      "counts" => %{
        "abstract_blocks" => length(paper.abstract_blocks),
        "sections" => length(paper.sections),
        "blocks" => length(blocks),
        "figures" => count_blocks(blocks, :figure),
        "tables" => count_blocks(blocks, :table),
        "equations" => count_blocks(blocks, :equation)
      }
    }
  end

  defp section_summary(section) do
    %{
      "id" => section.id,
      "number" => section.number,
      "level" => section.level,
      "title" => section.title,
      "blocks" => Enum.map(section.blocks, &block_summary/1)
    }
  end

  defp block_summary(block) do
    %{
      "id" => block.id,
      "type" => Atom.to_string(block.type),
      "text" => Map.get(block, :text),
      "caption" => Map.get(block, :caption),
      "image_src" => Map.get(block, :image_src)
    }
  end

  defp selection_summary(selection) do
    %{
      "id" => selection.id,
      "paper_id" => selection.paper_id,
      "section_id" => selection.section_id,
      "block_id" => selection.block_id,
      "selected_text" => selection.selected_text,
      "text_hash" => selection.text_hash,
      "captured_at" => iso8601(selection.inserted_at),
      "questions" => Enum.map(selection.questions, &question_summary/1)
    }
  end

  defp question_summary(question) do
    %{
      "id" => question.id,
      "parent_question_id" => question.parent_question_id,
      "question" => question.question,
      "answer" => question.answer,
      "status" => question.status,
      "error" => question.error,
      "prompt_payload" => question.prompt_payload,
      "asked_at" => iso8601(question.inserted_at),
      "updated_at" => iso8601(question.updated_at)
    }
  end

  defp count_blocks(blocks, type) do
    Enum.count(blocks, &(&1.type == type))
  end

  defp asset_files(assets_root) do
    assets_root
    |> File.ls!()
    |> Enum.reject(&(&1 in ["ms.html", "ms2.html", "ms3.html"]))
    |> Enum.flat_map(fn filename ->
      path = Path.join(assets_root, filename)

      if File.regular?(path) do
        [{"paper.scidoc/assets/#{filename}", File.read!(path)}]
      else
        []
      end
    end)
  end

  defp json(data), do: Jason.encode!(data, pretty: true)

  defp iso8601(nil), do: nil
  defp iso8601(datetime), do: DateTime.to_iso8601(datetime)
end
