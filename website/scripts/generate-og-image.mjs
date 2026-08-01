#!/usr/bin/env node
// Regenerates public/og-image.png from scripts/og-template.html.
// The template references fonts and the logo via __BRICO__/__ATK__/__LOGO__
// placeholders so the committed template stays small; this script inlines
// them as base64 data URIs and screenshots the page at 1200x630.
//
// Usage: pnpm generate:og
// Requires the playwright chromium browser (pnpm exec playwright install chromium).

import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const siteRoot = join(dirname(fileURLToPath(import.meta.url)), "..");

const WIDTH = 1200;
const HEIGHT = 630;
const OUTPUT = join(siteRoot, "public/og-image.png");

const ASSETS = {
	__BRICO__: join(
		siteRoot,
		"node_modules/@fontsource/bricolage-grotesque/files/bricolage-grotesque-latin-700-normal.woff2",
	),
	__ATK__: join(
		siteRoot,
		"node_modules/@fontsource/atkinson-hyperlegible/files/atkinson-hyperlegible-latin-400-normal.woff2",
	),
	__LOGO__: join(siteRoot, "src/assets/lattice.png"),
};

let chromium;
try {
	({ chromium } = await import("playwright"));
} catch {
	console.error(
		"playwright is not installed. Run: pnpm install && pnpm exec playwright install chromium",
	);
	process.exit(1);
}

let html = await readFile(join(siteRoot, "scripts/og-template.html"), "utf8");
for (const [placeholder, path] of Object.entries(ASSETS)) {
	html = html.replace(placeholder, (await readFile(path)).toString("base64"));
}

const workDir = await mkdtemp(join(tmpdir(), "og-image-"));
const htmlPath = join(workDir, "og.html");
await writeFile(htmlPath, html);

try {
	const browser = await chromium.launch();
	try {
		const page = await browser.newPage({
			viewport: { width: WIDTH, height: HEIGHT },
		});
		await page.goto(pathToFileURL(htmlPath).href);
		await page.evaluate(() => document.fonts.ready);
		await page.screenshot({ path: OUTPUT });
	} finally {
		await browser.close();
	}
} finally {
	await rm(workDir, { recursive: true, force: true });
}

console.log(`Wrote ${OUTPUT} (${WIDTH}x${HEIGHT})`);
