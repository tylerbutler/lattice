import starlight from "@astrojs/starlight";
import a11yEmoji from "@fec/remark-a11y-emoji";
import { defineConfig } from "astro/config";
import mermaid from "astro-mermaid";
import starlightLinksValidator from "starlight-links-validator";
import starlightLlmsTxt from "starlight-llms-txt";

// https://astro.build/config
export default defineConfig({
	site: "https://lattice.tylerbutler.com",
	prefetch: {
		defaultStrategy: "hover",
		prefetchAll: true,
	},
	integrations: [
		mermaid(),
		starlight({
			title: "lattice",
			favicon: "/favicon.png",
			editLink: {
				baseUrl:
					"https://github.com/tylerbutler/lattice/edit/main/website/",
			},
			description:
				"Conflict-free replicated data types (CRDTs) for Gleam.",
			lastUpdated: true,
			logo: {
				src: "./src/assets/lattice-min.webp",
				alt: "lattice geometric knot mark",
			},
			components: {
				Head: "./src/components/Head.astro",
				MobileTableOfContents:
					"./src/components/MobileTableOfContents.astro",
				MobileMenuToggle: "./src/components/MobileMenuToggle.astro",
				PageTitle: "./src/components/PageTitle.astro",
				TableOfContents: "./src/components/TableOfContents.astro",
			},
			customCss: [
				"@fontsource/atkinson-hyperlegible/400.css",
				"@fontsource/atkinson-hyperlegible/700.css",
				"@fontsource/bricolage-grotesque/600.css",
				"@fontsource/bricolage-grotesque/700.css",
				"./src/styles/fonts.css",
				"./src/styles/custom.css",
			],
			plugins: [
				starlightLlmsTxt(),
				starlightLinksValidator(),
			],
			social: [
				{
					icon: "github",
					label: "GitHub",
					href: "https://github.com/tylerbutler/lattice",
				},
			],
			sidebar: [
				{
					label: "Start Here",
					items: [
						{
							label: "What is lattice?",
							slug: "introduction",
						},
						{
							label: "Packages",
							slug: "packages",
						},
						{
							label: "Installation",
							slug: "installation",
						},
						{
							label: "Quick Start",
							slug: "quick-start",
						},
					],
				},
				{
					label: "Guides",
					items: [
						{
							label: "Replica IDs",
							slug: "guides/replica-ids",
						},
						{
							label: "Counters",
							slug: "guides/counters",
						},
						{
							label: "Registers",
							slug: "guides/registers",
						},
						{
							label: "Sets",
							slug: "guides/sets",
						},
						{
							label: "Maps",
							slug: "guides/maps",
						},
						{
							label: "Presence",
							slug: "guides/presence",
						},
					],
				},
				{
					label: "Advanced",
					items: [
						{
							label: "Delta-State Replication",
							slug: "advanced/delta-state",
						},
						{
							label: "Version Vectors",
							slug: "advanced/version-vectors",
						},
						{
							label: "JSON Serialization",
							slug: "advanced/serialization",
						},
					],
				},
			],
		}),
	],
	markdown: {
		smartypants: false,
		remarkPlugins: [
			a11yEmoji,
		],
	},
});
