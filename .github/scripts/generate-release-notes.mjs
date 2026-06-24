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
  Windows: new Map(),
  Linux: new Map(),
  macOS: new Map(),
  Other: new Map(),
};

const osOrder = ["Windows", "Linux", "macOS", "Other"];
const archOrder = ["x64", "ARM64", "Universal", "-"];
const downloadOrder = {
  Windows: ["Portable", "Installer"],
  Linux: ["AppImage", "DEB", "RPM"],
  macOS: ["DMG"],
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
  const lowerName = filename.toLowerCase();
  if (
    lowerName.includes("amd64") ||
    lowerName.includes("x86_64") ||
    lowerName.includes("x64")
  ) {
    return "x64";
  }
  if (lowerName.includes("arm64") || lowerName.includes("aarch64")) {
    return "ARM64";
  }
  return "Universal";
}

function badge(label, arch, color, logo, filename) {
  const encodedArch = encodeURIComponent(arch);
  const assetUrl = `https://github.com/${repo}/releases/download/${tagName}/${filename}`;
  const badgeUrl = `https://img.shields.io/badge/${label}-${encodedArch}-${color}?logo=${logo}`;
  return `[![${label}](${badgeUrl})](${assetUrl})`;
}

function textLink(label, filename) {
  const assetUrl = `https://github.com/${repo}/releases/download/${tagName}/${filename}`;
  return `[${label}](${assetUrl})`;
}

function addDownload(os, label, arch, color, logo, filename) {
  if (!downloads[os].has(arch)) {
    downloads[os].set(arch, []);
  }
  downloads[os].get(arch).push({ label, color, logo, filename });
}

for (const file of listFiles(artifactsDir)) {
  const filename = basename(file);
  const lowerName = filename.toLowerCase();
  const arch = detectArchitecture(filename);

  if (lowerName.includes("windows") && lowerName.endsWith("setup.exe")) {
    addDownload("Windows", "Installer", arch, "blue", "windows", filename);
  } else if (
    lowerName.includes("windows") &&
    lowerName.endsWith("portable.zip")
  ) {
    addDownload("Windows", "Portable", arch, "blue", "windows", filename);
  } else if (lowerName.includes("macos") && lowerName.endsWith(".dmg")) {
    addDownload("macOS", "DMG", arch, "black", "apple", filename);
  } else if (lowerName.includes("linux") && lowerName.endsWith(".deb")) {
    addDownload("Linux", "DEB", arch, "orange", "linux", filename);
  } else if (lowerName.includes("linux") && lowerName.endsWith(".rpm")) {
    addDownload("Linux", "RPM", arch, "orange", "linux", filename);
  } else if (lowerName.includes("linux") && lowerName.endsWith(".appimage")) {
    addDownload("Linux", "AppImage", arch, "orange", "linux", filename);
  } else {
    addDownload("Other", filename, "-", null, null, filename);
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

function orderedIndex(values, value) {
  const index = values.indexOf(value);
  return index === -1 ? values.length : index;
}

function renderDownloadTable() {
  const rows = [];

  for (const os of osOrder) {
    const archEntries = [...downloads[os].entries()].sort(
      ([leftArch], [rightArch]) =>
        orderedIndex(archOrder, leftArch) - orderedIndex(archOrder, rightArch),
    );

    archEntries.forEach(([arch, links], index) => {
      const orderedLinks = links
        .sort(
          (left, right) =>
            orderedIndex(downloadOrder[os], left.label) -
            orderedIndex(downloadOrder[os], right.label),
        )
        .map(({ label, color, logo, filename }) =>
          color && logo
            ? badge(label, arch, color, logo, filename)
            : textLink(label, filename),
        )
        .join(" ");
      rows.push(`| ${index === 0 ? os : ""} | ${arch} | ${orderedLinks} |`);
    });
  }

  return `| OS | Architecture | Download |
| --- | --- | --- |
${rows.join("\n")}`;
}

const body = `${generatedNotes()}

# Download based on your OS:

${renderDownloadTable()}
`;

writeFileSync(outputPath, body);
