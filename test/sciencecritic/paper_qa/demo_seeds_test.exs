defmodule Sciencecritic.PaperQA.DemoSeedsTest do
  use Sciencecritic.DataCase, async: false

  alias Sciencecritic.PaperQA
  alias Sciencecritic.PaperQA.DemoSeeds

  test "seeds useful demo questions for the Attention paper idempotently" do
    first_result = DemoSeeds.seed()
    second_result = DemoSeeds.seed()

    selections = PaperQA.list_paper_question_selections("attention-is-all-you-need")

    assert first_result.questions == length(DemoSeeds.examples())
    assert second_result.questions == 0
    assert length(selections) == length(DemoSeeds.examples())

    seeded_text = Enum.map(selections, & &1.selected_text)
    assert Enum.any?(seeded_text, &String.contains?(&1, "attention mechanisms"))
    assert Enum.any?(seeded_text, &String.contains?(&1, "recurrence"))

    seeded_questions = selections |> Enum.flat_map(& &1.questions) |> Enum.map(& &1.question)
    assert "Why divide by sqrt(d_k) in scaled dot-product attention?" in seeded_questions

    assert "What are representation subspaces, and why do multiple heads help?" in seeded_questions

    assert Enum.all?(Enum.flat_map(selections, & &1.questions), &(&1.status == "answered"))
  end
end
