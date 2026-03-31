#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import process from "node:process";

const cwd = process.cwd();
const latestTag =
  git(["tag", "--list", "zig-v*", "--sort=-version:refname"]).split(/\r?\n/).filter(Boolean)[0] ??
  "unreleased";
const headShort = git(["rev-parse", "--short", "HEAD"]) || "unknown";
const headSubject = git(["log", "-1", "--pretty=%s"]) || "unknown";
const recent = git([
  "log",
  "--max-count=5",
  "--pretty=format:%h%x09%s",
  "--perl-regexp",
  "--grep=^(feat|fix|refactor|docs|chore)\\(zig(?:/[^)]*)?\\):",
]);

console.log(`Latest zig tag: ${latestTag}`);
console.log(`Current head: ${headShort} ${headSubject}`);
console.log("Recommended commit style: feat(zig[/layer]): ... / fix(zig[/layer]): ... / docs(zig): ...");
console.log("");
console.log("Recent zig-native commits:");

if (!recent) {
  console.log("- none");
  process.exit(0);
}

for (const line of recent.split(/\r?\n/).filter(Boolean)) {
  const [hash, subject] = line.split("\t");
  console.log(`- ${hash} ${subject}`);
}

function git(args) {
  try {
    return execFileSync("git", args, {
      cwd,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return "";
  }
}
