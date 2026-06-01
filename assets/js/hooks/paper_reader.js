const PaperReader = {
  mounted() {
    this.compiledShadowRoot = null;
    this.lastSelectionSignature = null;
    this.handleSelectionChange = () =>
      this.captureSelection(this.activeSelectionDocument(), { commit: false });
    this.handleSelectionEnd = () =>
      window.setTimeout(
        () =>
          this.captureSelection(this.activeSelectionDocument(), {
            commit: true,
          }),
        0,
      );
    this.handleClick = (event) => this.handleReaderClick(event);

    document.addEventListener("selectionchange", this.handleSelectionChange);
    this.el.addEventListener("mouseup", this.handleSelectionEnd);
    this.el.addEventListener("keyup", this.handleSelectionEnd);
    this.el.addEventListener("click", this.handleClick);

    this.renderCompiledPaperIfPresent();
  },

  updated() {
    this.decorateSavedAnnotations();
  },

  destroyed() {
    document.removeEventListener("selectionchange", this.handleSelectionChange);
    this.el.removeEventListener("mouseup", this.handleSelectionEnd);
    this.el.removeEventListener("keyup", this.handleSelectionEnd);
    this.el.removeEventListener("click", this.handleClick);
  },

  activeSelectionDocument() {
    const shadowSelection = this.compiledShadowRoot?.getSelection?.();

    if (
      shadowSelection &&
      shadowSelection.rangeCount > 0 &&
      (shadowSelection.toString().trim() || "") !== ""
    ) {
      return this.compiledShadowRoot;
    }

    return document;
  },

  async renderCompiledPaperIfPresent() {
    const root = this.el.querySelector("[data-paper-compiled-root]");
    if (!root || root.dataset.compiledRendered === "true") return;

    root.dataset.compiledRendered = "true";
    const src = root.dataset.paperCompiledSrc;

    try {
      const response = await fetch(src);
      if (!response.ok)
        throw new Error(
          `Compiled paper request failed with ${response.status}`,
        );

      const html = await response.text();
      const parser = new DOMParser();
      const doc = parser.parseFromString(html, "text/html");
      const baseUrl = new URL(src, window.location.href);
      const shadow = root.attachShadow({ mode: "open" });
      this.compiledShadowRoot = shadow;

      const style = document.createElement("style");
      style.textContent = await this.compiledPaperCss(doc, baseUrl);

      const wrapper = document.createElement("article");
      wrapper.className = "compiled-paper-document";
      wrapper.dataset.paperSectionId = "compiled-tex4ht";
      this.rewriteCompiledUrls(doc, baseUrl);
      wrapper.append(
        ...Array.from(doc.body.childNodes).map((node) =>
          document.importNode(node, true),
        ),
      );
      this.moveLeadingFloatsAfterIntroParagraph(wrapper);
      this.decorateCompiledRoot(wrapper);
      this.decorateCompiledSectionAnchors(wrapper);
      this.decorateCompiledBlockSections(wrapper);

      shadow.replaceChildren(style, wrapper);
      this.applyReaderStyle();
      this.decorateSavedAnnotations();
    } catch (error) {
      root.innerHTML = `
        <div class="paper-reader-load-error" role="alert">
          <p class="paper-reader-kicker">Compiled HTML failed</p>
          <h2>Could not load the compiled TeX4ht reader.</h2>
          <pre></pre>
        </div>
      `;
      root.querySelector("pre").textContent = error?.message || String(error);
      console.error("Compiled paper render failed", error);
    }
  },

  async compiledPaperCss(doc, baseUrl) {
    const href = doc
      .querySelector("link[rel='stylesheet']")
      ?.getAttribute("href");
    let css = "";

    if (href) {
      const cssUrl = new URL(href, baseUrl);
      const response = await fetch(cssUrl);
      if (response.ok) css = await response.text();
    }

    return `
      :host {
        display: block;
        color-scheme: light;
      }

      .compiled-paper-document {
        box-sizing: border-box;
        border: 1px solid rgba(15, 23, 42, 0.1);
        border-radius: 1rem;
        background: #ffffff;
      }

      [data-paper-section-id] {
        scroll-margin-top: 1rem;
      }

      .paper-term-question-link {
        border: 0;
        border-radius: 0.28rem;
        padding: 0.04rem 0.18rem;
        color: #1d4ed8;
        font: inherit;
        font-weight: 700;
        background: #dbeafe;
        box-shadow: inset 0 -1px 0 rgba(37, 99, 235, 0.26);
        cursor: pointer;
        transition:
          background 160ms ease,
          color 160ms ease,
          box-shadow 160ms ease;
      }

      .paper-term-question-link:hover,
      .paper-term-question-link.is-active {
        color: #ffffff;
        background: #2563eb;
        box-shadow: 0 0 0 3px rgba(37, 99, 235, 0.18);
      }

      ${css}

      .compiled-paper-document > .center:first-child {
        display: none !important;
      }

      .compiled-paper-document {
        max-width: 100%;
        overflow-wrap: anywhere;
      }

      .compiled-paper-document div.author,
      .compiled-paper-document div.thanks {
        white-space: normal !important;
        overflow-wrap: anywhere;
      }

      .compiled-paper-document table,
      .compiled-paper-document div.tabular,
      .compiled-paper-document table.align,
      .compiled-paper-document table.align-star,
      .compiled-paper-document table.equation,
      .compiled-paper-document table.equation-star {
        max-width: 100% !important;
      }

      .compiled-paper-document img {
        max-width: 100%;
        height: auto;
      }

      :host([data-reader-font="large"]) .compiled-paper-document {
        font-size: 118%;
      }

      :host([data-reader-spacing="relaxed"]) .compiled-paper-document p,
      :host([data-reader-spacing="relaxed"]) .compiled-paper-document li,
      :host([data-reader-spacing="relaxed"]) .compiled-paper-document blockquote {
        line-height: 1.9 !important;
      }

      :host([data-reader-spacing="relaxed"]) .compiled-paper-document p {
        margin-top: 1.05rem !important;
        margin-bottom: 1.05rem !important;
      }

      :host([data-reader-theme="dark"]) .compiled-paper-document {
        color-scheme: dark !important;
        color: #e7edf5 !important;
        background: #11151c !important;
        border-color: rgba(203, 213, 225, 0.18) !important;
      }

      :host([data-reader-theme="dark"]) .compiled-paper-document,
      :host([data-reader-theme="dark"]) .compiled-paper-document body,
      :host([data-reader-theme="dark"]) .compiled-paper-document p,
      :host([data-reader-theme="dark"]) .compiled-paper-document div,
      :host([data-reader-theme="dark"]) .compiled-paper-document li,
      :host([data-reader-theme="dark"]) .compiled-paper-document td,
      :host([data-reader-theme="dark"]) .compiled-paper-document th,
      :host([data-reader-theme="dark"]) .compiled-paper-document span {
        color: #e7edf5 !important;
        border-color: rgba(203, 213, 225, 0.22) !important;
      }

      :host([data-reader-theme="dark"]) .compiled-paper-document a {
        color: #8ec5ff !important;
      }

      :host([data-reader-theme="dark"]) .compiled-paper-document h1,
      :host([data-reader-theme="dark"]) .compiled-paper-document h2,
      :host([data-reader-theme="dark"]) .compiled-paper-document h3,
      :host([data-reader-theme="dark"]) .compiled-paper-document h4,
      :host([data-reader-theme="dark"]) .compiled-paper-document h5,
      :host([data-reader-theme="dark"]) .compiled-paper-document .titleHead,
      :host([data-reader-theme="dark"]) .compiled-paper-document .sectionHead,
      :host([data-reader-theme="dark"]) .compiled-paper-document .subsectionHead,
      :host([data-reader-theme="dark"]) .compiled-paper-document .subsubsectionHead {
        color: #ffffff !important;
        text-shadow: 0 1px 0 rgba(0, 0, 0, 0.3);
      }

      :host([data-reader-theme="dark"]) .compiled-paper-document div.abstract {
        border-color: rgba(203, 213, 225, 0.16) !important;
        background: #171d26 !important;
      }

      :host([data-reader-theme="dark"]) .compiled-paper-document div.figure,
      :host([data-reader-theme="dark"]) .compiled-paper-document figure,
      :host([data-reader-theme="dark"]) .compiled-paper-document div.float,
      :host([data-reader-theme="dark"]) .compiled-paper-document figure.float,
      :host([data-reader-theme="dark"]) .compiled-paper-document table,
      :host([data-reader-theme="dark"]) .compiled-paper-document table.tabular,
      :host([data-reader-theme="dark"]) .compiled-paper-document div.tabular {
        border-color: rgba(203, 213, 225, 0.2) !important;
        background: #f8fafc !important;
      }

      :host([data-reader-theme="dark"]) .compiled-paper-document div.figure *,
      :host([data-reader-theme="dark"]) .compiled-paper-document figure *,
      :host([data-reader-theme="dark"]) .compiled-paper-document div.float *,
      :host([data-reader-theme="dark"]) .compiled-paper-document figure.float *,
      :host([data-reader-theme="dark"]) .compiled-paper-document table *,
      :host([data-reader-theme="dark"]) .compiled-paper-document table.tabular *,
      :host([data-reader-theme="dark"]) .compiled-paper-document div.tabular * {
        color: #172033 !important;
        border-color: rgba(15, 23, 42, 0.12) !important;
      }

      :host([data-reader-theme="dark"]) .compiled-paper-document table.equation,
      :host([data-reader-theme="dark"]) .compiled-paper-document table.equation-star,
      :host([data-reader-theme="dark"]) .compiled-paper-document table.align,
      :host([data-reader-theme="dark"]) .compiled-paper-document table.align-star,
      :host([data-reader-theme="dark"]) .compiled-paper-document div.math-display,
      :host([data-reader-theme="dark"]) .compiled-paper-document div.par-math-display {
        border-radius: 0.75rem;
        background: #f8fafc !important;
        box-shadow: inset 0 0 0 1px rgba(148, 163, 184, 0.22);
      }

      :host([data-reader-theme="dark"]) .compiled-paper-document table.equation,
      :host([data-reader-theme="dark"]) .compiled-paper-document table.equation-star,
      :host([data-reader-theme="dark"]) .compiled-paper-document table.align,
      :host([data-reader-theme="dark"]) .compiled-paper-document table.align-star {
        margin-top: 1rem;
        margin-bottom: 1rem;
        padding: 0.55rem;
      }

      :host([data-reader-theme="dark"]) .compiled-paper-document table.equation *,
      :host([data-reader-theme="dark"]) .compiled-paper-document table.equation-star *,
      :host([data-reader-theme="dark"]) .compiled-paper-document table.align *,
      :host([data-reader-theme="dark"]) .compiled-paper-document table.align-star * {
        color: #172033 !important;
        border-color: rgba(15, 23, 42, 0.24) !important;
      }

      :host([data-reader-theme="dark"]) .compiled-paper-document img {
        filter: none !important;
      }

      :host([data-reader-theme="dark"]) .paper-term-question-link {
        color: #e0f2fe !important;
        background: rgba(14, 116, 144, 0.9);
        box-shadow: inset 0 -1px 0 rgba(224, 242, 254, 0.28);
      }

      :host([data-reader-theme="dark"]) .paper-term-question-link:hover,
      :host([data-reader-theme="dark"]) .paper-term-question-link.is-active {
        color: #082f49 !important;
        background: #bae6fd;
        box-shadow: 0 0 0 3px rgba(186, 230, 253, 0.2);
      }
    `;
  },

  rewriteCompiledUrls(doc, baseUrl) {
    for (const element of doc.querySelectorAll(
      "img[src], link[href], a[href]",
    )) {
      const attr = element.hasAttribute("src") ? "src" : "href";
      const value = element.getAttribute(attr);
      if (
        !value ||
        value.startsWith("#") ||
        value.startsWith("http") ||
        value.startsWith("data:")
      )
        continue;
      element.setAttribute(attr, new URL(value, baseUrl).pathname);
    }
  },

  moveLeadingFloatsAfterIntroParagraph(root) {
    const headings = root.querySelectorAll(
      "h2, h3, h4, h5, h6, .sectionHead, .subsectionHead, .subsubsectionHead",
    );

    for (const heading of headings) {
      const leadingFloats = [];
      let cursor = nextElementSibling(heading);

      while (cursor && isCompiledFloat(cursor)) {
        leadingFloats.push(cursor);
        cursor = nextElementSibling(cursor);
      }

      if (leadingFloats.length === 0 || !cursor || !isParagraphLike(cursor))
        continue;

      for (const float of leadingFloats) {
        cursor.after(float);
        cursor = float;
      }
    }
  },

  decorateCompiledRoot(root) {
    for (const [index, block] of Array.from(
      root.querySelectorAll(
        "p, figure, table, blockquote, pre, div, h1, h2, h3, h4",
      ),
    ).entries()) {
      if (
        !block.dataset.paperBlockId &&
        (block.textContent || "").trim().length > 0
      ) {
        block.dataset.paperBlockId = `compiled-block-${index + 1}`;
      }
    }
  },

  decorateCompiledSectionAnchors(root) {
    const headings = root.querySelectorAll(
      ".sectionHead, .subsectionHead, .subsubsectionHead, .likesectionHead, h2, h3, h4, h5",
    );

    for (const heading of headings) {
      const title = headingTitle(heading);
      const slug = slugify(title);

      if (!slug) continue;

      heading.dataset.paperSectionId = slug;
      if (!heading.id) heading.id = slug;
    }
  },

  decorateCompiledBlockSections(root) {
    const headingSelector =
      ".sectionHead, .subsectionHead, .subsubsectionHead, .likesectionHead, h2, h3, h4, h5";
    let currentSectionId = root.dataset.paperSectionId || "compiled-tex4ht";

    for (const element of root.querySelectorAll(
      `[data-paper-block-id], ${headingSelector}`,
    )) {
      if (element.matches(headingSelector) && element.dataset.paperSectionId) {
        currentSectionId = element.dataset.paperSectionId;
      }

      if (element.dataset.paperBlockId) {
        element.dataset.paperSectionId = element.dataset.paperSectionId || currentSectionId;
      }
    }
  },

  navigateToPaperSection(event) {
    const link = event.target.closest("[data-paper-nav-target]");
    if (!link || !this.el.contains(link)) return;

    const sectionId = link.dataset.paperNavTarget;
    if (!sectionId) return;

    const target =
      this.findCompiledSection(sectionId) ||
      document.getElementById(`paper-section-${sectionId}`) ||
      document.getElementById(sectionId);

    if (!target) return;

    event.preventDefault();

    target.scrollIntoView({ behavior: "smooth", block: "start" });

    if (link.closest("summary")) {
      link.closest("details")?.setAttribute("open", "");
    }
  },

  handleReaderClick(event) {
    if (this.focusSavedSelectionFromControl(event)) return;
    if (this.applyReaderStyleFromControl(event)) return;
    this.navigateToPaperSection(event);
  },

  focusSavedSelectionFromControl(event) {
    const control = event.target.closest("[data-paper-saved-selection-link]");
    if (!control || !this.el.contains(control)) return false;

    const sectionId = control.dataset.paperSelectionSection;
    const blockId = control.dataset.paperSelectionBlock;
    const selectedText = control.dataset.paperSelectionText;
    const selectionId = control.dataset.paperSelectionId;

    this.focusSavedSelection({ selectionId, sectionId, blockId, selectedText });

    return true;
  },

  focusSavedSelection({ selectionId, sectionId, blockId, selectedText }) {
    const escapedBlockId = cssEscape(blockId);
    const escapedSectionId = cssEscape(sectionId);

    const target =
      this.compiledShadowRoot?.querySelector(
        `[data-paper-block-id="${escapedBlockId}"], [data-paper-section-id="${escapedSectionId}"]`,
      ) ||
      document.getElementById(`paper-section-${sectionId}`) ||
      document.getElementById(sectionId);

    target?.scrollIntoView({ behavior: "smooth", block: "center" });

    const highlighted = this.compiledShadowRoot?.querySelector(
      selectionId
        ? `[data-paper-saved-term][data-paper-selection-id="${cssEscape(selectionId)}"]`
        : `[data-paper-saved-term][data-paper-selection-text="${cssEscape(selectedText)}"]`,
    );

    highlighted?.classList.add("is-active");
    window.setTimeout(() => highlighted?.classList.remove("is-active"), 1400);
  },

  applyReaderStyleFromControl(event) {
    const control = event.target.closest("[data-paper-style-control]");
    if (!control || !this.el.contains(control)) return false;

    event.preventDefault();

    const kind = control.dataset.paperStyleKind;
    const value = control.dataset.paperStyleValue;

    if (!kind || !value) return true;

    const root = this.el.querySelector("[data-paper-compiled-root]");
    if (!root) return true;

    root.dataset[`reader${capitalize(kind)}`] = value;
    this.updatePressedReaderControl(control, kind);
    this.applyReaderStyle();

    return true;
  },

  applyReaderStyle() {
    const root = this.el.querySelector("[data-paper-compiled-root]");
    if (!root) return;

    root.dataset.readerTheme ||= "light";
    root.dataset.readerFont ||= "default";
    root.dataset.readerSpacing ||= "compact";
  },

  updatePressedReaderControl(activeControl, kind) {
    for (const control of this.el.querySelectorAll(
      `[data-paper-style-kind="${kind}"]`,
    )) {
      control.setAttribute("aria-pressed", control === activeControl);
    }
  },

  findCompiledSection(sectionId) {
    if (!this.compiledShadowRoot) return null;

    const escaped = window.CSS?.escape
      ? CSS.escape(sectionId)
      : sectionId.replace(/"/g, '\\"');

    return this.compiledShadowRoot.querySelector(
      `#${escaped}, [data-paper-section-id="${escaped}"]`,
    );
  },

  captureSelection(selectionDocument = document, { commit = false } = {}) {
    const selection = selectionDocument.getSelection();
    const text = selection?.toString().trim() || "";

    if (!selection || selection.rangeCount === 0 || text.length === 0) {
      if (!this.selectionPanelHasContext()) this.clearSelectionPanel();
      return;
    }

    const range = selection.getRangeAt(0);
    const container = selectionElement(range.commonAncestorContainer);
    const startContainer = selectionElement(range.startContainer);

    if (
      !this.selectionBelongsToReader(container) &&
      !this.selectionBelongsToReader(startContainer)
    ) {
      return;
    }

    const block =
      container?.closest?.("[data-paper-block-id]") ||
      startContainer?.closest?.("[data-paper-block-id]");
    const section =
      container?.closest?.("[data-paper-section-id]") ||
      startContainer?.closest?.("[data-paper-section-id]");
    const blockId = block?.dataset.paperBlockId || "unknown block";
    const sectionId = section?.dataset.paperSectionId || "unknown section";

    this.showSelectionPanel({ text, blockId, sectionId, commit });
  },

  selectionBelongsToReader(container) {
    if (!container) return false;

    return (
      this.compiledShadowRoot &&
      container.getRootNode() === this.compiledShadowRoot
    ) || (
      this.el.querySelector(".paper-document")?.contains(container) &&
      container.closest?.("[data-paper-block-id], [data-paper-section-id]")
    );
  },

  selectionPanelHasContext() {
    const result = this.el.querySelector("[data-paper-selection-result]");
    const textTarget = this.el.querySelector("[data-paper-selection-text]");

    return Boolean(
      result &&
        !result.hidden &&
        (textTarget?.textContent || "").trim().length > 0,
    );
  },

  showSelectionPanel({ text, blockId, sectionId, commit = false }) {
    const empty = this.el.querySelector("[data-paper-selection-empty]");
    const result = this.el.querySelector("[data-paper-selection-result]");
    const textTarget = this.el.querySelector("[data-paper-selection-text]");
    const metaTarget = this.el.querySelector("[data-paper-selection-meta]");
    const termTarget = this.el.querySelector("[data-paper-selection-term]");
    const sectionTarget = this.el.querySelector("[data-paper-selection-section]");
    const blockTarget = this.el.querySelector("[data-paper-selection-block]");
    const graphSourceTarget = this.el.querySelector("[data-paper-graph-source]");
    const graphQuestionTarget = this.el.querySelector("[data-paper-graph-question]");
    const captureNode = this.el.querySelector("[data-paper-capture-node]");

    if (!result || !textTarget || !metaTarget) return;

    if (empty) empty.hidden = true;
    result.hidden = false;
    if (captureNode) captureNode.hidden = false;
    textTarget.textContent = text;
    metaTarget.textContent = `${formatSectionLabel(sectionId)} · ${blockId} · ${text.length} characters selected`;
    if (termTarget) termTarget.textContent = text;
    if (sectionTarget) sectionTarget.textContent = formatSectionLabel(sectionId);
    if (blockTarget) blockTarget.textContent = blockId;
    if (graphSourceTarget) graphSourceTarget.textContent = sectionId;
    if (graphQuestionTarget)
      graphQuestionTarget.textContent = `What does “${truncateText(text, 54)}” mean here?`;
    this.updateSelectionInputs({ text, sectionId, blockId });

    const signature = `${sectionId}::${blockId}::${text}`;
    if (signature !== this.lastSelectionSignature) {
      if (!commit) return;

      this.lastSelectionSignature = signature;
      this.pushEvent("paper_selection_captured", {
        selected_text: text,
        section_id: sectionId,
        block_id: blockId,
      });
    }
  },

  clearSelectionPanel() {
    const empty = this.el.querySelector("[data-paper-selection-empty]");
    const result = this.el.querySelector("[data-paper-selection-result]");
    const textTarget = this.el.querySelector("[data-paper-selection-text]");
    const metaTarget = this.el.querySelector("[data-paper-selection-meta]");
    const termTarget = this.el.querySelector("[data-paper-selection-term]");
    const sectionTarget = this.el.querySelector("[data-paper-selection-section]");
    const blockTarget = this.el.querySelector("[data-paper-selection-block]");
    const graphSourceTarget = this.el.querySelector("[data-paper-graph-source]");
    const graphQuestionTarget = this.el.querySelector("[data-paper-graph-question]");
    const captureNode = this.el.querySelector("[data-paper-capture-node]");

    if (empty) empty.hidden = false;
    if (result) result.hidden = true;
    if (captureNode) captureNode.hidden = true;
    if (textTarget) textTarget.textContent = "";
    if (metaTarget) metaTarget.textContent = "";
    if (termTarget) termTarget.textContent = "Selected passage";
    if (sectionTarget) sectionTarget.textContent = "unknown section";
    if (blockTarget) blockTarget.textContent = "unknown block";
    if (graphSourceTarget) graphSourceTarget.textContent = "Attention Is All You Need";
    if (graphQuestionTarget)
      graphQuestionTarget.textContent = "What does this term mean here?";
    this.updateSelectionInputs();
    this.lastSelectionSignature = null;
  },

  updateSelectionInputs({ text = "", sectionId = "", blockId = "" } = {}) {
    const values = {
      selected_text: text,
      section_id: sectionId,
      block_id: blockId,
    };

    for (const [name, value] of Object.entries(values)) {
      const input = this.el.querySelector(`[data-paper-selection-input="${name}"]`);
      if (input) input.value = value;
    }
  },

  decorateSavedAnnotations() {
    if (!this.compiledShadowRoot) return;

    const annotations = this.savedAnnotations();
    if (annotations.length === 0) return;

    for (const annotation of annotations) {
      if (
        !annotation.id ||
        !annotation.selected_text ||
        this.compiledShadowRoot.querySelector(
          `[data-paper-saved-term][data-paper-selection-id="${annotation.id}"]`,
        )
      ) {
        continue;
      }

      this.wrapSavedTerm(annotation);
    }
  },

  savedAnnotations() {
    try {
      return JSON.parse(this.el.dataset.paperAnnotations || "[]");
    } catch (_error) {
      return [];
    }
  },

  wrapSavedTerm(annotation) {
    const root =
      this.compiledShadowRoot.querySelector(
        `[data-paper-section-id="${cssEscape(annotation.section_id)}"]`,
      )?.parentElement || this.compiledShadowRoot;

    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode: (node) => {
        const text = node.textContent || "";
        const parent = node.parentElement;

        if (!text.includes(annotation.selected_text)) {
          return NodeFilter.FILTER_REJECT;
        }

        if (
          !parent ||
          parent.closest(
            "a, button, script, style, [data-paper-saved-term]",
          )
        ) {
          return NodeFilter.FILTER_REJECT;
        }

        return NodeFilter.FILTER_ACCEPT;
      },
    });

    const node = walker.nextNode();
    if (!node) return;

    const index = node.textContent.indexOf(annotation.selected_text);
    if (index < 0) return;

    const before = node.textContent.slice(0, index);
    const after = node.textContent.slice(index + annotation.selected_text.length);
    const marker = document.createElement("button");
    marker.type = "button";
    marker.className = "paper-term-question-link";
    marker.dataset.paperSavedTerm = "true";
    marker.dataset.paperSelectionId = annotation.id;
    marker.dataset.paperSelectionText = annotation.selected_text;
    marker.textContent = annotation.selected_text;
    marker.title = `${annotation.question_count} saved question${annotation.question_count === 1 ? "" : "s"}`;
    marker.addEventListener("click", (event) => {
      event.preventDefault();
      this.pushEvent("select_saved_selection", {
        id: String(annotation.id),
      });
      this.focusSavedSelection({
        selectionId: annotation.id,
        sectionId: annotation.section_id,
        blockId: annotation.block_id,
        selectedText: annotation.selected_text,
      });
    });

    node.replaceWith(before, marker, after);
  },
};

function headingTitle(heading) {
  const clone = heading.cloneNode(true);

  for (const element of clone.querySelectorAll(".titlemark, a[id]")) {
    element.remove();
  }

  return (clone.textContent || "").trim();
}

function slugify(value) {
  return value
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

function truncateText(value, maxLength) {
  if (value.length <= maxLength) return value;
  return `${value.slice(0, maxLength - 1)}…`;
}

function capitalize(value) {
  return `${value.charAt(0).toUpperCase()}${value.slice(1)}`;
}

function formatSectionLabel(value) {
  if (!value) return "Unknown section";
  if (value === "compiled-tex4ht") return "Compiled HTML";

  return value
    .split("-")
    .filter(Boolean)
    .map(capitalize)
    .join(" ");
}

function cssEscape(value) {
  if (window.CSS?.escape) return CSS.escape(value || "");
  return String(value || "").replace(/"/g, '\\"');
}

function selectionElement(node) {
  if (!node) return null;
  if (node.nodeType === Node.ELEMENT_NODE) return node;
  if (node.parentElement) return node.parentElement;
  if (node.host) return node.host;
  return null;
}

function nextElementSibling(element) {
  let sibling = element.nextElementSibling;

  while (sibling && isIgnorableCompiledElement(sibling)) {
    sibling = sibling.nextElementSibling;
  }

  return sibling;
}

function isIgnorableCompiledElement(element) {
  return (
    element.tagName === "BR" ||
    ((element.textContent || "").trim() === "" &&
      element.querySelector("img, table, figure") === null)
  );
}

function isCompiledFloat(element) {
  return (
    element.matches(".table, .figure, .float, figure.float, figure.figure") ||
    element.querySelector(":scope > figure.float, :scope > figure.figure") !==
      null
  );
}

function isParagraphLike(element) {
  return (
    element.matches("p, .noindent, .indent") &&
    (element.textContent || "").trim().length > 0
  );
}

export default PaperReader;
