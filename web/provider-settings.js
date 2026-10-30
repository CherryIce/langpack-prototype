(function (root) {
  'use strict';
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  function badge(provider, value) {
    const saved = value.storage === 'delete-partial' ? '当前页已删除（旧副本未清）' : value.storage === 'deleted' ? '当前页已删除' : value.storage === 'partial' ? '当前页已保留（保存未完成）' : value.ready ? value.remembered ? '本机已保存' : '会话已保存' : provider === 'MyMemory' ? '匿名模式 · 私有 key 选填' : '尚未保存凭据';
    const labels = { valid: value.method === 'metadata' ? '授权检查通过（未试译）' : value.method === 'anonymous' ? '无需私有凭据' : '上次单字试译通过', invalid: '校验未通过', limited: '校验受限', unavailable: '尚未验证', unverified: '未验证' };
    return saved + ' · ' + (value.checking ? '正在验证' : labels[value.validationStatus] || '未验证');
  }
  function feedback(provider, value) {
    const saved = { local: '保存：已保存到本机浏览器。', session: '保存：仅保留在当前标签页会话。', partial: '保存：当前页已保留，但浏览器保存或旧副本清除未完成。', deleted: '保存：凭据已删除，旧校验结果已清除。', 'delete-partial': '保存：当前页凭据已删除，但浏览器旧副本未能清除，请清理站点数据。' };
    const storage = saved[value.storage] || (value.ready ? value.remembered ? saved.local : saved.session : provider === 'MyMemory' ? '保存：当前为匿名模式，没有私有凭据。' : '保存：尚未保存凭据。');
    const messages = {
      valid: value.method === 'metadata' ? '校验：授权检查通过，本次未试译。' : value.method === 'anonymous' ? '校验：匿名模式无需私有凭据；本次未检查服务、未试译。' : provider === 'MyMemory' ? '校验：上次单字试译通过，未核验私有词库权限。' : '校验：上次单字试译通过。',
      invalid: '校验：凭据或权限未通过，请检查已保存的配置。', limited: '校验：平台限制了本次验证，尚未确认翻译权限或可用性。',
      unavailable: '校验：网络或验证服务暂不可用，已保存配置尚未验证。', unverified: '校验：尚未验证已保存的配置。'
    };
    const message = value.checking ? '校验：正在验证当前已保存的配置，请勿重复提交。' : messages[value.validationStatus] || messages.unverified;
    const usage = !value.checking && value.method === 'translation' && value.billableCharacters === 1 ? '<p class="caption">本次校验最多涉及 1 字符试译，是否计费以平台实际规则为准。</p>' : '';
    const attemptedAt = value.checkedAt ? `<p class="caption">上次校验尝试：${esc(new Intl.DateTimeFormat('zh-CN', { month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false, timeZone: 'Asia/Shanghai' }).format(new Date(value.checkedAt)))}（仅本次会话）</p>` : '';
    return `<p class="provider-save-feedback">${esc(storage)}</p><p class="provider-validation-feedback" data-validation-status="${value.checking ? 'checking' : value.validationStatus || 'unverified'}">${esc(message)}</p>${usage}${attemptedAt}`;
  }
  function render({ settings, names, status }) {
    const order = settings.providerOrder;
    function card(provider) {
      const value = status(provider);
      const key = `<label class="field-label" for="provider-${provider}-key">API key</label><input class="field" type="password" id="provider-${provider}-key" autocomplete="off" value="" placeholder="${value.ready ? '已保存，留空保留原值' : '填写自己的 API key'}">`;
      const credential = (name, label) => `<label class="field-label" for="provider-${provider}-${name}">${label}</label><input class="field" type="password" id="provider-${provider}-${name}" autocomplete="off" value="" placeholder="${value.ready ? '已保存，留空保留原值' : '填写自己的凭据'}">`;
      let fields = key, note = '';
      if (provider === 'MyMemory') note = '可选：填写自己的私有词库 API key，仅通过本站代理发送，不放入浏览器请求网址。匿名翻译仍可不填；key 不代表更高的公共额度。';
      if (provider === 'ZTAITrans') {
        fields = `<label class="field-label" for="provider-${provider}-mode">授权方式</label><select class="field" id="provider-${provider}-mode"><option value="apiKey" ${!value.developer ? 'selected' : ''}>我自己的 API key</option><option value="developer" ${value.developer ? 'selected' : ''}>开发者口令</option></select>${key}<label class="field-label" for="provider-${provider}-tenant">Tenant ID（选填，仅自备 key）</label><input class="field" id="provider-${provider}-tenant" value="${esc(value.tenantId || '')}" autocomplete="off"><label class="field-label" for="provider-${provider}-developer">开发者口令</label><input class="field" type="password" id="provider-${provider}-developer" value="" autocomplete="off" placeholder="填写或更新开发者口令"><button class="text-button" data-action="verify-developer">验证开发者口令（不翻译）</button>`;
        note = '普通使用者需自备授权。开发者口令通过服务器验证后使用站点授权，站点 API key 不会显示或发给浏览器。';
      }
      if (provider === 'DeepL') {
        fields += `<label class="field-label" for="provider-${provider}-plan">接口计划</label><select class="field" id="provider-${provider}-plan"><option value="free" ${value.plan !== 'pro' ? 'selected' : ''}>免费接口（api-free）</option><option value="pro" ${value.plan === 'pro' ? 'selected' : ''}>标准接口（api）</option></select>`;
        note = '新 API Developer 总计 100 万字符、不重置；旧 API Free 每月 50 万字符，已不开放新购。此选项只选择 api-free 或 api 主机，请按账户文档选择入口，不会自动升级接口。';
      }
      if (provider === 'Azure') {
        fields += `<label class="field-label" for="provider-${provider}-region">资源区域（按 Azure 资源要求填写）</label><input class="field" id="provider-${provider}-region" value="${esc(value.region || '')}" autocomplete="off">`;
        note = 'F0 免费层每订阅每月 200 万字符，到限停止；其他资源层可能计费。';
      }
      if (provider === 'Google') note = '每月 50 万 NMT 字符抵扣，需要启用云端结算；超额可能计费，请在云控制台设置硬配额。';
      if (provider === 'Baidu') {
        fields = credential('appId', 'App ID') + credential('secretKey', 'Secret Key（密钥）');
        note = '本工具精确支持 32 种目标语言，部分扩展语种需要企业尊享版。标准版每月 5 万、高级版 100 万、尊享版 200 万字符；超额可能计费，请核对账户版本和官方规则。';
      }
      if (provider === 'Tencent') {
        fields = credential('secretId', 'Secret ID') + credential('secretKey', 'Secret Key') + `<label class="field-label" for="provider-${provider}-region">资源区域</label><input class="field" id="provider-${provider}-region" value="${esc(value.region || 'ap-guangzhou')}" autocomplete="off">`;
        note = '仅接入既有 TMT 账户，本工具开放经核实的 15 种目标语言。2026-10-1 起不再新发免费资源包，文本翻译不支持新用户；服务计划 2027-10-1 退市，请核对官方公告。';
      }
      if (provider === 'Alibaba') {
        fields = credential('accessKeyId', 'AccessKey ID') + credential('accessKeySecret', 'AccessKey Secret');
        note = '固定使用 cn-hangzhou 通用版，本工具精确支持 29 种目标语言。主账号每月 100 万字符，子账号共享；超额按每百万字符 50 元后付费，请核对用量与账单。';
      }
      const links = { DeepL: 'https://www.deepl.com/pro-api', Azure: 'https://azure.microsoft.com/pricing/details/cognitive-services/translator/', Google: 'https://cloud.google.com/translate/pricing', Baidu: 'https://api.fanyi.baidu.com/doc/13', Tencent: 'https://cloud.tencent.com/announce/detail/2448', Alibaba: 'https://help.aliyun.com/zh/machine-translation/product-overview/pricing-of-machine-translation-general-purpose-edition' };
      return `<details class="provider-card" ${value.storage ? 'open' : ''}><summary><strong>${provider}</strong><span id="provider-${provider}-badge" class="badge ${value.validationStatus === 'valid' ? 'ok' : 'neutral'}">${badge(provider, value)}</span></summary><div class="provider-fields">${fields}<p class="caption">${note}${links[provider] ? ` <a href="${links[provider]}" target="_blank" rel="noopener noreferrer">官方规则</a>` : ''}</p><label class="provider-remember"><input type="checkbox" id="provider-${provider}-remember" ${value.remembered ? 'checked' : ''}><span>记住到本机浏览器（不勾选则仅当前标签页会话）</span></label><div class="flex wrap"><button id="provider-${provider}-save" class="btn small-btn soft" data-action="save-provider-credentials" data-provider="${provider}" ${value.checking ? 'disabled' : ''}>${value.checking ? '正在验证…' : '保存并校验'}</button><button id="provider-${provider}-validate" class="btn small-btn" data-action="validate-provider" data-provider="${provider}" ${value.checking || !value.ready && provider !== 'MyMemory' ? 'disabled' : ''}>重新验证</button><button class="btn small-btn" data-action="delete-provider-credentials" data-provider="${provider}">删除凭据</button></div><p class="caption">保存会验证；部分平台会产生 1 字符试译用量。只更新保存方式时可沿用当前会话的校验结果。</p><div id="provider-${provider}-feedback" class="provider-feedback" role="status" aria-live="polite">${feedback(provider, value)}</div></div></details>`;
    }
    return `<div class="settings-grid"><section class="panel"><div class="panel-head"><h2>导出与平台顺序</h2></div><div class="panel-body"><div class="settings-line"><div><h3>默认包含源语言包</h3></div><input class="toggle" id="setting-source" type="checkbox" aria-label="默认包含源语言包" ${settings.includeSource ? 'checked' : ''}></div><div class="settings-line"><div><h3>格式化 JSON</h3></div><input class="toggle" id="setting-pretty" type="checkbox" aria-label="默认格式化 JSON" ${settings.pretty ? 'checked' : ''}></div><label class="field-label" for="primary-provider">首选翻译平台</label><select class="field" id="primary-provider">${names.map(provider => `<option value="${provider}" ${order[0] === provider ? 'selected' : ''}>${provider}</option>`).join('')}</select><p class="caption">先使用首选平台，再按下列启用顺序使用备用。切换配置会暂停正在执行的任务。</p><div class="provider-order">${[...order, ...names.filter(provider => !order.includes(provider))].map(provider => `<div class="provider-order-row"><label><input type="checkbox" data-provider-enabled="${provider}" ${order.includes(provider) ? 'checked' : ''}>${provider}${order[0] === provider ? ' · 首选' : ''}</label><span class="grow"></span><button class="text-button" data-action="move-provider" data-provider="${provider}" data-direction="-1" ${order.indexOf(provider) <= 0 ? 'disabled' : ''}>上移</button><button class="text-button" data-action="move-provider" data-provider="${provider}" data-direction="1" ${order.indexOf(provider) < 0 || order.indexOf(provider) === order.length - 1 ? 'disabled' : ''}>下移</button></div>`).join('')}</div><label class="provider-remember"><input type="checkbox" id="provider-fallback" ${settings.providerFallback ? 'checked' : ''}><span>仅在额度耗尽或不支持语言时，自动使用已启用的备用平台</span></label><div class="notice"><span>鉴权或配置错误会停止。网络错误和普通限流只有限重试，不会改用另一平台消费额度。已保存的有效译文继续复用，主动重译才请求新结果。</span></div><div class="settings-line"><div><h3>恢复初始示例</h3><p>清除项目、任务、导出及本机平台凭据</p></div><button class="btn small-btn" data-action="reset-confirm">重置</button></div></div></section><section class="panel"><div class="panel-head"><h2>自备平台凭据</h2><span class="badge ok">${names.length} 个平台</span></div><div class="panel-body"><div class="notice"><span>凭据只放在独立的本机会话或本机保存区，不进入项目、任务、语言包或浏览器项目备份。使用时通过当前站点发送给所选平台，文档文件不上传。</span></div><div class="provider-card"><h3>MyMemory · 无需 API key</h3><label class="field-label" for="translation-email">联系邮箱（选填）</label><input class="field" type="email" id="translation-email" value="${esc(settings.translationEmail || '')}" placeholder="填写你自己的有效联系邮箱" maxlength="254" autocomplete="email"><p class="caption"><a href="https://mymemory.translated.net/doc/usagelimits.php" target="_blank" rel="noopener noreferrer">官方额度规则</a>；邮箱随 MyMemory 请求发送。</p><div id="settings-error" class="error-text" role="alert"></div><button class="btn small-btn soft" data-action="save-translation-settings">保存翻译设置</button></div>${names.map(card).join('')}</div></section></div>`;
  }
  root.LangPackProviderSettings = Object.freeze({ render, badge, feedback });
})(typeof window !== 'undefined' ? window : globalThis);
