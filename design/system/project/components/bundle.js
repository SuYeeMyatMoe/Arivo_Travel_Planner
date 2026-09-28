/* @ds-bundle: {"format":4,"namespace":"Arivo","components":[{"name":"Button"},{"name":"ProvenanceTag"},{"name":"StatusChip"},{"name":"StopCard"},{"name":"TripSpine"},{"name":"PulseBadge"},{"name":"ChangeDiff"},{"name":"BudgetGauge"},{"name":"LocationFitMeter"},{"name":"BoardingPassCard"},{"name":"PriceBreakdown"},{"name":"CrewConstellation"}]} */
(function () {
  var React = window.React;
  var h = React.createElement;

  function cx() {
    return Array.prototype.filter.call(arguments, Boolean).join(' ');
  }
  function money(amount, currency) {
    var cur = currency || 'MYR';
    var sym = cur === 'MYR' ? 'RM' : cur === 'JPY' ? '¥' : cur === 'USD' ? '$' : cur + ' ';
    var digits = cur === 'JPY' ? 0 : Math.abs(amount) % 1 ? 2 : 0;
    var n = Math.abs(amount).toLocaleString('en-US', { minimumFractionDigits: digits, maximumFractionDigits: digits });
    return (amount < 0 ? '−' : '') + sym + (sym.length > 1 && sym !== cur + ' ' ? ' ' : '') + n;
  }
  function signedMoney(amount, currency) {
    return (amount > 0 ? '+' : '') + money(amount, currency);
  }
  function Icon(props) {
    var paths = {
      check: 'M4 10.5l4 4 8-9',
      lock: 'M6 9V7a4 4 0 118 0v2M5 9h10v8H5z',
      arrow: 'M4 10h11M11 6l4 4-4 4',
      plus: 'M10 4v12M4 10h12',
      minus: 'M4 10h12',
      warn: 'M10 3l8 14H2zM10 8v4M10 14.5v.5',
      walk: 'M11 4a1.2 1.2 0 100 .1M9 17l2-5 2 2v3M8 11l2-4 3 3 2 1',
      train: 'M6 3h8a2 2 0 012 2v8a2 2 0 01-2 2H6a2 2 0 01-2-2V5a2 2 0 012-2zM4 10h12M7 15l-2 3M13 15l2 3',
      plane: 'M2 11l16-6-5 12-3-5z',
      bed: 'M3 15V6M3 11h14v4M17 15v-3a3 3 0 00-3-3H9v2',
      bus: 'M5 3h10a1 1 0 011 1v10H4V4a1 1 0 011-1zM4 9h12M6 14v2M14 14v2',
      pulse: 'M2 10h4l2-5 3 10 2-5h5',
      clock: 'M10 3a7 7 0 110 14 7 7 0 010-14zM10 6v4l3 2',
      dot: 'M10 8a2 2 0 110 4 2 2 0 010-4z'
    };
    return h('svg', { className: cx('av-icon', props.className), viewBox: '0 0 20 20', width: props.size || 16, height: props.size || 16, 'aria-hidden': 'true', focusable: 'false' },
      h('path', { d: paths[props.name] || paths.dot, fill: 'none', stroke: 'currentColor', strokeWidth: 1.8, strokeLinecap: 'round', strokeLinejoin: 'round' }));
  }

  // ------------------------------------------------------------ Button
  function Button(props) {
    var variant = props.variant || 'primary';
    var rest = Object.assign({}, props);
    delete rest.variant; delete rest.icon; delete rest.children; delete rest.className;
    return h('button', Object.assign({ type: 'button' }, rest, { className: cx('av-btn', 'av-btn--' + variant, props.className) }),
      props.icon ? h(Icon, { name: props.icon }) : null,
      h('span', null, props.children));
  }

  // ------------------------------------------------------------ ProvenanceTag
  var PROV = { live: 'LIVE', est: 'EST.', you: 'YOU' };
  var PROV_SPOKEN = { live: 'live data', est: 'Arivo estimate', you: 'your input' };
  function ProvenanceTag(props) {
    var kind = props.kind || 'est';
    var spoken = PROV_SPOKEN[kind] + (props.source ? ' from ' + props.source : '') + (props.updated ? ', updated ' + props.updated : '');
    return h('span', { className: 'av-prov av-prov--' + kind, title: spoken, 'aria-label': spoken, role: 'note' }, PROV[kind]);
  }

  // ------------------------------------------------------------ StatusChip
  var STATUS = {
    confirmed: { icon: 'check', label: 'Confirmed' },
    pending: { icon: 'clock', label: 'Confirming' },
    failed: { icon: 'warn', label: 'Failed' },
    cancelled: { icon: 'minus', label: 'Cancelled' },
    sandbox: { icon: 'dot', label: 'Sandbox' },
    offline: { icon: 'lock', label: 'Saved offline' },
    closed: { icon: 'warn', label: 'Closed today' },
    booked: { icon: 'lock', label: 'Booked' }
  };
  function StatusChip(props) {
    var s = STATUS[props.tone] || STATUS.pending;
    return h('span', { className: 'av-chip av-chip--' + props.tone }, h(Icon, { name: s.icon, size: 14 }), props.children || s.label);
  }

  // ------------------------------------------------------------ StopCard
  function StopCard(props) {
    var status = props.status || 'planned';
    var spoken = [props.time, props.place, props.duration, props.leg, props.price, props.reason].filter(Boolean).join(', ');
    return h('article', { className: cx('av-stop', 'av-stop--' + status), 'aria-label': spoken, style: props.dayColor ? { '--av-day': 'var(--' + props.dayColor + ')' } : null },
      h('div', { className: 'av-stop__time mono-m' }, props.time),
      h('div', { className: 'av-stop__body' },
        h('div', { className: 'av-stop__head' },
          h('h3', { className: 'av-stop__place title-m' }, props.place),
          status === 'booked' ? h(StatusChip, { tone: 'booked' }) : null,
          status === 'closed' ? h(StatusChip, { tone: 'closed' }) : null,
          status === 'done' ? h(StatusChip, { tone: 'confirmed' }, 'Done') : null),
        h('div', { className: 'av-stop__meta caption' },
          props.duration ? h('span', null, props.duration) : null,
          props.leg ? h('span', null, props.leg) : null,
          props.price ? h('span', { className: 'av-stop__price mono-s' }, props.price, props.provenance ? h(ProvenanceTag, { kind: props.provenance, source: props.source }) : null) : null),
        props.reason ? h('p', { className: 'av-stop__why body-m' }, props.reason) : null));
  }

  // ------------------------------------------------------------ TripSpine
  var MODE_ICON = { walk: 'walk', train: 'train', bus: 'bus', flight: 'plane' };
  function TripSpine(props) {
    var color = props.routeColor || 'route-1';
    var stops = props.stops || [];
    return h('section', { className: 'av-spine', style: { '--av-day': 'var(--' + color + ')' }, 'aria-label': props.title },
      h('header', { className: 'av-spine__head' },
        h('span', { className: 'av-spine__day label' }, props.day),
        h('h2', { className: 'av-spine__title display-m' }, props.title)),
      h('ol', { className: 'av-spine__list' },
        stops.map(function (s, i) {
          return h('li', { key: i, className: 'av-spine__item' },
            h('span', { className: cx('av-spine__node', s.status === 'next' && 'is-next') }),
            h(StopCard, Object.assign({}, s, { dayColor: color })),
            s.legAfter ? h('div', { className: 'av-spine__leg caption' }, h(Icon, { name: MODE_ICON[s.legAfter.mode] || 'arrow', size: 14 }), s.legAfter.label) : null);
        })));
  }

  // ------------------------------------------------------------ PulseBadge
  function PulseBadge(props) {
    var evidence = props.evidence || [];
    var max = evidence.reduce(function (m, e) { return Math.max(m, e.weight); }, 0) || 1;
    return h('div', { className: cx('av-pulse', props.expanded && 'is-expanded') },
      h('div', { className: 'av-pulse__badge' },
        h(Icon, { name: 'pulse', size: 16 }),
        h('span', { className: 'av-pulse__score mono-m', 'aria-label': 'Trend Pulse ' + props.score + ' of 100' }, props.score),
        h('span', { className: 'label' }, props.label)),
      props.expanded ? h('div', { className: 'av-pulse__evidence' },
        h('ul', { className: 'av-pulse__bars' }, evidence.map(function (e) {
          return h('li', { key: e.name, className: 'av-pulse__bar' },
            h('span', { className: 'caption' }, e.name),
            h('span', { className: 'av-pulse__track' }, h('span', { className: 'av-pulse__fill', style: { width: (e.weight / max) * 100 + '%' } })),
            h('span', { className: 'mono-s' }, e.value));
        })),
        props.facts ? h('ul', { className: 'av-pulse__facts body-m' }, props.facts.map(function (f) { return h('li', { key: f }, f); })) : null,
        props.updated ? h('p', { className: 'caption av-muted' }, props.sources + ' independent sources · updated ' + props.updated) : null) : null);
  }

  // ------------------------------------------------------------ ChangeDiff
  function ChangeDiff(props) {
    var g = props.groups || {};
    var sections = [
      ['kept', 'Kept', 'check'],
      ['moved', 'Moved', 'arrow'],
      ['removed', 'Removed', 'minus'],
      ['added', 'Added', 'plus']
    ];
    var counts = sections.map(function (s) { return (g[s[0]] || []).length + ' ' + s[1].toLowerCase(); }).join(', ');
    return h('section', { className: 'av-diff', 'aria-label': 'Plan changes: ' + counts },
      h('header', { className: 'av-diff__head' },
        h('div', null, h('span', { className: 'caption av-muted' }, 'Time'), h('div', { className: 'mono-l' }, props.timeDelta)),
        h('div', null, h('span', { className: 'caption av-muted' }, 'Budget'), h('div', { className: cx('mono-l', props.budgetDelta < 0 ? 'av-good' : 'av-bad') }, signedMoney(props.budgetDelta, props.currency)))),
      sections.map(function (s) {
        var items = g[s[0]] || [];
        if (!items.length) return null;
        return h('div', { key: s[0], className: 'av-diff__group av-diff__group--' + s[0] },
          h('h4', { className: 'label' }, h(Icon, { name: s[2], size: 14 }), s[1], h('span', { className: 'av-diff__count mono-s' }, items.length)),
          h('ul', null, items.map(function (it, i) {
            return h('li', { key: i, className: 'av-diff__item' },
              h('span', { className: 'av-diff__name body-m' }, it.name),
              it.from ? h('span', { className: 'mono-s av-muted' }, it.from + ' → ' + it.to) : null,
              it.reason ? h('span', { className: 'caption av-muted' }, it.reason) : null,
              it.detail ? h('span', { className: 'caption av-muted' }, it.detail) : null);
          })));
      }));
  }

  // ------------------------------------------------------------ BudgetGauge
  function arc(r, start, end) {
    var a0 = (start - 0.25) * Math.PI * 2, a1 = (end - 0.25) * Math.PI * 2;
    var large = end - start > 0.5 ? 1 : 0;
    return 'M ' + (60 + r * Math.cos(a0)) + ' ' + (60 + r * Math.sin(a0)) + ' A ' + r + ' ' + r + ' 0 ' + large + ' 1 ' + (60 + r * Math.cos(a1)) + ' ' + (60 + r * Math.sin(a1));
  }
  function BudgetGauge(props) {
    var t = props.total, cur = props.currency;
    var sp = Math.min(1, props.spent / t), rs = Math.min(1 - sp, (props.reserved || 0) / t), fc = Math.min(1.2, (props.forecast || 0) / t);
    var state = fc > 1 ? 'over' : fc > 0.92 ? 'tight' : 'ok';
    var stateLabel = { ok: 'On track', tight: 'Tight', over: 'Over budget' }[state];
    return h('div', { className: 'av-gauge av-gauge--' + state, role: 'img', 'aria-label': money(props.spent, cur) + ' of ' + money(t, cur) + ' spent, ' + money(props.reserved || 0, cur) + ' reserved, forecast ' + money(props.forecast, cur) + '. ' + stateLabel + '.' },
      h('svg', { viewBox: '0 0 120 120', width: 132, height: 132, 'aria-hidden': 'true' },
        h('circle', { cx: 60, cy: 60, r: 48, className: 'av-gauge__track' }),
        sp > 0 ? h('path', { d: arc(48, 0, Math.max(0.001, sp)), className: 'av-gauge__spent' }) : null,
        rs > 0 ? h('path', { d: arc(48, sp, sp + rs), className: 'av-gauge__reserved' }) : null,
        h('path', { d: arc(56, 0, Math.min(0.999, fc)), className: 'av-gauge__forecast' })),
      h('div', { className: 'av-gauge__center' },
        h('span', { className: 'caption av-muted' }, 'Remaining'),
        h('span', { className: 'mono-l' }, money(t - props.spent - (props.reserved || 0), cur)),
        h('span', { className: 'caption av-gauge__state' }, stateLabel)),
      h('dl', { className: 'av-gauge__legend caption' },
        h('div', null, h('dt', null, h('i', { className: 'sw sw--spent' }), 'Spent'), h('dd', { className: 'mono-s' }, money(props.spent, cur))),
        h('div', null, h('dt', null, h('i', { className: 'sw sw--reserved' }), 'Reserved'), h('dd', { className: 'mono-s' }, money(props.reserved || 0, cur))),
        h('div', null, h('dt', null, h('i', { className: 'sw sw--forecast' }), 'Forecast'), h('dd', { className: 'mono-s' }, money(props.forecast, cur), h(ProvenanceTag, { kind: 'est' })))));
  }

  // ------------------------------------------------------------ LocationFitMeter
  function LocationFitMeter(props) {
    return h('div', { className: 'av-fit' },
      h('div', { className: 'av-fit__row' },
        h('span', { className: 'label' }, 'Location fit'),
        h('span', { className: 'mono-l' }, props.score + '%')),
      h('div', { className: 'av-fit__track', role: 'meter', 'aria-valuemin': 0, 'aria-valuemax': 100, 'aria-valuenow': props.score, 'aria-label': 'Location fit ' + props.score + ' percent' },
        h('span', { className: 'av-fit__fill', style: { width: props.score + '%' } })),
      props.sentence ? h('p', { className: 'body-m av-muted' }, props.sentence) : null);
  }

  // ------------------------------------------------------------ BoardingPassCard
  var KIND_ICON = { flight: 'plane', stay: 'bed', bus: 'bus', rail: 'train' };
  function BoardingPassCard(props) {
    return h('article', { className: cx('av-pass', 'av-pass--' + (props.status || 'confirmed')), 'aria-label': [props.from, 'to', props.to, props.date, props.depart, props.status, 'reference', props.reference].join(' ') },
      h('div', { className: 'av-pass__stub' },
        h('div', { className: 'av-pass__kind caption' }, h(Icon, { name: KIND_ICON[props.kind] || 'plane', size: 14 }), props.carrier),
        h('div', { className: 'av-pass__route mono-l' }, props.from, h('span', { className: 'av-pass__arrow' }, ' → '), props.to),
        h('div', { className: 'av-pass__times mono-m' }, props.depart, h('span', { className: 'av-muted' }, ' — '), props.arrive),
        h('div', { className: 'caption av-muted' }, props.date)),
      h('div', { className: 'av-pass__perf', 'aria-hidden': 'true' }),
      h('div', { className: 'av-pass__main' },
        h('div', { className: 'av-pass__chips' },
          h(StatusChip, { tone: props.status || 'confirmed' }),
          props.sandbox ? h(StatusChip, { tone: 'sandbox' }) : null),
        h('div', null, h('span', { className: 'caption av-muted' }, 'Reference'), h('div', { className: 'mono-m' }, props.reference)),
        props.note ? h('p', { className: 'caption av-muted' }, props.note) : null));
  }

  // ------------------------------------------------------------ PriceBreakdown
  function PriceBreakdown(props) {
    var cur = props.currency;
    return h('section', { className: 'av-price' },
      props.changedFrom != null ? h('div', { className: 'av-price__changed', role: 'alert' },
        h(Icon, { name: 'warn', size: 16 }),
        h('div', null,
          h('strong', { className: 'label' }, 'Price changed'),
          h('div', { className: 'mono-m' }, money(props.changedFrom, cur), ' → ', money(props.total, cur)),
          h('span', { className: 'caption' }, 'Confirm the new total to continue.'))) : null,
      h('dl', { className: 'av-price__lines' },
        (props.lines || []).map(function (l) {
          return h('div', { key: l.label, className: 'av-price__line' }, h('dt', { className: 'body-m' }, l.label), h('dd', { className: 'mono-m' }, money(l.amount, cur)));
        }),
        h('div', { className: 'av-price__line av-price__total' }, h('dt', { className: 'title-m' }, 'Total · ' + cur), h('dd', { className: 'mono-l' }, money(props.total, cur)))),
      props.terms ? h('ul', { className: 'av-price__terms caption' }, props.terms.map(function (t) { return h('li', { key: t }, t); })) : null,
      props.action ? h(Button, { variant: 'primary', className: 'av-price__cta' }, props.action) : null);
  }

  // ------------------------------------------------------------ CrewConstellation
  function CrewConstellation(props) {
    var members = props.members || [];
    // members sit on an ellipse, rotated half a step so pairs of neighbours form clean edges for link labels
    var W = 320, H = 210, cxp = W / 2, cyp = H / 2 - 8;
    var n = Math.max(1, members.length);
    var pos = members.map(function (m, i) {
      var a = (i / n) * Math.PI * 2 - Math.PI / 2 + Math.PI / n;
      return { x: cxp + Math.cos(a) * 112, y: cyp + Math.sin(a) * 62 };
    });
    function star(x, y, r) {
      var pts = [];
      for (var k = 0; k < 8; k++) {
        var rr = k % 2 === 0 ? r : r * 0.42, a = (k / 8) * Math.PI * 2 - Math.PI / 2;
        pts.push((x + Math.cos(a) * rr).toFixed(1) + ',' + (y + Math.sin(a) * rr).toFixed(1));
      }
      return pts.join(' ');
    }
    return h('figure', { className: 'av-crew' },
      h('svg', { viewBox: '0 0 ' + W + ' ' + H, role: 'img', 'aria-label': props.label || 'Crew constellation' },
        (props.links || []).map(function (l, i) {
          var a = pos[l.a], b = pos[l.b];
          return h('g', { key: i },
            h('line', { x1: a.x, y1: a.y, x2: b.x, y2: b.y, className: l.conflict ? 'av-crew__conflict' : 'av-crew__shared' }),
            l.label ? h('text', { x: (a.x + b.x) / 2 + (Math.abs(a.y - b.y) > Math.abs(a.x - b.x) ? ((a.x + b.x) / 2 < cxp ? -8 : 8) : 0), y: (a.y + b.y) / 2 + (Math.abs(a.y - b.y) > Math.abs(a.x - b.x) ? 4 : ((a.y + b.y) / 2 < cyp ? -8 : 16)), className: 'av-crew__linklabel', textAnchor: Math.abs(a.y - b.y) > Math.abs(a.x - b.x) ? ((a.x + b.x) / 2 < cxp ? 'end' : 'start') : 'middle' }, l.label) : null);
        }),
        members.map(function (m, i) {
          var p = pos[i];
          return h('g', { key: m.name },
            h('polygon', { points: star(p.x, p.y, 13), style: { fill: 'var(--crew-' + (i + 1) + ')' } }),
            h('text', { x: p.x, y: p.y + 30, textAnchor: 'middle', className: 'av-crew__name' }, m.name));
        })),
      props.balance ? h('ul', { className: 'av-crew__balance' }, props.balance.map(function (b, i) {
        return h('li', { key: b.name },
          h('span', { className: 'caption' }, b.name),
          h('span', { className: 'av-crew__track' }, h('span', { className: 'av-crew__fill', style: { width: b.share + '%', background: 'var(--crew-' + (i + 1) + ')' } })),
          h('span', { className: 'caption av-muted' }, b.note));
      })) : null);
  }

  window.Arivo = Object.assign(window.Arivo || {}, {
    Button: Button,
    ProvenanceTag: ProvenanceTag,
    StatusChip: StatusChip,
    StopCard: StopCard,
    TripSpine: TripSpine,
    PulseBadge: PulseBadge,
    ChangeDiff: ChangeDiff,
    BudgetGauge: BudgetGauge,
    LocationFitMeter: LocationFitMeter,
    BoardingPassCard: BoardingPassCard,
    PriceBreakdown: PriceBreakdown,
    CrewConstellation: CrewConstellation
  });
})();
