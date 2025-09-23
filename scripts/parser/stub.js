#!/usr/bin/env node
// Minimal stub parser: extracts match_id from filename and writes a skeleton JSON

const fs = require('fs');
const path = require('path');

function arg(name){
  const ix = process.argv.indexOf(name);
  if(ix === -1 || ix+1 >= process.argv.length) return null;
  return process.argv[ix+1];
}

const inPath = arg('--in');
const outPath = arg('--out');
if(!inPath || !outPath){
  console.error('Usage: node scripts/parser/stub.js --in <file.dem[.bz2]> --out <file.json>');
  process.exit(2);
}

const base = path.basename(inPath);
const m = base.match(/^(\d+)/);
const match_id = m ? Number(m[1]) : null;

const out = {
  match_id,
  generated_at: new Date().toISOString(),
  source: 'stub',
  wards: [],
  item_first_purchase: [],
  stacks: [],
  smokes: [],
  objectives: [],
  camps: { stacked: [], blocked: [], farmed: [] },
  farming: []
};

fs.mkdirSync(path.dirname(outPath), { recursive: true });
fs.writeFileSync(outPath, JSON.stringify(out));
