defmodule Sciencecritic.PaperQA.QuestionAnswerer do
  @moduledoc """
  Answers grounded paper-selection questions.

  The LLM path uses ReqLLM with OpenAI. Without `OPENAI_API_KEY`, the module
  returns a deterministic local answer so the PoC remains usable in dev and
  test environments.
  """

  alias Sciencecritic.PaperQA.Selection

  @default_model "openai:gpt-5-mini"

  def answer(%Selection{} = selection, question, previous_questions \\ []) do
    prompt = prompt(selection, question, previous_questions)

    if llm_available?() do
      request_llm(prompt)
    else
      {:ok, fallback_answer(selection, question, previous_questions), prompt}
    end
  end

  def fallback_answer_for_test(selection, question, previous_questions \\ []) do
    fallback_answer(selection, question, previous_questions)
  end

  defp request_llm(prompt) do
    case ReqLLM.generate_text(llm_model(), prompt,
           system_prompt:
             "You answer questions about scientific papers. Ground every answer in the selected source text and its document location. Be concise, explicit, and useful for building a reusable knowledge graph.",
           temperature: 0.2,
           reasoning_effort: :minimal,
           max_tokens: 700
         ) do
      {:ok, response} ->
        {:ok, ReqLLM.Response.text(response) |> to_string() |> String.trim(), prompt}

      {:error, reason} ->
        {:error, inspect(reason), prompt}
    end
  rescue
    exception ->
      {:error, Exception.message(exception), prompt}
  end

  defp llm_available? do
    not Application.get_env(:sciencecritic, :paper_qa_disable_llm, false) and
      openai_api_key_configured?()
  end

  defp openai_api_key_configured? do
    case System.get_env("OPENAI_API_KEY") || ReqLLM.get_key("OPENAI_API_KEY") do
      key when is_binary(key) -> String.trim(key) != ""
      _ -> false
    end
  end

  defp llm_model do
    System.get_env("PAPER_QA_LLM_MODEL") ||
      Application.get_env(:sciencecritic, :paper_qa_llm_model) ||
      @default_model
  end

  defp fallback_answer(selection, question, previous_questions) do
    thread_note =
      if previous_questions == [] do
        ""
      else
        " This continues a thread with #{length(previous_questions)} previous question(s)."
      end

    """
    Local fallback answer: "#{selection.selected_text}" appears in section `#{selection.section_id}` and block `#{selection.block_id}`. The question being asked is: "#{question}".#{thread_note}

    Set `OPENAI_API_KEY` to replace this with a grounded LLM answer. The default test model is `#{@default_model}`.

    Useful follow-up: What role does this selected passage play in the paper's argument?
    """
  end

  defp prompt(selection, question, previous_questions) do
    previous =
      previous_questions
      |> Enum.map(fn question ->
        """
        Q: #{question.question}
        A: #{question.answer || "(not answered)"}
        """
      end)
      |> Enum.join("\n")

    """
    A reader selected this text from a scientific paper:

    ```text
    #{selection.selected_text}
    ```

    Paper ID: #{selection.paper_id}
    Section ID: #{selection.section_id}
    Block ID: #{selection.block_id}

    #{if previous == "", do: "", else: "Previous thread:\n#{previous}"}

    Reader question:
    #{question}

    Answer in 2-4 short paragraphs. Explain the selected term or passage in this paper's context, then add one useful follow-up question the reader could ask next.
    """
  end
end
