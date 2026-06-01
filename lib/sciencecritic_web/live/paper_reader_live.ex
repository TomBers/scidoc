defmodule SciencecriticWeb.PaperReaderLive do
  use SciencecriticWeb, :live_view

  alias Sciencecritic.PaperQA
  alias Sciencecritic.PaperQA.Selection
  alias Sciencecritic.Papers.LatexParser

  @impl true
  def mount(_params, _session, socket) do
    paper_root =
      :sciencecritic
      |> :code.priv_dir()
      |> Path.join("static/papers/attention")

    compiled_path =
      Path.join(:code.priv_dir(:sciencecritic), "static/generated_papers/attention/ms.html")

    socket =
      case LatexParser.parse_directory(paper_root) do
        {:ok, paper} ->
          assign(socket,
            paper: paper,
            outline_groups: outline_groups(paper.sections),
            stats: paper_stats(paper),
            compiled_available?: File.exists?(compiled_path),
            parse_error: nil,
            saved_selections: PaperQA.list_paper_question_selections(paper.id),
            selected_selection: nil,
            selection_questions: [],
            question_form: to_form(%{"question" => ""}, as: :qa),
            follow_up_form: to_form(%{"question" => ""}, as: :follow_up),
            qa_error: nil
          )

        {:error, reason} ->
          assign(socket,
            paper: nil,
            outline_groups: [],
            stats: %{},
            compiled_available?: File.exists?(compiled_path),
            parse_error: inspect(reason),
            saved_selections: [],
            selected_selection: nil,
            selection_questions: [],
            question_form: to_form(%{"question" => ""}, as: :qa),
            follow_up_form: to_form(%{"question" => ""}, as: :follow_up),
            qa_error: nil
          )
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("paper_selection_captured", params, socket) do
    attrs = paper_selection_attrs(socket, params)

    case PaperQA.get_selection_by_attrs(attrs) do
      %Selection{} = selection ->
        {:noreply,
         socket
         |> assign(:selected_selection, selection)
         |> assign(:selection_questions, selection.questions)
         |> assign(:question_form, to_form(%{"question" => ""}, as: :qa))
         |> assign(:follow_up_form, to_form(%{"question" => ""}, as: :follow_up))
         |> assign(:qa_error, nil)}

      nil ->
        {:noreply,
         socket
         |> assign(:selected_selection, transient_selection(attrs))
         |> assign(:selection_questions, [])
         |> assign(:question_form, to_form(%{"question" => ""}, as: :qa))
         |> assign(:follow_up_form, to_form(%{"question" => ""}, as: :follow_up))
         |> assign(:qa_error, nil)}
    end
  end

  def handle_event("select_saved_selection", %{"id" => selection_id}, socket) do
    case Integer.parse(selection_id) do
      {selection_id, ""} ->
        case PaperQA.get_selection_with_questions(selection_id) do
          %Selection{} = selection ->
            {:noreply,
             socket
             |> assign(:selected_selection, selection)
             |> assign(:selection_questions, selection.questions)
             |> assign(:question_form, to_form(%{"question" => ""}, as: :qa))
             |> assign(:follow_up_form, to_form(%{"question" => ""}, as: :follow_up))
             |> assign(:qa_error, nil)}

          nil ->
            {:noreply, assign(socket, :qa_error, "That shared question is no longer available.")}
        end

      _ ->
        {:noreply, assign(socket, :qa_error, "Could not identify the saved question.")}
    end
  end

  def handle_event("ask_selection_question", %{"qa" => params}, socket) do
    question = params |> Map.get("question", "") |> String.trim()

    with question when question != "" <- question,
         {:ok, selection_or_attrs} <- selection_for_question(socket, params),
         {:ok, question_record} <- PaperQA.create_question(selection_or_attrs, question) do
      {:noreply, refresh_selection_questions(socket, question_record.paper_selection_id)}
    else
      {:error, :missing_selection} ->
        {:noreply, assign(socket, :qa_error, "Select a passage before asking a question.")}

      "" ->
        {:noreply, assign(socket, :qa_error, "Question cannot be blank.")}

      {:error, reason} ->
        {:noreply, assign(socket, :qa_error, "Could not answer question: #{inspect(reason)}")}
    end
  end

  def handle_event(
        "ask_follow_up_question",
        %{"follow_up" => %{"question" => question, "parent_question_id" => parent_question_id}},
        socket
      ) do
    with %Selection{id: selection_id} = selection when not is_nil(selection_id) <-
           socket.assigns.selected_selection,
         question when question != "" <- String.trim(question),
         {parent_question_id, ""} <- Integer.parse(parent_question_id),
         {:ok, _question} <-
           PaperQA.create_question(selection, question, parent_question_id: parent_question_id) do
      {:noreply, refresh_selection_questions(socket, selection_id)}
    else
      nil ->
        {:noreply, assign(socket, :qa_error, "Select a passage before asking a follow-up.")}

      %Selection{} ->
        {:noreply,
         assign(socket, :qa_error, "Ask an initial question before adding a follow-up.")}

      "" ->
        {:noreply, assign(socket, :qa_error, "Follow-up question cannot be blank.")}

      :error ->
        {:noreply, assign(socket, :qa_error, "Could not identify the parent question.")}

      {:error, reason} ->
        {:noreply, assign(socket, :qa_error, "Could not answer follow-up: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      main_class="px-3 py-4 sm:px-4 lg:px-6"
      content_class="mx-auto w-full max-w-[1440px]"
    >
      <section
        id="paper-reader"
        class="paper-reader-shell semantic-paper-demo"
        phx-hook="PaperReader"
        data-paper-annotations={annotation_json(@saved_selections)}
      >
        <%= if @parse_error do %>
          <div class="paper-reader-error">
            <p class="paper-reader-kicker">TeX parsing failed</p>
            <h1>Could not load the paper source.</h1>
            <p>{@parse_error}</p>
          </div>
        <% else %>
          <aside
            class="paper-reader-rail semantic-argument-panel"
            aria-label="Semantic paper workspace"
          >
            <section
              id="paper-workspace-ai"
              class="paper-ai-history-panel"
              aria-labelledby="context-heading"
            >
              <div class="paper-panel-toolbar">
                <div>
                  <p class="paper-reader-kicker">Public Q&A</p>
                  <h2 id="context-heading">Ask about a selection</h2>
                </div>
                <span>{saved_question_count(@saved_selections)} shared</span>
              </div>

              <section
                id="paper-workspace-selection"
                class="paper-selection-panel paper-primary-workflow"
                aria-label="Ask AI"
              >
                <p
                  class="paper-selection-empty"
                  data-paper-selection-empty
                  hidden={not is_nil(@selected_selection)}
                >
                  Select text in the paper to ask a grounded question. Answers are added to the shared demo history.
                </p>
                <div
                  class="paper-selection-result"
                  data-paper-selection-result
                  hidden={is_nil(@selected_selection)}
                >
                  <div class="paper-selection-summary" data-paper-capture-node>
                    <blockquote data-paper-selection-text>
                      {if @selected_selection, do: @selected_selection.selected_text, else: ""}
                    </blockquote>
                    <dl>
                      <div>
                        <dt>Section</dt>
                        <dd data-paper-selection-section>
                          {if @selected_selection,
                            do: section_label(@selected_selection.section_id),
                            else: "unknown section"}
                        </dd>
                      </div>
                      <div>
                        <dt>Block</dt>
                        <dd data-paper-selection-block>
                          {if @selected_selection,
                            do: @selected_selection.block_id,
                            else: "unknown block"}
                        </dd>
                      </div>
                    </dl>
                    <p class="paper-selection-meta" data-paper-selection-meta>
                      {selection_meta(@selected_selection)}
                    </p>
                    <span class="sr-only" data-paper-selection-term>
                      {if @selected_selection,
                        do: @selected_selection.selected_text,
                        else: "Selected passage"}
                    </span>
                  </div>

                  <.form
                    for={@question_form}
                    id="paper-selection-question-form"
                    phx-submit="ask_selection_question"
                    class="paper-question-form"
                  >
                    <input
                      type="hidden"
                      name="qa[selected_text]"
                      value={if @selected_selection, do: @selected_selection.selected_text, else: ""}
                      data-paper-selection-input="selected_text"
                    />
                    <input
                      type="hidden"
                      name="qa[section_id]"
                      value={if @selected_selection, do: @selected_selection.section_id, else: ""}
                      data-paper-selection-input="section_id"
                    />
                    <input
                      type="hidden"
                      name="qa[block_id]"
                      value={if @selected_selection, do: @selected_selection.block_id, else: ""}
                      data-paper-selection-input="block_id"
                    />
                    <.input
                      field={@question_form[:question]}
                      type="textarea"
                      rows="3"
                      label="Ask about this selection"
                      placeholder="What does this mean in the paper?"
                      class="paper-question-input"
                    />
                    <button type="submit" phx-disable-with="Asking...">
                      <.icon name="hero-paper-airplane" class="size-4" /> Ask and save
                    </button>
                  </.form>

                  <p :if={@qa_error} class="paper-question-error">{@qa_error}</p>
                </div>

                <span class="sr-only" data-paper-graph-source>
                  {if @selected_selection,
                    do: @selected_selection.section_id,
                    else: "Attention Is All You Need"}
                </span>
                <span class="sr-only" data-paper-graph-question>
                  {selection_question_prompt(@selected_selection)}
                </span>
              </section>

              <details
                id="paper-workspace-answers"
                class="paper-workspace-section paper-question-thread-section"
                open={@selection_questions != []}
              >
                <summary>
                  <span>Answers</span>
                  <small>{length(@selection_questions)} active</small>
                </summary>
                <div :if={@selection_questions != []} class="paper-question-thread">
                  <article
                    :for={question <- @selection_questions}
                    id={"paper-question-#{question.id}"}
                  >
                    <header>
                      <span>{question.status}</span>
                      <strong>Q</strong>
                    </header>
                    <p>{question.question}</p>
                    <div class={["paper-question-answer", question.status == "failed" && "is-error"]}>
                      {question.answer || question.error || "Waiting for an answer..."}
                    </div>
                    <.form
                      for={@follow_up_form}
                      id={"paper-follow-up-form-#{question.id}"}
                      phx-submit="ask_follow_up_question"
                      class="paper-follow-up-form"
                    >
                      <input type="hidden" name="follow_up[parent_question_id]" value={question.id} />
                      <.input
                        id={"paper-follow-up-question-#{question.id}"}
                        field={@follow_up_form[:question]}
                        type="text"
                        placeholder="Ask a follow-up"
                        class="paper-follow-up-input"
                      />
                      <button type="submit" aria-label="Ask follow-up" phx-disable-with="Asking...">
                        <.icon name="hero-arrow-right" class="size-4" />
                      </button>
                    </.form>
                  </article>
                </div>
                <p :if={@selection_questions == []} class="paper-selection-empty">
                  Answers and follow-up prompts appear here after you ask about a selection.
                </p>
              </details>

              <details
                id="paper-workspace-history"
                class="paper-workspace-section paper-saved-questions paper-secondary-workflow"
                open
              >
                <summary>
                  <span id="saved-questions-heading">Shared history</span>
                  <small>{saved_question_count(@saved_selections)} public</small>
                </summary>

                <p :if={saved_question_count(@saved_selections) == 0} class="paper-selection-empty">
                  Shared questions will appear here when readers ask about selected passages.
                </p>

                <div
                  :if={saved_question_count(@saved_selections) > 0}
                  class="paper-saved-question-list"
                >
                  <button
                    :for={selection <- @saved_selections}
                    :if={selection.questions != []}
                    type="button"
                    phx-click="select_saved_selection"
                    phx-value-id={selection.id}
                    data-paper-saved-selection-link
                    data-paper-selection-id={selection.id}
                    data-paper-selection-text={selection.selected_text}
                    data-paper-selection-section={selection.section_id}
                    data-paper-selection-block={selection.block_id}
                  >
                    <span>{section_label(selection.section_id)}</span>
                    <strong>{selection.selected_text}</strong>
                    <small>
                      {length(selection.questions)} question{if(length(selection.questions) == 1,
                        do: "",
                        else: "s"
                      )}
                    </small>
                  </button>
                </div>
              </details>
            </section>

            <details class="paper-workspace-section paper-panel-disclosure" open>
              <summary>
                <span>Document map</span>
                <small>{@stats.sections} sections</small>
              </summary>
              <div class="semantic-section-dropdowns" id="paper-section-navigator">
                <details
                  :for={{group, index} <- Enum.with_index(@outline_groups)}
                  class={[
                    "semantic-section-dropdown",
                    group.children == [] && "is-leaf"
                  ]}
                  open={index == 0}
                >
                  <summary>
                    <a
                      href={"#paper-section-#{group.section.id}"}
                      data-paper-nav-target={group.section.id}
                    >
                      <span>{group.section.number}</span>
                      {group.section.title}
                    </a>
                    <small>{block_count_label(outline_group_block_count(group))}</small>
                  </summary>
                  <ol :if={group.children != []}>
                    <li :for={child <- group.children}>
                      <a href={"#paper-section-#{child.id}"} data-paper-nav-target={child.id}>
                        <span>{child.number}</span>
                        {child.title}
                      </a>
                      <small>{block_count_label(length(child.blocks))}</small>
                    </li>
                  </ol>
                </details>
              </div>
            </details>

            <details
              id="paper-workspace-view"
              class="paper-workspace-section paper-view-controls"
              open
            >
              <summary>
                <span id="readability-heading">View</span>
                <small>Display</small>
              </summary>
              <div class="paper-reading-controls" aria-label="Reader display controls">
                <div class="paper-reading-control-group">
                  <span>Theme</span>
                  <div role="group" aria-label="Reader theme">
                    <button
                      type="button"
                      data-paper-style-control
                      data-paper-style-kind="theme"
                      data-paper-style-value="light"
                      aria-pressed="true"
                    >
                      <.icon name="hero-sun" class="size-4" /> Light
                    </button>
                    <button
                      type="button"
                      data-paper-style-control
                      data-paper-style-kind="theme"
                      data-paper-style-value="dark"
                      aria-pressed="false"
                    >
                      <.icon name="hero-moon" class="size-4" /> Dark
                    </button>
                  </div>
                </div>

                <div class="paper-reading-control-group">
                  <span>Text size</span>
                  <div role="group" aria-label="Reader font size">
                    <button
                      type="button"
                      data-paper-style-control
                      data-paper-style-kind="font"
                      data-paper-style-value="default"
                      aria-pressed="true"
                    >
                      A
                    </button>
                    <button
                      type="button"
                      data-paper-style-control
                      data-paper-style-kind="font"
                      data-paper-style-value="large"
                      aria-pressed="false"
                    >
                      A+
                    </button>
                  </div>
                </div>

                <div class="paper-reading-control-group">
                  <span>Spacing</span>
                  <div role="group" aria-label="Reader line spacing">
                    <button
                      type="button"
                      data-paper-style-control
                      data-paper-style-kind="spacing"
                      data-paper-style-value="compact"
                      aria-pressed="true"
                    >
                      Tight
                    </button>
                    <button
                      type="button"
                      data-paper-style-control
                      data-paper-style-kind="spacing"
                      data-paper-style-value="relaxed"
                      aria-pressed="false"
                    >
                      Open
                    </button>
                  </div>
                </div>
              </div>
            </details>

            <details class="paper-workspace-section paper-package-panel">
              <summary>
                <span>Package</span>
                <small>Export</small>
              </summary>
              <div class="paper-workspace-intro semantic-paper-header">
                <p class="paper-reader-kicker">Semantic scientific document demo</p>
                <h2>{@paper.title}</h2>
                <p>
                  A working argument that scientific papers should ship as semantic document graphs with high-quality renderings. The visible paper is generated by real TeX4ht; the workspace is backed by a simplified AST parsed from the same TeX source.
                </p>
                <div class="semantic-source-strip" aria-label="Document pipeline">
                  <span>TeX source</span>
                  <span>TeX4ht HTML</span>
                  <span>Semantic AST</span>
                  <span>Selectable clarification context</span>
                </div>
                <.link href={~p"/papers/attention/export"} class="paper-package-export-link">
                  <.icon name="hero-arrow-down-tray" class="size-4" /> Export package
                </.link>
              </div>
            </details>
          </aside>

          <article class="paper-document semantic-paper-document" data-paper-id={@paper.id}>
            <%= if @compiled_available? do %>
              <div
                id="paper-compiled-root"
                class="paper-compiled-root"
                data-paper-compiled-root
                data-paper-compiled-src={~p"/generated_papers/attention/ms.html"}
                phx-update="ignore"
              >
                <p class="paper-reader-status">Loading compiled paper HTML…</p>
              </div>
            <% else %>
              <div class="paper-reader-error">
                <p class="paper-reader-kicker">Compiled HTML missing</p>
                <h2>Run <code>mix papers.build attention</code> to generate the TeX4ht reader.</h2>
              </div>
              <.semantic_fallback paper={@paper} />
            <% end %>
          </article>
        <% end %>
      </section>
    </Layouts.app>
    """
  end

  attr :paper, :map, required: true

  defp semantic_fallback(assigns) do
    ~H"""
    <section id="paper-abstract" class="paper-section" data-paper-section-id="abstract">
      <h2>Abstract</h2>
      <%= for block <- @paper.abstract_blocks do %>
        <.paper_block block={block} />
      <% end %>
    </section>

    <%= for section <- @paper.sections do %>
      <section
        id={"paper-section-#{section.id}"}
        class={["paper-section", "paper-section-level-#{section.level}"]}
        data-paper-section-id={section.id}
      >
        <.paper_heading section={section} />
        <%= for block <- section.blocks do %>
          <.paper_block block={block} />
        <% end %>
      </section>
    <% end %>
    """
  end

  attr :section, :map, required: true

  defp paper_heading(assigns) do
    ~H"""
    <div class="paper-section-heading">
      <span>{@section.number}</span>
      <h2 :if={@section.level == 1}>{@section.title}</h2>
      <h3 :if={@section.level == 2}>{@section.title}</h3>
      <h4 :if={@section.level == 3}>{@section.title}</h4>
    </div>
    """
  end

  attr :block, :map, required: true

  defp paper_block(%{block: %{type: :paragraph}} = assigns) do
    ~H"""
    <p id={@block.id} class="paper-paragraph" data-paper-block-id={@block.id}>
      {@block.text}
    </p>
    """
  end

  defp paper_block(%{block: %{type: :equation}} = assigns) do
    ~H"""
    <figure id={@block.id} class="paper-equation" data-paper-block-id={@block.id}>
      <pre><code>{@block.text}</code></pre>
    </figure>
    """
  end

  defp paper_block(%{block: %{type: :figure}} = assigns) do
    ~H"""
    <figure id={@block.id} class="paper-figure" data-paper-block-id={@block.id}>
      <img :if={@block.image_src} src={@block.image_src} alt={@block.caption || "Paper figure"} />
      <figcaption :if={@block.caption != ""}>{@block.caption}</figcaption>
    </figure>
    """
  end

  defp paper_block(%{block: %{type: :table}} = assigns) do
    ~H"""
    <figure id={@block.id} class="paper-table" data-paper-block-id={@block.id}>
      <figcaption :if={@block.caption != ""}>{@block.caption}</figcaption>
      <table :if={Map.get(@block, :rows, []) != []}>
        <tbody>
          <tr :for={row <- @block.rows}>
            <td :for={cell <- row}>{cell}</td>
          </tr>
        </tbody>
      </table>
      <pre :if={Map.get(@block, :rows, []) == []}><code>{@block.text}</code></pre>
    </figure>
    """
  end

  defp paper_stats(paper) do
    blocks = paper.abstract_blocks ++ Enum.flat_map(paper.sections, & &1.blocks)

    %{
      sections: length(paper.sections),
      blocks: length(blocks),
      figures: count_blocks(blocks, :figure),
      tables: count_blocks(blocks, :table),
      equations: count_blocks(blocks, :equation)
    }
  end

  defp count_blocks(blocks, type) do
    Enum.count(blocks, &(&1.type == type))
  end

  defp outline_groups(sections) do
    sections
    |> Enum.reduce([], fn section, groups ->
      if section.level == 1 or groups == [] do
        groups ++ [%{section: section, children: []}]
      else
        List.update_at(groups, -1, fn group ->
          %{group | children: group.children ++ [section]}
        end)
      end
    end)
  end

  defp outline_group_block_count(group) do
    length(group.section.blocks) +
      (group.children
       |> Enum.map(&length(&1.blocks))
       |> Enum.sum())
  end

  defp block_count_label(1), do: "1 block"
  defp block_count_label(count), do: "#{count} blocks"

  defp refresh_selection_questions(socket, selection_id) do
    selection = PaperQA.get_selection_with_questions(selection_id)

    socket
    |> assign(:selected_selection, selection)
    |> assign(:selection_questions, selection.questions)
    |> assign(:saved_selections, PaperQA.list_paper_question_selections(socket.assigns.paper.id))
    |> assign(:question_form, to_form(%{"question" => ""}, as: :qa))
    |> assign(:follow_up_form, to_form(%{"question" => ""}, as: :follow_up))
    |> assign(:qa_error, nil)
  end

  defp selection_for_question(socket, params) do
    case socket.assigns.selected_selection do
      %Selection{id: id} = selection when not is_nil(id) ->
        {:ok, selection}

      %Selection{} = selection ->
        {:ok, selection_attrs_from_selection(selection)}

      _ ->
        attrs = paper_selection_attrs(socket, params)

        if attrs.selected_text == "" do
          {:error, :missing_selection}
        else
          {:ok, attrs}
        end
    end
  end

  defp paper_selection_attrs(socket, attrs) do
    PaperQA.selection_attrs(%{
      "paper_id" => socket.assigns.paper.id,
      "section_id" => attrs["section_id"],
      "block_id" => attrs["block_id"],
      "selected_text" => attrs["selected_text"]
    })
  end

  defp selection_attrs_from_selection(selection) do
    PaperQA.selection_attrs(%{
      paper_id: selection.paper_id,
      section_id: selection.section_id,
      block_id: selection.block_id,
      selected_text: selection.selected_text
    })
  end

  defp transient_selection(attrs) do
    %Selection{
      paper_id: attrs.paper_id,
      section_id: attrs.section_id,
      block_id: attrs.block_id,
      selected_text: attrs.selected_text,
      text_hash: attrs.text_hash
    }
  end

  defp saved_question_count(selections) do
    selections
    |> Enum.flat_map(& &1.questions)
    |> length()
  end

  defp selection_meta(nil), do: ""

  defp selection_meta(selection) do
    "#{section_label(selection.section_id)} · #{selection.block_id} · #{String.length(selection.selected_text)} characters selected"
  end

  defp section_label(nil), do: "Unknown section"
  defp section_label(""), do: "Unknown section"
  defp section_label("compiled-tex4ht"), do: "Compiled HTML"

  defp section_label(section_id) do
    section_id
    |> String.replace("-", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp selection_question_prompt(nil), do: "What does this term mean here?"

  defp selection_question_prompt(selection) do
    "What does “#{truncate_text(selection.selected_text, 54)}” mean here?"
  end

  defp truncate_text(value, max_length) do
    if String.length(value) <= max_length do
      value
    else
      "#{String.slice(value, 0, max_length - 1)}…"
    end
  end

  defp annotation_json(selections) do
    selections
    |> Enum.filter(&(&1.questions != []))
    |> Enum.map(fn selection ->
      %{
        id: selection.id,
        selected_text: selection.selected_text,
        section_id: selection.section_id,
        block_id: selection.block_id,
        question_count: length(selection.questions)
      }
    end)
    |> Jason.encode!()
  end
end
