/* LangPack prototype engine. Local demonstration data; no remote translation calls. */
(function (root) {
  'use strict';

  const encoder = new TextEncoder();
  const localeCodes = ['en', 'ja', 'ko', 'fr', 'de', 'es', 'zh-Hant'];
  const rows = [
    ['登录', 'login', 'Log in', 'ログイン', '로그인', 'Se connecter', 'Anmelden', 'Iniciar sesión', '登入'],
    ['注册', 'register', 'Sign up', '新規登録', '회원가입', "S’inscrire", 'Registrieren', 'Registrarse', '註冊'],
    ['注册账号', 'register_account', 'Create an account', 'アカウントを作成', '계정 만들기', 'Créer un compte', 'Konto erstellen', 'Crear una cuenta', '註冊帳號'],
    ['退出登录', 'log_out', 'Log out', 'ログアウト', '로그아웃', 'Se déconnecter', 'Abmelden', 'Cerrar sesión', '登出'],
    ['退出', 'exit', 'Exit', '終了', '종료', 'Quitter', 'Beenden', 'Salir', '退出'],
    ['忘记密码', 'forgot_password', 'Forgot password?', 'パスワードをお忘れですか？', '비밀번호를 잊으셨나요?', 'Mot de passe oublié ?', 'Passwort vergessen?', '¿Olvidaste tu contraseña?', '忘記密碼'],
    ['密码', 'password', 'Password', 'パスワード', '비밀번호', 'Mot de passe', 'Passwort', 'Contraseña', '密碼'],
    ['请输入密码', 'enter_password', 'Enter your password', 'パスワードを入力してください', '비밀번호를 입력하세요', 'Saisissez votre mot de passe', 'Passwort eingeben', 'Introduce tu contraseña', '請輸入密碼'],
    ['请输入用户名', 'enter_username', 'Enter your username', 'ユーザー名を入力してください', '사용자 이름을 입력하세요', "Saisissez votre nom d’utilisateur", 'Benutzernamen eingeben', 'Introduce tu nombre de usuario', '請輸入使用者名稱'],
    ['用户名', 'username', 'Username', 'ユーザー名', '사용자 이름', "Nom d’utilisateur", 'Benutzername', 'Nombre de usuario', '使用者名稱'],
    ['欢迎回来', 'welcome_back', 'Welcome back', 'おかえりなさい', '다시 오신 것을 환영합니다', 'Bon retour', 'Willkommen zurück', 'Te damos la bienvenida de nuevo', '歡迎回來'],
    ['欢迎回来，{name}', 'welcome_back_user', 'Welcome back, {name}', 'おかえりなさい、{name}', '{name}님, 다시 오신 것을 환영합니다', 'Bon retour, {name}', 'Willkommen zurück, {name}', 'Te damos la bienvenida de nuevo, {name}', '歡迎回來，{name}'],
    ['欢迎，{name}', 'welcome_user', 'Welcome, {name}', 'ようこそ、{name}', '{name}님, 환영합니다', 'Bienvenue, {name}', 'Willkommen, {name}', 'Bienvenido, {name}', '歡迎，{name}'],
    ['保存', 'save', 'Save', '保存', '저장', 'Enregistrer', 'Speichern', 'Guardar', '儲存'],
    ['保存更改', 'save_changes', 'Save changes', '変更を保存', '변경 사항 저장', 'Enregistrer les modifications', 'Änderungen speichern', 'Guardar cambios', '儲存變更'],
    ['开启通知', 'enable_notifications', 'Enable notifications', '通知を有効にする', '알림 켜기', 'Activer les notifications', 'Benachrichtigungen aktivieren', 'Activar notificaciones', '開啟通知'],
    ['取消', 'cancel', 'Cancel', 'キャンセル', '취소', 'Annuler', 'Abbrechen', 'Cancelar', '取消'],
    ['确定', 'confirm', 'Confirm', '確認', '확인', 'Confirmer', 'Bestätigen', 'Confirmar', '確定'],
    ['删除', 'delete', 'Delete', '削除', '삭제', 'Supprimer', 'Löschen', 'Eliminar', '刪除'],
    ['下一步', 'next_step', 'Next', '次へ', '다음', 'Suivant', 'Weiter', 'Siguiente', '下一步'],
    ['返回', 'go_back', 'Back', '戻る', '뒤로', 'Retour', 'Zurück', 'Volver', '返回'],
    ['开始使用', 'get_started', 'Get started', '始める', '시작하기', 'Commencer', 'Jetzt starten', 'Comenzar', '開始使用'],
    ['立即开始', 'start_now', 'Start now', '今すぐ始める', '지금 시작하기', 'Commencer maintenant', 'Jetzt beginnen', 'Empezar ahora', '立即開始'],
    ['密码重置成功', 'password_reset_success', 'Password reset successfully', 'パスワードをリセットしました', '비밀번호가 재설정되었습니다', 'Mot de passe réinitialisé', 'Passwort erfolgreich zurückgesetzt', 'Contraseña restablecida', '密碼重設成功'],
    ['登录成功', 'login_success', 'Logged in successfully', 'ログインしました', '로그인되었습니다', 'Connexion réussie', 'Erfolgreich angemeldet', 'Has iniciado sesión', '登入成功'],
    ['邮箱地址', 'email_address', 'Email address', 'メールアドレス', '이메일 주소', 'Adresse e-mail', 'E-Mail-Adresse', 'Dirección de correo electrónico', '電子郵件地址'],
    ['请先阅读并同意用户协议', 'accept_user_agreement', 'Please read and accept the User Agreement', '利用規約を読み、同意してください', '이용약관을 읽고 동의해 주세요', "Veuillez lire et accepter les conditions d’utilisation", 'Bitte lesen und akzeptieren Sie die Nutzungsbedingungen', 'Lee y acepta el Acuerdo de usuario', '請先閱讀並同意使用者協議'],
    ['让每一段中文，抵达更多语言。', 'reach_more_languages', 'Bring every Chinese passage to more languages.', 'すべての中国語の文章を、より多くの言語へ。', '모든 중국어 문장을 더 많은 언어로 전하세요.', 'Ouvrez chaque texte chinois à davantage de langues.', 'Bringen Sie jeden chinesischen Text in weitere Sprachen.', 'Lleva cada texto en chino a más idiomas.', '讓每一段中文，抵達更多語言。'],
    ['欢迎使用译包。', 'welcome_to_langpack', 'Welcome to LangPack.', 'LangPack へようこそ。', 'LangPack에 오신 것을 환영합니다.', 'Bienvenue sur LangPack.', 'Willkommen bei LangPack.', 'Te damos la bienvenida a LangPack.', '歡迎使用譯包。'],
    ['一次输入，即可生成多种语言的翻译结果。', 'translate_into_multiple_languages', 'Enter your text once and generate translations in multiple languages.', '一度の入力で、複数の言語に翻訳できます。', '한 번 입력하면 여러 언어의 번역 결과를 생성할 수 있습니다.', 'Saisissez votre texte une seule fois pour générer des traductions en plusieurs langues.', 'Geben Sie Ihren Text einmal ein und erstellen Sie Übersetzungen in mehreren Sprachen.', 'Introduce tu texto una vez y genera traducciones en varios idiomas.', '一次輸入，即可產生多種語言的翻譯結果。'],
    ['为每一段中文生成稳定的语义 key。', 'generate_stable_semantic_keys', 'Generate a stable semantic key for every Chinese passage.', '中国語の各段落に、安定した意味のあるキーを生成します。', '각 중국어 문단에 안정적인 의미 기반 키를 생성합니다.', 'Générez une clé sémantique stable pour chaque paragraphe en chinois.', 'Erstellen Sie für jeden chinesischen Absatz einen stabilen semantischen Schlüssel.', 'Genera una clave semántica estable para cada párrafo en chino.', '為每一段中文產生穩定的語義 key。'],
    ['按语言导出 JSON，让本地化更简单。', 'export_json_by_language', 'Export JSON by language to make localization easier.', '言語ごとに JSON を書き出して、ローカライズを簡単に。', '언어별 JSON 내보내기로 현지화를 더 간편하게 만드세요.', 'Exportez des fichiers JSON par langue pour simplifier la localisation.', 'Exportieren Sie JSON nach Sprache und vereinfachen Sie die Lokalisierung.', 'Exporta JSON por idioma y simplifica la localización.', '按語言匯出 JSON，讓在地化更簡單。'],
    ['项目名称', 'project_name', 'Project name', 'プロジェクト名', '프로젝트 이름', 'Nom du projet', 'Projektname', 'Nombre del proyecto', '專案名稱'],
    ['新建项目', 'create_project', 'Create project', 'プロジェクトを作成', '프로젝트 만들기', 'Créer un projet', 'Projekt erstellen', 'Crear proyecto', '建立專案'],
    ['设置', 'settings', 'Settings', '設定', '설정', 'Paramètres', 'Einstellungen', 'Configuración', '設定'],
    ['加载中', 'loading', 'Loading', '読み込み中', '불러오는 중', 'Chargement', 'Wird geladen', 'Cargando', '載入中'],
    ['网络连接失败，请稍后重试。', 'network_error_retry', 'Connection failed. Please try again later.', '接続に失敗しました。しばらくしてからもう一度お試しください。', '연결에 실패했습니다. 잠시 후 다시 시도해 주세요.', 'La connexion a échoué. Réessayez plus tard.', 'Verbindung fehlgeschlagen. Bitte versuchen Sie es später erneut.', 'La conexión ha fallado. Vuelve a intentarlo más tarde.', '網路連線失敗，請稍後重試。']
  ];
  const dictionary = new Map(rows.map(row => [normalizeSource(row[0]), { key: row[1], values: Object.fromEntries(localeCodes.map((locale, i) => [locale, row[i + 2]])) }]));

  function normalizeSource(value) {
    return String(value == null ? '' : value).normalize('NFC').trim().replace(/[。.!！?？]+$/u, '').replace(/\s+/gu, ' ');
  }

  function sourceHash(value) {
    let hash = 2166136261;
    for (const character of String(value)) {
      hash ^= character.codePointAt(0);
      hash = Math.imul(hash, 16777619);
    }
    return (hash >>> 0).toString(36).padStart(7, '0');
  }

  function makeId() {
    return root.crypto && typeof root.crypto.randomUUID === 'function' ? root.crypto.randomUUID() : 'entry_' + Date.now().toString(36) + '_' + Math.random().toString(36).slice(2, 10);
  }

  function uniqueKey(source, existingKeys, context) {
    const used = new Set(Array.from(existingKeys || []).map(item => typeof item === 'string' ? item : item.key));
    const normalized = normalizeSource(source);
    const known = dictionary.get(normalized);
    let base;
    if (known) {
      base = known.key;
    } else if (/^[\x20-\x7E]+$/.test(normalized) && /[a-zA-Z]/.test(normalized)) {
      base = normalized.toLowerCase().replace(/\{[^}]*\}|%\d*\$?[sdif]/g, '').replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '').slice(0, 48).replace(/_+$/, '') || 'text';
      if (!/^[a-z]/.test(base)) base = 'text_' + base;
    } else {
      // Unknown copy must not pretend an automatic semantic model is available.
      base = 'text_' + sourceHash(normalized);
    }
    const prefix = String(context || '').toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '');
    if (prefix) base = (prefix + '_' + base).slice(0, 64).replace(/_+$/, '');
    if (!used.has(base)) return base;
    const suffix = sourceHash(normalized + '\u0000' + (context || ''));
    const candidate = base.slice(0, 53) + '_' + suffix;
    if (!used.has(candidate)) return candidate;
    let count = 2;
    while (used.has(candidate + '_' + count)) count++;
    return candidate + '_' + count;
  }

  function fromBlocks(blocks) {
    const used = new Set();
    return blocks.map((block, index) => {
      const source = (typeof block === 'string' ? block : block.text).trim();
      const key = uniqueKey(source, used);
      used.add(key);
      return { id: makeId(), key, source, selected: true, translations: {}, reviewed: {}, sourceVersion: 1, sourceIndex: index, sourceType: typeof block === 'string' ? 'paragraph' : block.type || 'paragraph', keyGenerated: dictionary.has(normalizeSource(source)) ? 'semantic' : 'fallback' };
    }).filter(entry => entry.source);
  }

  function splitText(text, mode) {
    const clean = String(text || '').replace(/^\uFEFF/, '').replace(/\r\n?/g, '\n').trim();
    if (!clean) return [];
    if (mode === 'line' || mode === 'lines') return fromBlocks(clean.split('\n').map(line => line.trim()).filter(Boolean));
    if (mode === 'markdown' || mode === 'md') return fromBlocks(markdownBlocks(clean));
    return fromBlocks(clean.split(/\n[\t ]*\n+/).map(part => part.trim()).filter(Boolean));
  }

  function markdownBlocks(text) {
    const blocks = [];
    let pending = [];
    let fence = null;
    const flush = () => { if (pending.length) blocks.push({ text: pending.join('\n'), type: 'paragraph' }); pending = []; };
    for (const line of text.split('\n')) {
      const mark = line.match(/^\s{0,3}(`{3,}|~{3,})/);
      if (mark) {
        flush();
        if (!fence) fence = mark[1][0];
        else if (mark[1][0] === fence) fence = null;
        continue;
      }
      if (fence) continue;
      if (!line.trim()) { flush(); continue; }
      if (/^\s{0,3}(?:[-*_]\s*){3,}$/.test(line)) { flush(); continue; }
      const heading = line.match(/^\s{0,3}#{1,6}\s+(.+?)(?:\s+#+)?$/);
      const list = line.match(/^\s*(?:[-+*]|\d+[.)])\s+(.+)$/);
      if (heading || list) {
        flush();
        blocks.push({ text: (heading || list)[1], type: heading ? 'heading' : 'list' });
      } else if (/^\s*\|?\s*:?-{3,}:?\s*(?:\|\s*:?-{3,}:?\s*)+\|?\s*$/.test(line)) {
        flush();
      } else if (line.includes('|')) {
        flush();
        line.replace(/^\s*\||\|\s*$/g, '').split('|').map(cell => cell.trim()).filter(Boolean).forEach(cell => blocks.push({ text: cell, type: 'table-cell' }));
      } else {
        pending.push(line.replace(/^\s*>\s?/, ''));
      }
    }
    flush();
    return blocks;
  }

  async function unzipMember(bytes, targetName) {
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    let eocd = -1;
    for (let i = bytes.length - 22; i >= Math.max(0, bytes.length - 65557); i--) {
      if (view.getUint32(i, true) === 0x06054b50) { eocd = i; break; }
    }
    if (eocd < 0) throw new Error('无法读取 DOCX，请确认文件未损坏且未加密。');
    const count = view.getUint16(eocd + 10, true);
    let offset = view.getUint32(eocd + 16, true);
    if (count === 65535 || offset === 0xffffffff) throw new Error('暂不支持超大型 ZIP64 文档，请另存为较小的 DOCX 或 TXT。');
    const decoder = new TextDecoder();
    for (let item = 0; item < count; item++) {
      if (offset + 46 > bytes.length || view.getUint32(offset, true) !== 0x02014b50) throw new Error('DOCX 文件目录不完整。');
      const flags = view.getUint16(offset + 8, true);
      const method = view.getUint16(offset + 10, true);
      const compressedSize = view.getUint32(offset + 20, true);
      const plainSize = view.getUint32(offset + 24, true);
      const nameLength = view.getUint16(offset + 28, true);
      const extraLength = view.getUint16(offset + 30, true);
      const commentLength = view.getUint16(offset + 32, true);
      const name = decoder.decode(bytes.subarray(offset + 46, offset + 46 + nameLength));
      if (name === targetName) {
        if (flags & 1) throw new Error('暂不支持加密 DOCX，请先移除密码。');
        if (plainSize > 20 * 1024 * 1024) throw new Error('文档正文过大，原型最多处理 20 MB 解压后的正文。');
        const local = view.getUint32(offset + 42, true);
        if (local + 30 > bytes.length || view.getUint32(local, true) !== 0x04034b50) throw new Error('DOCX 正文位置无效。');
        const start = local + 30 + view.getUint16(local + 26, true) + view.getUint16(local + 28, true);
        if (start + compressedSize > bytes.length) throw new Error('DOCX 正文不完整。');
        const compressed = bytes.slice(start, start + compressedSize);
        if (method === 0) return decoder.decode(compressed);
        if (method !== 8) throw new Error('暂不支持此 DOCX 压缩方式，请另存为标准 DOCX。');
        if (typeof DecompressionStream === 'undefined') throw new Error('当前浏览器无法解压 DOCX，请使用新版浏览器，或导出为 TXT 后上传。');
        let decompressor;
        try { decompressor = new DecompressionStream('deflate-raw'); } catch (_) { throw new Error('当前浏览器不支持 DOCX 解压，请使用新版浏览器，或上传 TXT。'); }
        const reader = new Blob([compressed]).stream().pipeThrough(decompressor).getReader();
        const chunks = [];
        let total = 0;
        for (;;) {
          const part = await reader.read();
          if (part.done) break;
          total += part.value.length;
          if (total > 20 * 1024 * 1024) { await reader.cancel(); throw new Error('文档正文超过原型的 20 MB 处理上限。'); }
          chunks.push(part.value);
        }
        const result = new Uint8Array(total);
        let position = 0;
        chunks.forEach(chunk => { result.set(chunk, position); position += chunk.length; });
        return decoder.decode(result);
      }
      offset += 46 + nameLength + extraLength + commentLength;
    }
    throw new Error('未找到 DOCX 正文，请上传标准 Word 文档。');
  }

  function docxBlocks(xml) {
    if (typeof DOMParser === 'undefined') throw new Error('当前环境缺少文档解析能力，请在浏览器中导入 DOCX。');
    const document = new DOMParser().parseFromString(xml, 'application/xml');
    if (document.getElementsByTagName('parsererror').length) throw new Error('DOCX 正文格式错误，请重新另存为 DOCX。');
    const wordNamespace = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
    const body = document.getElementsByTagNameNS(wordNamespace, 'body')[0];
    if (!body) throw new Error('DOCX 中没有可读取的正文。');
    const paragraphText = paragraph => {
      let text = '';
      const walk = node => {
        if (node.nodeType === 1 && node.namespaceURI === wordNamespace) {
          if (node.localName === 'del') return;
          if (node.localName === 't') { text += node.textContent; return; }
          if (node.localName === 'tab') { text += '\t'; return; }
          if (node.localName === 'br' || node.localName === 'cr') { text += '\n'; return; }
        }
        Array.from(node.childNodes || []).forEach(walk);
      };
      walk(paragraph);
      return text.trim();
    };
    const result = [];
    const read = node => {
      if (node.nodeType !== 1) return;
      if (node.namespaceURI === wordNamespace && node.localName === 'p') {
        const text = paragraphText(node);
        const style = node.getElementsByTagNameNS(wordNamespace, 'pStyle')[0];
        const styleName = style && (style.getAttributeNS(wordNamespace, 'val') || style.getAttribute('w:val')) || '';
        const type = /heading|title|标题/i.test(styleName) ? 'heading' : node.getElementsByTagNameNS(wordNamespace, 'numPr').length ? 'list' : 'paragraph';
        if (text) result.push({ text, type });
        return;
      }
      if (node.namespaceURI === wordNamespace && node.localName === 'tc') {
        const text = Array.from(node.getElementsByTagNameNS(wordNamespace, 'p')).map(paragraphText).filter(Boolean).join('\n');
        if (text) result.push({ text, type: 'table-cell' });
        return;
      }
      Array.from(node.children || []).forEach(read);
    };
    read(body);
    return result;
  }

  async function parseDocument(file) {
    if (!file || typeof file.name !== 'string') throw new Error('请先选择需要导入的文件。');
    if (file.size > 20 * 1024 * 1024) throw new Error('原型支持 20 MB 以内的文档，请缩小文件后重试。');
    const extension = file.name.split('.').pop().toLowerCase();
    let entries;
    if (extension === 'txt' || extension === 'md' || extension === 'markdown') {
      entries = splitText(await file.text(), extension === 'txt' ? 'paragraph' : 'markdown');
    } else if (extension === 'docx') {
      const xml = await unzipMember(new Uint8Array(await file.arrayBuffer()), 'word/document.xml');
      entries = fromBlocks(docxBlocks(xml));
    } else {
      throw new Error('请选择 TXT、Markdown 或 DOCX 文件。PDF 与扫描件暂不支持。');
    }
    if (!entries.length) throw new Error('没有找到可翻译的文字，请确认文档正文不是图片或空内容。');
    return { entries, fileName: file.name };
  }

  function translate(source, locale) {
    const entry = dictionary.get(normalizeSource(source));
    const canonicalLocale = ({ 'en-US': 'en', 'en-GB': 'en', 'ja-JP': 'ja', 'ko-KR': 'ko', 'fr-FR': 'fr', 'de-DE': 'de', 'es-ES': 'es', 'zh-TW': 'zh-Hant' })[locale] || locale;
    if (canonicalLocale === 'zh-Hans' || canonicalLocale === 'zh-CN') return { text: String(source), demo: true, known: true };
    const text = entry && entry.values[canonicalLocale];
    return { text: typeof text === 'string' ? text : '', demo: true, known: typeof text === 'string' };
  }

  function translationText(entry, locale) {
    const value = entry.translations && entry.translations[locale];
    return value && typeof value === 'object' ? String(value.text == null ? '' : value.text) : String(value == null ? '' : value);
  }

  function placeholders(text) {
    // Double braces are matched first so {{name}} is not treated as {name}.
    const matches = String(text || '').match(/\{\{\s*[\w.]+\s*\}\}|\{[\w.]+\}|%(?:\d+\$)?[-+#0 ']*(?:\d+|\*)?(?:\.(?:\d+|\*))?[sdif@uoxXegGc]|%%/g) || [];
    return matches.filter(item => item !== '%%').map(item => item.replace(/\s+/g, '')).sort();
  }

  function validate(entries, locales) {
    const active = (entries || []).filter(entry => entry.selected !== false);
    const issues = [];
    const keys = new Set();
    active.forEach(entry => {
      const add = (type, message, locale) => issues.push({ entryId: entry.id, key: entry.key, locale: locale || null, type, message });
      if (!/^[a-z][a-z0-9_]{0,79}$/.test(entry.key || '')) add('key', 'key 需以小写英文字母开头，仅包含小写字母、数字和下划线，最多 80 个字符。');
      if (keys.has(entry.key)) add('duplicate', '存在重复 key：' + entry.key);
      keys.add(entry.key);
      if (!String(entry.source || '').trim()) add('source', '中文原文不能为空。');
      const expected = placeholders(entry.source);
      Array.from(new Set(locales || [])).forEach(locale => {
        const text = translationText(entry, locale);
        if (!text.trim()) add('missing', '该语言译文尚未补全。', locale);
        else {
          const meta = entry.translationMeta && entry.translationMeta[locale];
          const checked = entry.edited && entry.edited[locale] || entry.reviewed && entry.reviewed[locale];
          if (meta && meta.status === 'failed' && !checked) add('translation', '该译文的翻译请求失败，请重试或人工确认现有内容。', locale);
          else if (meta && meta.provider === 'LegacyDemo' && !checked) add('legacy', '历史演示译文需重新翻译，或经人工校对确认。', locale);
          if (JSON.stringify(placeholders(text)) !== JSON.stringify(expected)) add('placeholders', '译文中的占位符与原文不一致。', locale);
        }
      });
    });
    if (!active.length) issues.push({ entryId: null, key: null, locale: null, type: 'empty', message: '请至少选择一条文案。' });
    if (!(locales || []).length) issues.push({ entryId: null, key: null, locale: null, type: 'language', message: '请至少选择一种目标语言。' });
    return issues;
  }

  function makePackages(entries, locales, includeSource) {
    const active = (entries || []).filter(entry => entry.selected !== false).slice().sort((a, b) => a.key < b.key ? -1 : a.key > b.key ? 1 : 0);
    const keys = new Set();
    active.forEach(entry => {
      if (!/^[a-z][a-z0-9_]{0,79}$/.test(entry.key || '') || keys.has(entry.key)) throw new Error('请先修复重复或格式不正确的 key。');
      keys.add(entry.key);
    });
    const files = {};
    const selected = Array.from(new Set(locales || []));
    if (includeSource !== false && !selected.includes('zh-Hans')) selected.unshift('zh-Hans');
    selected.forEach(locale => {
      if (!/^[a-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$/.test(locale)) throw new Error('语言标识不正确。');
      const values = Object.create(null);
      active.forEach(entry => { values[entry.key] = locale === 'zh-Hans' ? entry.source : translationText(entry, locale); });
      files[locale + '.json'] = JSON.stringify(values, null, 2) + '\n';
    });
    return files;
  }

  const crcTable = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let bit = 0; bit < 8; bit++) c = c & 1 ? 0xedb88320 ^ c >>> 1 : c >>> 1;
    crcTable[n] = c >>> 0;
  }
  function crc32(bytes) {
    let result = 0xffffffff;
    for (let i = 0; i < bytes.length; i++) result = crcTable[(result ^ bytes[i]) & 255] ^ result >>> 8;
    return (result ^ 0xffffffff) >>> 0;
  }

  function makeZip(files) {
    const entries = Object.entries(files || {}).map(([name, value]) => ({ name: encoder.encode(name), data: typeof value === 'string' ? encoder.encode(value) : new Uint8Array(value) }));
    if (entries.length > 65535) throw new Error('导出文件过多。');
    let localSize = 0;
    let centralSize = 0;
    entries.forEach(item => {
      if (!item.name.length || item.name.length > 65535) throw new Error('导出文件名不正确。');
      item.crc = crc32(item.data);
      item.offset = localSize;
      localSize += 30 + item.name.length + item.data.length;
      centralSize += 46 + item.name.length;
    });
    if (localSize + centralSize + 22 >= 0xffffffff) throw new Error('导出内容过大。');
    const zip = new Uint8Array(localSize + centralSize + 22);
    const view = new DataView(zip.buffer);
    let offset = 0;
    entries.forEach(item => {
      view.setUint32(offset, 0x04034b50, true);
      view.setUint16(offset + 4, 20, true);
      view.setUint16(offset + 6, 0x0800, true);
      view.setUint16(offset + 8, 0, true);
      view.setUint16(offset + 12, 0x0021, true);
      view.setUint32(offset + 14, item.crc, true);
      view.setUint32(offset + 18, item.data.length, true);
      view.setUint32(offset + 22, item.data.length, true);
      view.setUint16(offset + 26, item.name.length, true);
      zip.set(item.name, offset + 30);
      zip.set(item.data, offset + 30 + item.name.length);
      offset += 30 + item.name.length + item.data.length;
    });
    entries.forEach(item => {
      view.setUint32(offset, 0x02014b50, true);
      view.setUint16(offset + 4, 20, true);
      view.setUint16(offset + 6, 20, true);
      view.setUint16(offset + 8, 0x0800, true);
      view.setUint16(offset + 10, 0, true);
      view.setUint16(offset + 14, 0x0021, true);
      view.setUint32(offset + 16, item.crc, true);
      view.setUint32(offset + 20, item.data.length, true);
      view.setUint32(offset + 24, item.data.length, true);
      view.setUint16(offset + 28, item.name.length, true);
      view.setUint32(offset + 42, item.offset, true);
      zip.set(item.name, offset + 46);
      offset += 46 + item.name.length;
    });
    view.setUint32(offset, 0x06054b50, true);
    view.setUint16(offset + 8, entries.length, true);
    view.setUint16(offset + 10, entries.length, true);
    view.setUint32(offset + 12, centralSize, true);
    view.setUint32(offset + 16, localSize, true);
    return zip;
  }

  root.LangPackEngine = Object.freeze({ splitText, uniqueKey, parseDocument, translate, validate, makePackages, makeZip, placeholders, translationText, localeCodes: localeCodes.slice(), demoSources: rows.map(row => row[0]) });
})(typeof window !== 'undefined' ? window : globalThis);
