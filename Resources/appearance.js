(() => {
  if (location.protocol !== 'https:' || location.hostname !== 'weread.qq.com') return;
  // Install before site scripts measure text and cache canvas page coordinates.
  // document.body does not exist yet at documentStart; use documentElement below.
  const settings = __READER_SETTINGS__;
  const id = 'qingdu-appearance';
  let style = document.getElementById(id);
  if (!style) {
    style = document.createElement('style');
    style.id = id;
    (document.head || document.documentElement).appendChild(style);
  }
  // The official reader paints some text into a dedicated canvas layer.
  // Recolor only that layer and add a thin dark outline; leave images alone.
  if (!document.getElementById('qingdu-text-filters')) {
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.id = 'qingdu-text-filters';
    svg.setAttribute('aria-hidden', 'true');
    svg.setAttribute('width', '0');
    svg.setAttribute('height', '0');
    svg.style.cssText = 'position:absolute;pointer-events:none;overflow:hidden';
    svg.innerHTML = `<defs>
      <filter id="qingdu-gold-text" color-interpolation-filters="sRGB">
        <feColorMatrix in="SourceGraphic" result="gold" type="matrix" values="
          0 0 0 0 0.831373
          0 0 0 0 0.686275
          0 0 0 0 0.215686
          0 0 0 1 0" />
        <feMorphology in="SourceAlpha" operator="dilate" radius="0.65" result="outlineMask" />
        <feFlood flood-color="#29251E" flood-opacity="0.9" result="outlineColor" />
        <feComposite in="outlineColor" in2="outlineMask" operator="in" result="outline" />
        <feMerge><feMergeNode in="outline" /><feMergeNode in="gold" /></feMerge>
      </filter>
    </defs>`;
    (document.body || document.documentElement).appendChild(svg);
  }
  const readingStyle = `
    /* Keep layout boxes intact: the reader measures them for canvas pagination. */
    body:has(.readerChapterContent, .wr_horizontalReader) :is(.readerTopBar, .readerControls, .readerBottomBar, .wr_reader_float_corner_bookmark_wrapper),
    body:has(.readerChapterContent, .wr_horizontalReader) :is(.readerTopBar, .readerControls, .readerBottomBar, .wr_reader_float_corner_bookmark_wrapper) * {
      visibility: hidden !important;
      pointer-events: none !important;
    }

    .preRenderContainer .preRenderContent,
    .preRenderContainer .preRenderContent :is(p, span, div, a, h1, h2, h3, h4, h5, h6),
    .readerChapterContent .renderTargetContent,
    .readerChapterContent .renderTargetContent :is(p, span, div, a, h1, h2, h3, h4, h5, h6),
    .readerChapterContent .renderTargetPageInfo_header {
      font-family: "PingFang SC", -apple-system, "Helvetica Neue", sans-serif !important;
      font-weight: 500 !important;
    }
    .preRenderContainer .preRenderContent p,
    .readerChapterContent .renderTargetContent p {
      line-height: 1.55 !important;
      margin-bottom: 0.6em !important;
    }
    .preRenderContainer .preRenderContent p:last-child,
    .readerChapterContent .renderTargetContent p:last-child {
      margin-bottom: 0 !important;
    }
    .readerChapterContent,
    .readerChapterContent .renderTargetContent,
    .readerChapterContent .renderTargetContent :is(p, span, div, a, h1, h2, h3, h4, h5, h6, pre, code),
    .readerChapterContent .renderTargetPageInfo_header,
    .readerChapterContent .renderTargetPageInfo_header * {
      text-shadow: -0.65px 0 #29251E, 0.65px 0 #29251E, 0 -0.65px #29251E, 0 0.65px #29251E;
      color: #D4AF37 !important;
      -webkit-text-fill-color: #D4AF37 !important;
    }
    .readerChapterContent .wr_canvasContainer canvas {
      filter: url('#qingdu-gold-text') !important;
    }
    .wr_horizontalReader .renderTarget_pager_button,
    .readerContentHeader .readerHeaderButton,
    .readerFooter_button[title="上一页"],
    .readerFooter_button[title="下一页"] {
      display: none !important;
    }
  `;
  // Scope to the reader. Bookstore, QR login, notes and dialogs keep their own backgrounds.
  style.textContent = readingStyle + (settings.transparent ? `
    html:has(.readerChapterContent),
    html:has(.wr_horizontalReader),
    body:has(.readerChapterContent),
    body:has(.wr_horizontalReader),
    .app:has(.readerChapterContent),
    .app:has(.wr_horizontalReader),
    .readerContent, .readerChapterContent, .readerChapterContent_container,
    .wr_horizontalReader, .wr_horizontalReader_app_content, .wr_horizontalReader .renderTargetContainer,
    .wr_horizontalReader .renderTargetContent,
    .app_content:has(.readerChapterContent),
    .app_content:has(.wr_horizontalReader) {
      background: transparent !important;
      box-shadow: none !important;
    }
    body:has(.readerChapterContent), body:has(.wr_horizontalReader) {
      background: rgba(28, 28, 30, ${settings.opacity}) !important;
    }
    body.wr_whiteTheme:has(.readerChapterContent),
    body.wr_whiteTheme:has(.wr_horizontalReader),
    body:has(.wr_whiteTheme .readerChapterContent),
    body:has(.wr_whiteTheme .wr_horizontalReader) {
      background: rgba(255, 255, 255, ${settings.opacity}) !important;
    }
    .readerTopBar {
      background: rgba(28, 28, 30, ${settings.opacity}) !important;
      border-bottom-color: transparent !important;
      box-shadow: none !important;
    }
    .wr_whiteTheme .readerTopBar { background: rgba(255, 255, 255, ${settings.opacity}) !important; }
  ` : '');
})();
