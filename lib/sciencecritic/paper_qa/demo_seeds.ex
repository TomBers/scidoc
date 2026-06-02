defmodule Sciencecritic.PaperQA.DemoSeeds do
  @moduledoc """
  Idempotent demo seed data for the Attention paper.

  These examples are hand-authored instead of generated at boot so the public
  demo has useful persisted questions even when the SQLite database is ephemeral,
  and even when no LLM API key is configured.
  """

  import Ecto.Query

  alias Sciencecritic.PaperQA
  alias Sciencecritic.PaperQA.Question
  alias Sciencecritic.PaperQA.Selection
  alias Sciencecritic.Repo

  @paper_id "attention-is-all-you-need"

  @examples [
    %{
      section_id: "abstract",
      block_id: "abstract-block-565703",
      selected_text:
        "the Transformer, based solely on attention mechanisms, dispensing with recurrence and convolutions entirely",
      question:
        "What is the key conceptual jump in replacing recurrence and convolutions with attention?",
      answer:
        "The key jump is that the model no longer processes tokens mainly by stepping through a sequence or sliding local filters over it. Instead, each token can directly compare itself with every other token and gather information according to learned attention weights. This makes long-range interaction shorter and training more parallel, but it also means the model must add positional information separately because attention alone is permutation-insensitive."
    },
    %{
      section_id: "introduction",
      block_id: "introduction-block-991620",
      selected_text:
        "This inherently sequential nature precludes parallelization within training examples",
      question: "Why is sequential computation such a bottleneck for training sequence models?",
      answer:
        "If each hidden state depends on the previous hidden state, the model cannot compute all positions at the same time during training. That limits how effectively GPUs and TPUs can be used, especially on long sequences. The Transformer reduces this bottleneck because self-attention and feed-forward layers can process all positions in a layer largely in parallel."
    },
    %{
      section_id: "model-architecture",
      block_id: "model-architecture-block-628174",
      selected_text: "the encoder maps an input sequence of symbol representations",
      question: "What does it mean for the encoder to map symbols to continuous representations?",
      answer:
        "The input tokens start as discrete symbols such as word pieces. The encoder turns each token into a vector that captures contextual information from the surrounding sequence. By the end of the encoder stack, each vector is no longer just a token embedding; it is a learned representation of that token in context."
    },
    %{
      section_id: "scaled-dot-product-attention",
      block_id: "scaled-dot-product-attention-block-818939",
      selected_text: "We compute the dot products of the query with all keys, divide each by",
      question: "Why divide by sqrt(d_k) in scaled dot-product attention?",
      answer:
        "As the key/query dimension grows, raw dot products tend to have larger variance. Large dot products push the softmax into very peaked regions where gradients can become tiny. Dividing by sqrt(d_k) keeps the logits in a more stable range, making optimization easier while preserving the relative similarity signal."
    },
    %{
      section_id: "multi-head-attention",
      block_id: "multi-head-attention-block-476228",
      selected_text:
        "Multi-head attention allows the model to jointly attend to information from different representation subspaces at different positions.",
      question: "What are representation subspaces, and why do multiple heads help?",
      answer:
        "Each attention head learns different projections of queries, keys, and values. You can think of these projections as different views of the same tokens. One head might learn syntactic relationships, another might track coreference, and another might focus on local phrase structure. Multiple heads let the model combine several relationship patterns instead of compressing everything into one attention distribution."
    },
    %{
      section_id: "positional-encoding",
      block_id: "positional-encoding-block-257309",
      selected_text:
        "Since our model contains no recurrence and no convolution, in order for the model to make use of the order of the sequence, we must inject some information about the relative or absolute position of the tokens",
      question: "Why does the Transformer need positional encoding?",
      answer:
        "Self-attention compares tokens without inherently knowing their order. If token vectors were passed to attention with no positional signal, the model would see a bag of tokens rather than a sequence. Positional encodings add information about where each token occurs so attention can learn order-sensitive patterns such as adjacency, direction, and distance."
    },
    %{
      section_id: "why-self-attention",
      block_id: "why-self-attention-block-764195",
      selected_text:
        "The shorter these paths between any combination of positions in the input and output sequences, the easier it is to learn long-range dependencies",
      question: "What is path length, and why does it matter for long-range dependencies?",
      answer:
        "Path length is the number of computational steps information must traverse for one position to influence another. In recurrent networks, distant tokens may interact only through many sequential steps. In self-attention, any token can attend directly to any other token in a single layer, shortening the path and making long-range relationships easier to represent and optimize."
    },
    %{
      section_id: "regularization",
      block_id: "regularization-block-726822",
      selected_text: "During training, we employed label smoothing of value",
      question: "What does label smoothing do here?",
      answer:
        "Label smoothing prevents the model from becoming overly confident that the single observed target token has probability 1. Instead, a small amount of probability mass is spread to other labels. This can improve generalization and calibration, though the paper notes it may increase perplexity while improving BLEU."
    },
    %{
      section_id: "machine-translation",
      block_id: "machine-translation-block-957929",
      selected_text:
        "The Transformer achieves better BLEU scores than previous state-of-the-art models",
      question: "What should a reader understand about BLEU in this result?",
      answer:
        "BLEU is an automatic translation metric based on n-gram overlap with reference translations. It is useful for broad comparison but not a perfect measure of translation quality. The important claim is not only that the Transformer improved BLEU, but that it did so with much lower training cost and greater parallelism than prior architectures."
    },
    %{
      section_id: "english-constituency-parsing",
      block_id: "english-constituency-parsing-block-570126",
      selected_text:
        "To evaluate if the Transformer can generalize to other tasks we performed experiments on English constituency parsing.",
      question: "Why include constituency parsing in a machine translation paper?",
      answer:
        "The parsing experiment tests whether the architecture is more generally useful than a translation-specific trick. Constituency parsing has different output constraints and longer structured outputs. Strong results there suggest that self-attention can serve as a general sequence transduction architecture, not only a machine translation model."
    }
  ]

  def seed do
    Enum.reduce(@examples, %{questions: 0}, fn example, acc ->
      {:ok, selection} = PaperQA.get_or_create_selection(selection_attrs(example))
      {_question, inserted?} = get_or_insert_question(selection, example)

      %{questions: acc.questions + if(inserted?, do: 1, else: 0)}
    end)
  end

  def examples, do: @examples

  defp selection_attrs(example) do
    %{
      paper_id: @paper_id,
      section_id: example.section_id,
      block_id: example.block_id,
      selected_text: example.selected_text
    }
  end

  defp get_or_insert_question(%Selection{} = selection, example) do
    existing =
      Question
      |> where(
        [question],
        question.paper_selection_id == ^selection.id and
          is_nil(question.parent_question_id) and question.question == ^example.question
      )
      |> Repo.one()

    if existing do
      {existing, false}
    else
      {:ok, question} =
        %Question{}
        |> Question.changeset(%{
          paper_selection_id: selection.id,
          question: example.question,
          answer: example.answer,
          status: "answered",
          prompt_payload: demo_prompt_payload(example)
        })
        |> Repo.insert()

      {question, true}
    end
  end

  defp demo_prompt_payload(example) do
    Jason.encode!(%{
      source: "demo_seed",
      paper_id: @paper_id,
      section_id: example.section_id,
      block_id: example.block_id,
      selected_text: example.selected_text,
      question: example.question
    })
  end
end
