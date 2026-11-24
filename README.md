# Kamruzzaman Akib | Portfolio

Personal portfolio of Kamruzzaman Akib, Systems Administrator in Lisbon, Portugal:
endpoint management, identity & access and cloud migration across Microsoft 365,
Google Workspace and Atlassian Cloud.

Live site: https://kamruzzaman-akib.github.io/

## Publishing

This is a GitHub Pages user site, so the repository must be named exactly
`kamruzzaman-akib.github.io` (your GitHub username followed by `.github.io`) and be
public. In Settings > Pages, set Source to "Deploy from a branch", branch `main`,
folder `/ (root)`. `index.html` must sit at the top of the repository, not inside a
subfolder. The empty `.nojekyll` file tells GitHub Pages to publish the files exactly
as they are, without running Jekyll first.

Built with plain HTML, CSS and a little JavaScript. No frameworks, no build step,
hosted for free on GitHub Pages. The design uses a light indigo and sky-blue palette
(`--accent` and `--accent-2` at the top of `assets/css/style.css`), with an optional
dark mode from the button in the header.

## Structure

| Path | What it is |
| --- | --- |
| `index.html` | The home page |
| `articles/index.html` | List of all published articles |
| `articles/*.html` | One page per article (public versions of my internal guides) |
| `articles/img/` | Screenshots for the articles at their original size, with only names, emails and company details blurred |
| `scripts/index.html` | PowerShell script library page |
| `scripts/*.ps1` | The scripts themselves, downloadable |
| `404.html` | Friendly "page not found" page |
| `.nojekyll` | Empty file: publish as-is, skip Jekyll |
| `assets/css/style.css` | Design and layout |
| `assets/js/main.js` | Menu, dark mode, email link, screenshot viewer, animations |
| `assets/img/` | Icon and link-preview image |
| `assets/Kamruzzaman_Akib_CV.pdf` | Downloadable CV |

## Articles

The guides in `articles/` started as internal knowledge-base articles I wrote at work.
The public versions have company names, colleagues' names, email addresses, internal
domains and system details removed, and screenshots are blurred where they showed
people or company information. Example addresses use Microsoft's fictional
`contoso.com` domain.

To add a new article, copy any article page in `articles/`, change the title,
description, text and images, then add a card for it in `articles/index.html`
(and optionally on the home page) and a line in `sitemap.xml`.

## Scripts

`scripts/` holds PowerShell scripts I wrote for Microsoft 365, Entra ID, Intune, OneDrive and Active Directory
administration: bulk licence assignment and removal, BitLocker recovery key export,
listing a user's group memberships, exporting, importing and deleting Entra ID groups
for a tenant-to-tenant move, exporting OneDrive files, and creating Active Directory
users from a template. Most use the Microsoft Graph PowerShell SDK; the rest use the
SharePoint Online and ActiveDirectory modules. They include comment-based help
(`Get-Help .\Script.ps1 -Full`) and support `-WhatIf` where they change anything.
Personal paths have been removed. Test them in a non-production tenant first.

To add a script, put the `.ps1` file in `scripts/`, add an entry for it in
`scripts/index.html` (and optionally a card in the Scripts section of `index.html`).
