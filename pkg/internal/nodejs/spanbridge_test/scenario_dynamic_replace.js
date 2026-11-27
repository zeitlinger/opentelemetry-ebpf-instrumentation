'use strict';

const fs = require('fs');
const path = require('path');
const emitted = [];
const realExistsSync = fs.existsSync;
fs.existsSync = (pathname, ...rest) => {
  if (typeof pathname === 'string' && pathname.startsWith('/dev/null/obi-span/')) {
    emitted.push(JSON.parse(pathname.slice('/dev/null/obi-span/'.length)).name);
    return false;
  }
  return realExistsSync(pathname, ...rest);
};

globalThis.__obiSpanBridge = {
  withSpan(name, fn, thisArg, args) {
    emitted.push(name);
    return Reflect.apply(fn, thisArg, args || []);
  },
};

const loaded = require('./scenario_dynamic_replace_module');
const source = fs.readFileSync(path.join(__dirname, '..', 'dynamic_spans.js'), 'utf8');
const apply = (rules) => {
  // eslint-disable-next-line no-eval
  eval(source.replace('__OBI_DYNAMIC_SPAN_RULES__', JSON.stringify(rules)));
};
const rule = (name) => ({ name, reference: `${require.resolve('./scenario_dynamic_replace_module')}:exports.work` });

apply([rule('first')]);
const retained = loaded.work;
retained();
apply([rule('second')]);
retained();
apply([rule('second')]); // retry must not duplicate spans
retained();
apply([]); // empty is an authoritative clear
retained();

fs.existsSync = realExistsSync;
process.stdout.write(JSON.stringify({ emitted }));
