(function () {
  'use strict';

  const COLUMNS = 11;
  const SVG_NS = 'http://www.w3.org/2000/svg';
  const VERDICT_LABEL = {
    'better': 'Better',
    'worse': 'Worse',
    'less-effort': 'Less effort',
    'no-change': 'No change',
    'not-comparable': 'Not comparable'
  };

  const data = window.EVAL_DASHBOARD;
  const body = document.querySelector('#results tbody');
  const expanded = new Set();

  function appendChildren(el, children) {
    for (const child of children.flat()) {
      if (child === null || child === undefined || child === false) continue;
      el.append(child instanceof Node ? child : document.createTextNode(String(child)));
    }
  }

  function element(create, tag, props, children) {
    const el = create(tag);
    for (const [key, value] of Object.entries(props || {})) {
      if (value === null || value === undefined || value === false) continue;
      if (key === 'class') el.setAttribute('class', value);
      else if (key.startsWith('on')) el.addEventListener(key.slice(2), value);
      else el.setAttribute(key, value === true ? '' : String(value));
    }
    appendChildren(el, children);
    return el;
  }

  const h = (tag, props, ...children) => element((t) => document.createElement(t), tag, props, children);
  const svg = (tag, props, ...children) => element((t) => document.createElementNS(SVG_NS, t), tag, props, children);

  const breakable = (text) => String(text).split(/(?<=[:/])/).flatMap((part, i) => (i === 0 ? [part] : [h('wbr'), part]));
  const percent = (ratio) => Math.round(ratio * 100) + '%';
  const one = (value) => value.toFixed(1);
  const seconds = (value) => Math.round(value) + ' s';
  const tokens = (value) => (value >= 10000 ? Math.round(value / 1000) + 'k' : Math.round(value).toString());
  const signed = (value, text) => (value > 0 ? '+' : '') + text;
  const day = (comparison) => comparison.date || 'unknown date';
  const monthDay = (comparison) => (comparison.date ? comparison.date.slice(5) : '?');

  function showMessage(text) {
    document.getElementById('freshness').textContent = text;
    document.querySelector('.table-wrap').hidden = true;
    document.getElementById('filters').hidden = true;
  }

  function commitLink(sha, text) {
    if (typeof sha !== 'string' || !/^[0-9a-f]{7,40}$/i.test(sha)) return text || 'unknown';
    const base = data && typeof data.repoUrl === 'string' && /^https:\/\/\S+$/.test(data.repoUrl) ? data.repoUrl.replace(/\/+$/, '') : null;
    if (!base) return text || sha.slice(0, 7);
    return h('a', { href: base + '/commit/' + sha }, text || sha.slice(0, 7));
  }

  function renderHeader() {
    const results = new Set();
    let newest = '';
    for (const skill of data.skills) {
      for (const task of skill.tasks) {
        for (const target of task.targets) {
          for (const c of target.history) {
            results.add(skill.skill + '/' + c.runId);
            if (c.runId > newest) newest = c.runId;
          }
        }
      }
    }
    const freshness = document.getElementById('freshness');
    freshness.textContent = '';
    appendChildren(freshness, [
      'Generated ', h('time', { datetime: data.generatedAt }, data.generatedAt.replace('T', ' ').replace('Z', ' UTC')),
      ' from commit ', commitLink(data.commit, data.commit ? data.commit.slice(0, 7) : 'unknown'), '. ',
      results.size === 0 ? 'No result sets yet.' : results.size + ' result set' + (results.size === 1 ? '' : 's') + ', newest ' + newest + '.'
    ]);

    const t = data.thresholds;
    const rules = document.getElementById('rules');
    const lines = [
      ['Not comparable', 'a mode has no counted run, or no counted run has a graded check, so there is no pass rate to compare.'],
      ['Better', 'pass rate is higher by ' + Math.round(t.PassRateDelta * 100) + ' points or more.'],
      ['Worse', 'pass rate is lower by ' + Math.round(t.PassRateDelta * 100) + ' points or more.'],
      ['Less effort', 'pass rate is within ' + Math.round(t.PassRateDelta * 100) + ' points, and mean failed builds are lower by ' + t.FailedBuildsDrop + ' or more, or mean turns are lower by ' + Math.round(t.TurnsDropRatio * 100) + '% or more.'],
      ['No change', 'all other cases.'],
      ['Too few runs', 'a mode has fewer than ' + t.MinCountedRuns + ' counted runs. The verdict can change with more runs.']
    ];
    rules.textContent = '';
    for (const [name, text] of lines) rules.append(h('li', null, h('strong', null, name), ': ', text));
  }

  function fillFilters() {
    const skillSelect = document.getElementById('filter-skill');
    const agentSelect = document.getElementById('filter-agent');
    const agents = new Set();
    for (const skill of data.skills) {
      skillSelect.append(h('option', { value: skill.skill }, skill.skill));
      for (const task of skill.tasks) for (const target of task.targets) agents.add(target.agent);
    }
    for (const agent of [...agents].sort()) agentSelect.append(h('option', { value: agent }, agent));
  }

  function currentFilters() {
    return {
      skill: document.getElementById('filter-skill').value,
      agent: document.getElementById('filter-agent').value,
      text: document.getElementById('filter-text').value.trim().toLowerCase()
    };
  }

  function matchesTarget(skill, task, target, f) {
    if (f.agent && target.agent !== f.agent) return false;
    if (!f.text) return true;
    return [skill.skill, task.task, target.target, target.resolvedModel].some((s) => String(s).toLowerCase().includes(f.text));
  }

  function filterTree(f) {
    const narrowed = Boolean(f.agent || f.text);
    const skills = [];
    for (const skill of data.skills) {
      if (f.skill && skill.skill !== f.skill) continue;
      const tasks = skill.tasks
        .map((task) => ({ task: task.task, targets: task.targets.filter((target) => matchesTarget(skill, task, target, f)) }))
        .filter((task) => !narrowed || task.targets.length > 0);
      if (narrowed && tasks.length === 0) continue;
      skills.push({ skill: skill.skill, description: skill.description, tasks });
    }
    return skills;
  }

  function changeCell(without, withSkill, format, relative) {
    if (without === null || withSkill === null) return h('td', { class: 'num' }, '-');
    const diff = withSkill - without;
    let note;
    if (relative && without > 0) note = signed(diff, Math.round((diff / without) * 100) + '%');
    else if (!relative) note = signed(diff, one(diff));
    const flat = Math.abs(diff) < 0.05 * Math.max(Math.abs(without), 1);
    return h('td', { class: 'num' }, format(without) + ' to ' + format(withSkill),
      note ? h('span', { class: 'change ' + (flat ? 'flat' : diff < 0 ? 'good' : 'bad') }, note) : null);
  }

  function passRateCell(c) {
    if (c.without.passRate === null || c.with.passRate === null) {
      const only = c.with.passRate !== null ? percent(c.with.passRate) : c.without.passRate !== null ? percent(c.without.passRate) : '-';
      return h('td', { class: 'num' }, only);
    }
    const delta = Math.round((c.with.passRate - c.without.passRate) * 100);
    return h('td', { class: 'num' }, percent(c.without.passRate) + ' to ' + percent(c.with.passRate),
      h('span', { class: 'delta ' + (delta > 0 ? 'good' : delta < 0 ? 'bad' : 'flat') }, signed(delta, delta + ' points')));
  }

  function verdictCell(verdict) {
    return h('td', null,
      h('span', { class: 'badge v-' + verdict.direction }, VERDICT_LABEL[verdict.direction] || verdict.direction),
      verdict.underpowered ? h('span', { class: 'tag' }, 'too few runs') : null,
      h('div', { class: 'reason' }, verdict.reason));
  }

  function resultSetCell(c) {
    return h('td', { class: 'num' }, day(c), ' ', commitLink(c.skillCommit, c.skillCommit ? c.skillCommit.slice(0, 7) : 'no commit'),
      c.skillDirty ? h('span', { class: 'dirty', title: 'The skill folder, its eval folder, or evals/lib had uncommitted changes when a run started.' }, ' dirty') : null,
      h('div', { class: 'sub' }, c.runId));
  }

  function matrixTable(c) {
    const rows = c.checks.map((check) => {
      const w = check.with;
      const wo = check.without;
      const rateWith = w.total ? w.passed / w.total : null;
      const rateWithout = wo.total ? wo.passed / wo.total : null;
      let status = '';
      let cls = '';
      if (rateWith !== null && rateWithout !== null) {
        if (rateWith > rateWithout) { status = 'fixed by the skill'; cls = 'fixes'; }
        else if (rateWith < rateWithout) { status = 'broken by the skill'; cls = 'breaks'; }
      }
      const cell = (x) => (x.total ? x.passed + '/' + x.total : '-');
      return h('tr', { class: cls }, h('td', null, check.text), h('td', { class: 'num' }, cell(wo)), h('td', { class: 'num' }, cell(w)), h('td', null, status));
    });
    return h('table', { class: 'matrix' },
      h('thead', null, h('tr', null, h('th', { scope: 'col' }, 'Check'), h('th', { scope: 'col' }, 'Without'), h('th', { scope: 'col' }, 'With'), h('th', { scope: 'col' }, 'Effect'))),
      h('tbody', null, rows));
  }

  function trendChart(history) {
    const width = 300;
    const height = 130;
    const pad = { left: 34, right: 12, top: 10, bottom: 24 };
    const innerW = width - pad.left - pad.right;
    const innerH = height - pad.top - pad.bottom;
    const x = (i) => pad.left + (history.length === 1 ? innerW / 2 : (innerW * i) / (history.length - 1));
    const y = (rate) => pad.top + innerH * (1 - rate);
    const label = 'Pass rate by result set. ' + history.map((c) => day(c) + ': without ' +
      (c.without.passRate === null ? 'none' : percent(c.without.passRate)) + ', with ' + (c.with.passRate === null ? 'none' : percent(c.with.passRate))).join('; ') + '.';
    const chart = svg('svg', { class: 'trend', viewBox: '0 0 ' + width + ' ' + height, width, role: 'img', 'aria-label': label }, svg('title', null, label));
    for (const tick of [0, 0.5, 1]) {
      chart.append(svg('line', { class: 'grid', x1: pad.left, x2: width - pad.right, y1: y(tick), y2: y(tick) }));
      chart.append(svg('text', { x: pad.left - 4, y: y(tick) + 3, 'text-anchor': 'end' }, percent(tick)));
    }
    history.forEach((c, i) => {
      const anchor = history.length === 1 ? 'middle' : i === 0 ? 'start' : i === history.length - 1 ? 'end' : 'middle';
      chart.append(svg('text', { x: x(i), y: height - 8, 'text-anchor': anchor }, monthDay(c)));
    });
    for (const mode of ['without', 'with']) {
      const points = history.map((c, i) => ({ i, rate: c[mode].passRate })).filter((p) => p.rate !== null);
      if (points.length > 1) {
        chart.append(svg('polyline', {
          class: 'line ' + mode,
          'stroke-dasharray': mode === 'without' ? '5 3' : null,
          points: points.map((p) => x(p.i) + ',' + y(p.rate)).join(' ')
        }));
      }
      for (const p of points) {
        chart.append(mode === 'with'
          ? svg('circle', { class: mode, cx: x(p.i), cy: y(p.rate), r: 4 })
          : svg('rect', { class: mode, x: x(p.i) - 3.5, y: y(p.rate) - 3.5, width: 7, height: 7 }));
      }
    }
    return h('div', null, chart, h('p', { class: 'legend' }, 'Pass rate over result sets. Solid line with circles: with the skill. Dashed line with squares: without the skill.'));
  }

  function detailRow(entry) {
    return h('tr', { class: 'detail' }, h('td', { colspan: COLUMNS },
      h('div', { class: 'detail-grid' },
        h('div', { class: 'table-scroll' }, matrixTable(entry.latest)),
        trendChart(entry.history))));
  }

  function targetRows(skill, task, entry) {
    const c = entry.latest;
    const key = [skill, task, entry.target, entry.resolvedModel].join('\u0001');
    const open = expanded.has(key);
    const detailId = 'detail-' + rowCounter++;
    const toggle = h('button', {
      type: 'button',
      class: 'toggle',
      'aria-expanded': String(open),
      'aria-controls': detailId,
      'aria-label': 'Show checks and trend for ' + entry.target,
      onclick: (event) => {
        const row = event.currentTarget.closest('tr');
        const next = row.nextElementSibling;
        if (expanded.has(key)) {
          expanded.delete(key);
          next.remove();
          event.currentTarget.setAttribute('aria-expanded', 'false');
          event.currentTarget.textContent = '+';
        } else {
          expanded.add(key);
          const detail = detailRow(entry);
          detail.id = detailId;
          row.after(detail);
          event.currentTarget.setAttribute('aria-expanded', 'true');
          event.currentTarget.textContent = '-';
        }
      }
    }, open ? '-' : '+');
    const w = c.with;
    const wo = c.without;
    const row = h('tr', { class: entry.superseded ? 'superseded' : null },
      h('td', null, h('div', { class: 'target-name' }, toggle,
        h('div', null, h('span', { class: 'label' }, breakable(entry.target)), h('span', { class: 'model' }, breakable(c.resolvedModel || entry.resolvedModel)),
          entry.superseded ? h('span', { class: 'older', title: 'A later result set ran this target on a different model.' }, 'older model') : null))),
      h('td', { class: 'num' }, w.runs ? w.counted + '/' + w.runs : '-'),
      passRateCell(c),
      h('td', { class: 'num' }, wo.counted ? wo.allPassRuns + '/' + wo.counted : '-', ' to ', w.counted ? w.allPassRuns + '/' + w.counted : '-'),
      changeCell(wo.meanTurns, w.meanTurns, one, true),
      changeCell(wo.meanFailedBuilds, w.meanFailedBuilds, one, false),
      changeCell(wo.meanSeconds, w.meanSeconds, seconds, true),
      changeCell(wo.meanTokens, w.meanTokens, tokens, true),
      h('td', { class: 'num' }, w.counted + ' / ' + wo.counted),
      verdictCell(c.verdict),
      resultSetCell(c));
    return open ? [row, Object.assign(detailRow(entry), { id: detailId })] : [row];
  }

  function groupHeader(cls, label, extra) {
    return h('tr', { class: cls }, h('th', { colspan: COLUMNS, scope: 'colgroup' }, h('div', { class: 'group-label' }, label, extra)));
  }

  let rowCounter = 0;

  function render() {
    const tree = filterTree(currentFilters());
    body.textContent = '';
    rowCounter = 0;
    let shown = 0;
    for (const skill of tree) {
      const targetCount = skill.tasks.reduce((n, task) => n + task.targets.length, 0);
      const taskNames = skill.tasks.map((task) => task.task).join(', ');
      body.append(groupHeader('skill-row', skill.skill, h('span', { class: 'desc', title: skill.description }, skill.description)));
      shown++;
      if (targetCount === 0) {
        body.append(h('tr', { class: 'empty-row' }, h('td', { colspan: COLUMNS }, 'No results yet. Tasks: ' + (taskNames || 'none') + '.')));
        continue;
      }
      for (const task of skill.tasks) {
        body.append(groupHeader('task-row', 'Task: ' + task.task));
        if (task.targets.length === 0) {
          body.append(h('tr', { class: 'empty-row' }, h('td', { colspan: COLUMNS }, 'No results yet.')));
          continue;
        }
        for (const entry of task.targets) body.append(...targetRows(skill.skill, task.task, entry));
      }
    }
    document.getElementById('empty').hidden = shown > 0;
  }

  if (!data || !Array.isArray(data.skills)) {
    showMessage('The result data did not load. Check that data.js is next to this page.');
    return;
  }
  renderHeader();
  fillFilters();
  document.getElementById('filters').addEventListener('input', render);
  document.getElementById('filters').addEventListener('submit', (event) => event.preventDefault());
  render();
}());
