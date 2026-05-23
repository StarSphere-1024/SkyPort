import { execFileSync } from "node:child_process";
import { readdirSync, statSync, writeFileSync } from "node:fs";
import { basename, join } from "node:path";

const [tagName, outputPath = "release_notes.md", artifactsDir = "artifacts"] =
  process.argv.slice(2);
const repo = process.env.GITHUB_REPOSITORY;

if (!tagName) {
  throw new Error(
    "Usage: generate-release-notes.mjs <tag> [output] [artifacts-dir]",
  );
}

if (!repo) {
  throw new Error("GITHUB_REPOSITORY is required");
}

const downloads = {
  Windows: [],
  macOS: [],
  Linux: [],
  Other: [],
};

function listFiles(directory) {
  return readdirSync(directory)
    .flatMap((entry) => {
      const path = join(directory, entry);
      return statSync(path).isDirectory() ? listFiles(path) : [path];
    })
    .sort();
}

function detectArchitecture(filename) {
  if (filename.includes("amd64")) return "x64";
  if (filename.includes("arm64")) return "ARM64";
  return "Universal";
}

function badge(label, arch, color, logo, filename) {
  const encodedArch = encodeURIComponent(arch);
  const assetUrl = `https://github.com/${repo}/releases/download/${tagName}/${filename}`;
  const badgeUrl = `https://img.shields.io/badge/${label}-${encodedArch}-${color}?logo=${logo}`;
  return `[![${label}](${badgeUrl})](${assetUrl})`;
}

function addDownload(os, label, arch, color, logo, filename) {
  downloads[os].push(badge(label, arch, color, logo, filename));
}

for (const file of listFiles(artifactsDir)) {
  const filename = basename(file);
  let arch = detectArchitecture(filename);

  if (filename.includes("windows") && filename.endsWith("setup.exe")) {
    addDownload("Windows", "Installer", arch, "blue", "windows", filename);
  } else if (
    filename.includes("windows") &&
    filename.endsWith("portable.zip")
  ) {
    addDownload("Windows", "Portable", arch, "blue", "windows", filename);
  } else if (filename.includes("macos") && filename.endsWith(".dmg")) {
    if (arch === "ARM64") arch = "Apple Silicon";
    addDownload("macOS", "DMG", arch, "black", "apple", filename);
  } else if (filename.includes("linux") && filename.endsWith(".deb")) {
    addDownload("Linux", "DEB", arch, "orange", "linux", filename);
  } else if (filename.includes("linux") && filename.endsWith(".AppImage")) {
    addDownload("Linux", "AppImage", arch, "orange", "linux", filename);
  } else {
    const assetUrl = `https://github.com/${repo}/releases/download/${tagName}/${filename}`;
    downloads.Other.push(`[${filename}](${assetUrl})`);
  }
}

function generatedNotes() {
  return execFileSync(
    "gh",
    [
      "api",
      `repos/${repo}/releases/generate-notes`,
      "-f",
      `tag_name=${tagName}`,
      "--jq",
      ".body",
    ],
    { encoding: "utf8" },
  ).trimEnd();
}

function renderDownloadTable() {
  const rows = Object.entries(downloads)
    .filter(([, links]) => links.length > 0)
    .map(([os, links]) => `| ${os} | ${links.join(" ")} |`);

  return `| OS | Download |
| --- | --- |
${rows.join("\n")}`;
}

const body = `${generatedNotes()}

# Download based on your OS:

${renderDownloadTable()}
`;

writeFileSync(outputPath, body);
