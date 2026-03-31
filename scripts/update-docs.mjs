#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";

const root = process.cwd();
const checkOnly = process.argv.includes("--check");
const manifestPath = path.join(root, "automation", "progress.json");
const manifest = JSON.parse(await fs.readFile(manifestPath, "utf8"));
const gitMeta = collectGitMeta(root);

let changed = false;

const progressPath = path.join(root, "PROGRESS.md");
await writeFile(progressPath, replaceToc(renderProgress(manifest, gitMeta)));

const layersPath = path.join(root, "LAYERS.md");
await writeFile(layersPath, replaceToc(renderLayers(manifest, gitMeta)));

const readmePath = path.join(root, "README.md");
const readmeCurrent = await fs.readFile(readmePath, "utf8");
const readmeWithStatus = replaceSection(
  readmeCurrent,
  "<!-- zig-rewrite:start -->",
  "<!-- zig-rewrite:end -->",
  buildStatusBlock(manifest, gitMeta),
);
await writeFile(readmePath, replaceToc(readmeWithStatus));

const zigReadmePath = path.join(root, "zig", "README.md");
const zigReadmeCurrent = await fs.readFile(zigReadmePath, "utf8");
await writeFile(zigReadmePath, replaceToc(zigReadmeCurrent));

if (checkOnly && changed) {
  console.error("Generated docs are out of date. Run: npm run docs:sync");
  process.exit(1);
}

async function writeFile(file, next) {
  let current = "";
  try {
    current = await fs.readFile(file, "utf8");
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }

  if (current === next) return;
  changed = true;
  if (!checkOnly) {
    await fs.writeFile(file, next);
  }
}

function renderProgress(data, git) {
  const { project, milestones, verification, next } = data;
  const generatedAt = new Date().toISOString().slice(0, 10);

  const board = [
    "| Area | Status | Notes |",
    "| --- | --- | --- |",
    ...milestones.map(
      (item) =>
        `| ${escapePipes(item.name)} | ${statusLabel(item.status)} | ${escapePipes(item.details)} |`,
    ),
  ].join("\n");

  const verificationList = verification
    .map((item) => `- \`${item.command}\`: ${item.purpose}`)
    .join("\n");

  const nextList = next.map((item) => `- ${item}`).join("\n");

  return `# Progress

Generated from \`automation/progress.json\` on ${generatedAt}.

## Contents
<!-- toc:start -->
<!-- toc:end -->

## Overview

${project.summary}

- Status: \`${project.status}\`
- Docs: [README](${project.docs.readme}), [zig/README](${project.docs.zig_readme}), [PROGRESS](${project.docs.progress}), [LAYERS](${project.docs.layers}), [OpenSpec](${project.docs.openspec_readme})
- Planning: [project](${project.docs.openspec_project}), [active change](${project.docs.openspec_change})
- Release Strategy: ${project.release.strategy}
- Latest Zig Tag: \`${git.latestTag}\`
- Commit Style: ${project.release.commit_style}

## Status Board

${board}

## Verification

${verificationList}

## Next

${nextList}
`;
}

function renderLayers(data, git) {
  const { project, layers, next } = data;
  const generatedAt = new Date().toISOString().slice(0, 10);

  const layerBoard = [
    "| Layer | Status | Paths | Shipped | Next |",
    "| --- | --- | --- | --- | --- |",
    ...layers.map(
      (layer) =>
        `| ${escapePipes(layer.name)} | ${statusLabel(layer.status)} | ${escapePipes(layer.paths.join("<br>"))} | ${escapePipes(layer.shipped)} | ${escapePipes(layer.next)} |`,
    ),
  ].join("\n");

  const scopes = project.release.scopes.map((scope) => `- \`${scope}\``).join("\n");
  const nextList = next.map((item) => `- ${item}`).join("\n");

  return `# Layers

Generated from \`automation/progress.json\` and local git state on ${generatedAt}.

## Contents
<!-- toc:start -->
<!-- toc:end -->

## Release Line

- Latest Zig Tag: \`${git.latestTag}\`
- Tag Format: \`${project.release.tag_format}\`
- Commit Style: ${project.release.commit_style}
- Live Status: Run \`npm run release:status\` for the current head commit and recent Zig-native commit subjects.

## Layer Map

${layerBoard}

## Commit Scopes

${scopes}

## Immediate Order

${nextList}
`;
}

function buildStatusBlock(data, git) {
  const counts = countStatuses(data.milestones);
  const verifyCommands = data.verification.slice(0, 3).map((item) => `\`${item.command}\``).join(", ");
  return `- Status: \`${data.project.status}\`
- Rewrite Summary: ${data.project.summary}
- Progress Board: ${counts.done} done, ${counts.in_progress} in progress, ${counts.planned} planned
- Docs: [zig/README.md](./zig/README.md), [PROGRESS.md](./PROGRESS.md), [LAYERS.md](./LAYERS.md), [openspec/README.md](./openspec/README.md)
- Planning: [openspec/project.md](./openspec/project.md), [openspec/changes/rewrite-bubbletea-in-zig](./openspec/changes/rewrite-bubbletea-in-zig)
- Latest Zig Tag: \`${git.latestTag}\`
- Default Verification: ${verifyCommands}
- Release Flow: ${data.project.release.strategy}
- Commit Discipline: ${data.project.release.commit_style}`;
}

function replaceToc(content) {
  return replaceSection(
    content,
    "<!-- toc:start -->",
    "<!-- toc:end -->",
    buildToc(content),
  );
}

function buildToc(content) {
  const headings = extractHeadings(content);
  return headings
    .filter((heading) => heading.text.toLowerCase() !== "contents")
    .map((heading) => {
      const depth = Math.max(0, heading.level - 2);
      const indent = "  ".repeat(depth);
      return `${indent}- [${heading.text}](#${slugify(heading.text)})`;
    })
    .join("\n");
}

function extractHeadings(content) {
  const lines = content.split(/\r?\n/);
  const headings = [];
  let inFence = false;
  let inToc = false;

  for (const line of lines) {
    if (line.startsWith("```")) {
      inFence = !inFence;
      continue;
    }

    if (line.includes("<!-- toc:start -->")) {
      inToc = true;
      continue;
    }
    if (line.includes("<!-- toc:end -->")) {
      inToc = false;
      continue;
    }
    if (inFence || inToc) continue;

    const match = /^(###{0,3})\s+(.+?)\s*$/.exec(line);
    if (!match) continue;

    const level = match[1].length;
    if (level < 2) continue;
    headings.push({
      level,
      text: normalizeHeading(match[2]),
    });
  }

  return headings;
}

function normalizeHeading(text) {
  return text
    .replace(/\[(.*?)\]\(.*?\)/g, "$1")
    .replace(/`/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

function slugify(text) {
  return normalizeHeading(text)
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, "")
    .trim()
    .replace(/\s+/g, "-");
}

function replaceSection(content, startMarker, endMarker, replacement) {
  const start = content.indexOf(startMarker);
  const end = content.indexOf(endMarker);
  if (start === -1 || end === -1 || end < start) {
    throw new Error(`Missing markers ${startMarker} / ${endMarker}`);
  }

  const before = content.slice(0, start + startMarker.length);
  const after = content.slice(end);
  return `${before}\n${replacement}\n${after}`;
}

function countStatuses(items) {
  return items.reduce(
    (acc, item) => {
      acc[item.status] = (acc[item.status] ?? 0) + 1;
      return acc;
    },
    { done: 0, in_progress: 0, planned: 0 },
  );
}

function statusLabel(status) {
  switch (status) {
    case "done":
      return "Done";
    case "in_progress":
      return "In Progress";
    case "planned":
      return "Planned";
    default:
      return status;
  }
}

function escapePipes(value) {
  return String(value).replace(/\|/g, "\\|");
}

function collectGitMeta(cwd) {
  const latestTag =
    git(cwd, ["tag", "--list", "zig-v*", "--sort=-version:refname"]).split(/\r?\n/).filter(Boolean)[0] ??
    "unreleased";

  return {
    latestTag,
  };
}

function git(cwd, args) {
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
