import starlight from "@astrojs/starlight";
import a11yEmoji from "@fec/remark-a11y-emoji";
import { defineConfig } from "astro/config";
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
		starlight({
			title: "lattice",
			editLink: {
				baseUrl:
					"https://github.com/tylerbutler/lattice/edit/main/website/",
			},
			description:
				"Conflict-free replicated data types (CRDTs) for Gleam.",
			lastUpdated: true,
			logo: {
				src: "./src/assets/lattice-min.webp",
				alt: "lattice logo",
			},
			customCss: [
				"@fontsource/metropolis/400.css",
				"@fontsource/metropolis/600.css",
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
					],
				},
				{
					label: "Advanced",
					items: [
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
