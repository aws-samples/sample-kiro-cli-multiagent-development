---
name: aws-technical-docs
description: AWS technical documentation patterns covering procedures, lists, tables, titles, error messages, and content patterns. Use when writing AWS service documentation, procedures, troubleshooting guides, tutorials, or getting started content.
---

# AWS technical documentation

Apply these rules when writing AWS technical documentation. Follow the general `aws-writing-style` skill for voice, tone, and word usage. For the complete guide, see the [AWS documentation style guide](https://docs.aws.amazon.com/style-guide/latest/styleguide/).

## Titles and headings

- Sentence case for titles, headings, and subheadings.
- 50–60 characters recommended for SEO.
- Don't begin with an article (a, an, the).
- Don't stack headings — include explanatory text between them.
- Conceptual topics: noun phrase + preposition + service name ("Access control in Amazon S3").
- Procedural topics: present participle + preposition + service name ("Creating a bucket in Amazon S3").
- Procedure titles: infinitive phrase ("To create a bucket").

## Procedures

### Section title

- Use a gerund phrase ("Creating a domain"). Sentence case.
- Use parentheses to differentiate console, AWS CLI, and SDK procedures.

### Procedure title

- Use an infinitive phrase ("To restrict access to a resource").
- Sentence case. No end punctuation.

### Steps

- One main action per step. Active voice. Imperative verb.
- First step: locate the reader in the console ("Sign in to the AWS Management Console and open the Amazon RDS console at https://console.aws.amazon.com/rds/.")
- Subsequent steps: start with where, then what ("For Actions, choose Create.")
- Begin optional steps with "(Optional)".
- Limit to seven steps. Break longer procedures into multiple ones.

### Procedure phrasing

- **choose** — for buttons, menus, tabs, panes
- **select** — for picking resources or enabling options
- **clear** — for turning off previously selected options
- **press** — for keyboard keys
- **enter** — for text input
- **turn on/turn off** — for toggle switches
- Don't use: click, hit, strike

## Lists

- Introduce every list with a complete sentence.
- End introductory sentence with a colon (if no list title) or period (if list has a title).
- Make list items parallel in structure.
- Capitalize the first word of each item.
- Punctuate consistently — if one item needs a period, use periods for all.
- Alphabetize items when order is arbitrary.
- Use bulleted lists for unordered items.
- Use numbered lists for sequential items (not procedures).
- Use procedures for steps a reader must complete.

## Tables

- Include a lead-in sentence before every table (complete sentence, no colon).
- Use sentence case for column headings.
- Don't leave cells empty — use "Not applicable" or "None."
- Don't use tables for styling, lists, or two-column layouts.
- Keep tables simple for accessibility — no rowspans, no colored cells.

## Error messages

Structure: heading (summary or error code) + body (what happened, why, how to fix, link to help).

- Keep to 1–3 sentences.
- Use straightforward language, not cryptic codes.
- Use PascalCase for error codes (ErrorCodeNotFound).
- Don't use "please," "sorry," or exclamation points.
- Don't blame the user.
- Use positive language: "You can link an instance to only one VPC" instead of "You can't link an instance to more than one VPC."
- Validation errors: "[label] is required" or "Enter a valid [label]."
- Quota errors: "You've reached the quota for [resource]. You can create up to [number]."

## Notes and alerts

- **Tip** — optional shortcut or best practice. Not essential.
- **Note** — special interest information. No risk if ignored.
- **Important** — essential for task completion.
- **Warning** — irreversible or damaging actions. Place before the affected step.
- Don't stack notes. Avoid notes in tables, lists, or procedures.

## Links and cross-references

- Use formal cross-references: "For more information about [topic], see [link text]."
- Don't use "click here," "here," "go to," or "For information on."
- Use "For instructions on" or "For instructions for" when linking to procedures.
- Use "following," "preceding," "previous," or "earlier" for same-page references — not "above" or "below."
- Link text must match the destination page title.
- Link only the first instance on a page.

## Content patterns

### Getting started

- Clear, action-oriented title. Include time and cost to complete.
- Prerequisites, numbered steps, next steps.
- Use best practices and latest security guidance.

### Procedure

- Title, short description, numbered steps, expected results.
- One action per step. Start with where, then what.
- Limit to 5–7 steps per procedure.

### Tutorial

- Title containing "Tutorial." Overview with learning objectives.
- Time and cost to complete. Prerequisites.
- Numbered steps. Cleanup steps to avoid charges.

### Troubleshooting

- Exact error message or clear problem description as title.
- Common cause explanation. Step-by-step resolution.
- Optional: prevention guidance.

## Images and screenshots

- Use screenshots sparingly. Written content must be comprehensible without images.
- All images require alt text (maximum 125 characters). Don't start with "Screenshot of."
- Write lead-in content before images to provide context.
- Don't use screenshots for code, tables, or text that must be read.

## Accessibility

- Use device-agnostic verbs (choose, not click).
- Don't reference color, shape, or sound alone.
- Use "preceding" or "following" — not "above" or "below."
- Refer to UI elements by their label text.
