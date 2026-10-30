(function () {
  'use strict';
  const storageKey = 'langpack_onboarding_v1';
  let firstVisit = false;
  try { const marker = localStorage.getItem(storageKey); firstVisit = marker === 'pending' || !marker && localStorage.getItem('langpack-prototype-v1') === null; } catch (_) { /* Preserve the workspace when storage cannot be inspected. */ }
  const logo = "<svg aria-hidden=\"true\" xmlns=\"http://www.w3.org/2000/svg\" width=\"1024\" height=\"1024\" viewBox=\"0 0 1024 1024\"> <rect width=\"1024\" height=\"1024\" fill=\"#197E64\"/> <g id=\"language-cards\"> <g transform=\"rotate(-11 412 465)\"> <rect x=\"236\" y=\"225\" width=\"362\" height=\"468\" rx=\"70\" fill=\"#CDE9D9\"/> <path d=\"M303 342H520M409 302V342M351 359C369 414 420 452 493 477M480 359C461 414 410 458 331 490\" fill=\"none\" stroke=\"#197E64\" stroke-width=\"28\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/> <path d=\"M311 563H403\" stroke=\"#197E64\" stroke-width=\"20\" stroke-linecap=\"round\" opacity=\".3\"/> </g> <g transform=\"rotate(11 621 596)\"> <rect x=\"440\" y=\"356\" width=\"354\" height=\"435\" rx=\"70\" fill=\"#F5F8F4\" stroke=\"#197E64\" stroke-opacity=\".13\" stroke-width=\"3\"/> <path d=\"M526 663L608 469C611 461 622 461 625 469L708 663M553 603H681\" fill=\"none\" stroke=\"#197E64\" stroke-width=\"30\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/> <path d=\"M535 718H694\" stroke=\"#197E64\" stroke-width=\"18\" stroke-linecap=\"round\" opacity=\".2\"/> </g> </g> </svg>";
  const arrow = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12h14m-5-5 5 5-5 5"/></svg>';
  const check = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m5 12 4 4L19 6"/></svg>';
  const pages = [
    {
      eyebrow: '01 / COLLECT YOUR WORDS',
      title: ['把文案，轻轻装进来', 'A little space for every word'],
      body: ['输入文字，或导入 TXT、Markdown、DOCX。把每一句原文，整理成清晰的语言条目。', 'Enter text or import TXT, Markdown, and DOCX files. Give every source string a clear place to start.'],
      hint: ['从一句话，到一整份文档', 'From a single phrase to a whole document'],
      art: english => `<div class="ob-illustration ob-collect"><div class="ob-orbit"></div><div class="ob-paper ob-back-paper"></div><div class="ob-paper ob-source-paper"><div class="ob-paper-caption"><span class="ob-small-file">≡</span>${english ? 'Product copy' : '产品文案'}<span class="ob-ellipsis">•••</span></div><div class="ob-source-row"><i>01</i><span>${english ? 'Welcome back, {name}' : '欢迎回来，{name}'}</span></div><div class="ob-source-row"><i>02</i><span>${english ? 'Let’s get started' : '开始新的旅程'}</span></div><div class="ob-source-row"><i>03</i><span>${english ? 'Save changes' : '保存更改'}</span></div><div class="ob-keyline"><span>⌘</span> welcome_back</div></div><div class="ob-file-pill"><span>↥</span>TXT · MD · DOCX</div><span class="ob-art-spark">✦</span></div>`
    },
    {
      eyebrow: '02 / REACH MORE LANGUAGES',
      title: ['一种表达，走向多种语言', 'One expression. More possibilities.'],
      body: ['在 35 种语言中选择目标，按需配置翻译平台。让新增文案与缺失译文，接着完成。', 'Choose targets from 35 languages and configure the providers you need. Keep moving with new strings and missing translations.'],
      hint: ['选择所需语言，保留每一份表达', 'Choose your languages. Keep every expression.'],
      art: english => `<div class="ob-illustration ob-languages"><div class="ob-orbit"></div><div class="ob-language-center">${english ? 'Hello' : '你好'}<span>zh · en</span></div><div class="ob-language-chip ob-chip-en"><span>EN</span>Hello ${check}</div><div class="ob-language-chip ob-chip-ja"><span>JA</span>こんにちは ${check}</div><div class="ob-language-chip ob-chip-fr"><span>FR</span>Bonjour ${check}</div><div class="ob-language-chip ob-chip-ko"><span>KO</span>안녕하세요 ${check}</div><div class="ob-language-count"><strong>35</strong><span>${english ? 'languages to explore' : '种语言，自由选择'}</span></div><span class="ob-art-spark">✦</span></div>`
    },
    {
      eyebrow: '03 / PACK IT WITH CONFIDENCE',
      title: ['认真校对，安心交付', 'Thoughtfully reviewed. Ready to go.'],
      body: ['逐条检查译文与占位符，再导出 JSON 或 ZIP。让每一个语言包，都有条不紊。', 'Review translations and placeholders, then export JSON or ZIP. Keep every language pack organized and ready to use.'],
      hint: ['从好文案，到准备就绪的语言包', 'From good words to a ready-to-use language pack'],
      art: english => `<div class="ob-illustration ob-export"><div class="ob-orbit"></div><div class="ob-paper ob-json-paper"><div class="ob-paper-caption"><span class="ob-json-braces">{ }</span>en.json ${check}</div><pre>{\n  <b>"welcome"</b>: "Hello",\n  <b>"save"</b>: "Save"\n}</pre><div class="ob-export-check">${check}${english ? 'Placeholders checked' : '占位符保持一致'}</div></div><div class="ob-pack"><span class="ob-pack-zip">•••<br>•••<br>•••</span><span>{ }</span><strong>LangPack.zip</strong><small>JSON · UTF-8</small></div><span class="ob-art-spark">✦</span></div>`
    }
  ];
  let dialog, page = 0, english = false, previousFocus, onLanguageChange;
  function remember() { try { localStorage.setItem(storageKey, 'complete'); } catch (_) { /* The current session can still proceed. */ } }
  function close() {
    remember();
    dialog?.close();
    if (previousFocus?.isConnected) previousFocus.focus();
  }
  function render(focus = false) {
    const current = pages[page], locale = english ? 1 : 0;
    dialog.lang = english ? 'en' : 'zh-CN';
    dialog.innerHTML = `<div class="ob-frame"><header class="ob-header"><div class="ob-brand"><span class="ob-brand-icon">${logo}</span><span>LangPack</span></div><div class="ob-header-actions"><button type="button" data-ob="language" class="ob-language" aria-label="${english ? 'Switch to Chinese' : 'Switch to English'}">${english ? '中文' : 'English'}</button><button type="button" class="ob-skip" data-ob="skip">${english ? 'Skip' : '跳过'}</button></div></header><div class="ob-layout"><div class="ob-art-panel" aria-hidden="true">${current.art(english)}<p>${current.hint[locale]}</p></div><section class="ob-copy"><div class="ob-eyebrow">${current.eyebrow}</div><h1 id="ob-title" tabindex="-1">${current.title[locale]}</h1><p class="ob-description">${current.body[locale]}</p><div class="ob-page-progress" aria-label="${english ? `Step ${page + 1} of 3` : `第 ${page + 1} 步，共 3 步`}">${pages.map((_, index) => `<button type="button" data-ob="page" data-page="${index}" class="${index === page ? 'is-active' : ''}" ${index === page ? 'aria-current="step"' : ''} aria-label="${english ? `Step ${index + 1}` : `第 ${index + 1} 页`}"><span></span></button>`).join('')}</div><div class="ob-footer"><button type="button" data-ob="previous" class="ob-previous" ${page === 0 ? 'disabled aria-hidden="true" tabindex="-1"' : ''}>${english ? 'Back' : '上一步'}</button><button type="button" data-ob="next" class="ob-primary">${page === 2 ? english ? 'Open my workspace' : '开始使用译包' : english ? 'Continue' : '下一步'}${arrow}</button></div><div class="ob-note">${english ? 'Your words. Your languages. Beautifully organized.' : '让每一种表达，都有自己的位置。'}</div></section></div><div class="ob-bottom-label">LANGPACK · MADE FOR EVERY LANGUAGE</div></div>`;
    if (focus) dialog.querySelector('#ob-title').focus();
  }
  function show(options = {}) {
    english = !!options.english;
    page = 0;
    previousFocus = document.activeElement;
    if (!dialog) {
      dialog = document.createElement('dialog');
      dialog.id = 'langpack-onboarding';
      dialog.setAttribute('aria-labelledby', 'ob-title');
      dialog.addEventListener('click', event => {
        const button = event.target.closest('[data-ob]');
        if (!button || button.disabled) return;
        switch (button.dataset.ob) {
          case 'skip': close(); return;
          case 'next': if (page === pages.length - 1) { close(); return; } page++; break;
          case 'previous': page = Math.max(0, page - 1); break;
          case 'page': page = Number(button.dataset.page); break;
          case 'language': english = !english; onLanguageChange?.(english); break;
        }
        render(true);
      });
      dialog.addEventListener('cancel', event => { event.preventDefault(); close(); });
      dialog.addEventListener('keydown', event => {
        if (event.key === 'ArrowRight' && page < pages.length - 1) { event.preventDefault(); page++; render(true); }
        if (event.key === 'ArrowLeft' && page > 0) { event.preventDefault(); page--; render(true); }
      });
      document.body.append(dialog);
    }
    render();
    if (!dialog.open) dialog.showModal();
    dialog.querySelector('#ob-title').focus();
  }
  window.LangPackOnboarding = {
    logo,
    show,
    initialize(options = {}) {
      onLanguageChange = options.onLanguageChange;
      document.querySelectorAll('.langpack-boot-emblem').forEach(node => { node.innerHTML = logo; });
      if (firstVisit) { firstVisit = false; try { localStorage.setItem(storageKey, 'pending'); } catch (_) {} show(options); }
    }
  };
  document.querySelectorAll('.langpack-boot-emblem').forEach(node => { node.innerHTML = logo; });
})();
