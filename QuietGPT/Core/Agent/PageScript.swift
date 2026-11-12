enum PageScript {
    static let snapshot = """
    document.querySelectorAll('[data-quiet]').forEach(e => e.removeAttribute('data-quiet'));
    const clean = s => (s || '').replace(/\\s+/g, ' ').trim().slice(0, 80);
    const query = 'input,select,textarea,button,a[href],[role=button],[role=link],[role=option],[role=tab],[role=menuitem],[role=combobox],[role=checkbox],[role=radio]';
    const found = [];
    for (const el of document.querySelectorAll(query)) {
        const type = (el.getAttribute('type') || '').toLowerCase();
        if (el.disabled || type === 'hidden') continue;
        if (el.checkVisibility && !el.checkVisibility({ visibilityProperty: true })) continue;
        const box = el.getBoundingClientRect();
        if (box.width < 4 || box.height < 4) continue;
        const tag = el.tagName.toLowerCase();
        const role = el.getAttribute('role') || '';
        let kind = 'button';
        if (tag === 'select') kind = 'list';
        else if (tag === 'textarea') kind = 'field';
        else if (tag === 'input') kind = ['button', 'submit', 'reset', 'image'].includes(type) ? 'button' : (['checkbox', 'radio'].includes(type) ? 'check' : 'field');
        else if (role === 'checkbox' || role === 'radio') kind = 'check';
        else if (tag === 'a' || role === 'link') kind = 'link';
        const image = el.querySelector ? el.querySelector('img[alt]') : null;
        const own = kind === 'field' || kind === 'list' ? '' : (el.innerText || el.value);
        const label = clean(el.getAttribute('aria-label') || (el.labels && el.labels[0] && el.labels[0].innerText) || el.placeholder || own || el.title || el.getAttribute('name') || (image ? image.alt : ''));
        if (!label && kind === 'link') continue;
        const auto = (el.getAttribute('autocomplete') || '').toLowerCase();
        const secret = type === 'password' || auto.startsWith('cc-') || auto === 'one-time-code';
        let value = '';
        if (kind === 'list') value = clean(el.selectedOptions[0] ? el.selectedOptions[0].text : '');
        else if (kind === 'check') value = (el.checked || el.getAttribute('aria-checked') === 'true') ? 'on' : 'off';
        else if (kind === 'field' && !secret) value = clean(el.value);
        const options = kind === 'list' ? Array.from(el.options).slice(0, 20).map(o => clean(o.text)).filter(Boolean) : [];
        const inView = box.bottom > 0 && box.top < innerHeight;
        found.push({ el, kind, type, label, value, options, secret, rank: (kind === 'link' ? 2 : 0) + (inView ? 0 : 1) });
    }
    found.sort((a, b) => a.rank - b.rank);
    const elements = found.slice(0, limit).map((f, i) => {
        f.el.setAttribute('data-quiet', String(i + 1));
        return { id: i + 1, kind: f.kind, type: f.type, label: f.label, value: f.value, options: f.options, secret: f.secret };
    });
    const heads = Array.from(document.querySelectorAll('h1,h2,h3,[role=alert],[role=status]'))
        .filter(e => !e.checkVisibility || e.checkVisibility())
        .map(e => clean(e.innerText)).filter(Boolean);
    return JSON.stringify({ title: clean(document.title), url: location.href, text: heads.join(' / ').slice(0, textLimit), elements });
    """

    static let act = """
    const el = document.querySelector('[data-quiet="' + id + '"]');
    if (!el) return 'missing';
    const fire = name => el.dispatchEvent(new Event(name, { bubbles: true }));
    if (verb === 'mark') {
        el.scrollIntoView({ block: 'center' });
        el.dataset.quietOutline = el.style.outline;
        el.style.outline = '3px solid #0A84FF';
        el.style.outlineOffset = '2px';
        return 'ok';
    }
    if (verb === 'unmark') {
        el.style.outline = el.dataset.quietOutline || '';
        el.style.outlineOffset = '';
        return 'ok';
    }
    if (verb === 'tap') {
        el.click();
        return 'ok';
    }
    if (verb === 'type') {
        const isArea = el instanceof HTMLTextAreaElement;
        if (!isArea && !(el instanceof HTMLInputElement)) return 'not a field';
        el.focus();
        const proto = isArea ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
        Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, text);
        fire('input');
        fire('change');
        return el.value === text ? 'ok' : 'the field did not accept the text';
    }
    if (verb === 'select') {
        if (!(el instanceof HTMLSelectElement)) return 'not a list';
        const want = text.trim().toLowerCase();
        const all = Array.from(el.options);
        const option = all.find(o => o.text.trim().toLowerCase() === want) || all.find(o => o.text.toLowerCase().includes(want));
        if (!option) return 'no such option';
        el.value = option.value;
        fire('input');
        fire('change');
        return 'ok';
    }
    return 'unknown';
    """

    static let scroll = "window.scrollBy({ top: innerHeight * 0.8, behavior: 'instant' }); return 'ok';"
}
