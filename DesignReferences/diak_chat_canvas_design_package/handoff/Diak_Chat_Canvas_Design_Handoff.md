# Diak Chat + Canvas Design Handoff

## Overview
This package contains the **five new Diak Mac app screens** requested for the chat + canvas workspace:

1. Document
2. Browser
3. Code
4. Board
5. Design

The screens follow the same visual direction as the earlier Diak/Hermes package: a clean Mac-native shell, calm spacing, thin borders, soft shadows, strong information hierarchy, and a trust-first productivity feel.

## Package contents
- `artboards/png/` — presentation-ready PNG exports
- `artboards/svg/` — import-friendly SVG artboards
- `tokens/` — JSON + CSS design tokens
- `screen_manifest.json` — metadata for each artboard
- `index.html` — local gallery preview
- `Diak_Chat_Canvas_All_Screens_Contact_Sheet.png` — all-screen preview sheet
- `handoff/Diak_Chat_Canvas_Design_Handoff.md` — this handoff file
- `figma_plugin/` — lightweight helper plugin stub + instructions

## Screens included

### 1. Chat + Canvas — Document
- Size: 1586 × 992
- Purpose: Dual-pane workspace with chat on the left and a structured project document canvas on the right.

### 2. Chat + Canvas — Browser
- Size: 1586 × 992
- Purpose: Dual-pane workspace with live browser research, captured notes, and source links inside the canvas.

### 3. Chat + Canvas — Code
- Size: 1586 × 992
- Purpose: Developer-focused dual-pane workspace with a repository tree, editor tabs, and code diff view.

### 4. Chat + Canvas — Board
- Size: 1586 × 992
- Purpose: Project-planning board view with milestones in chat and kanban execution inside the canvas.

### 5. Chat + Canvas — Design
- Size: 1586 × 992
- Purpose: Design canvas view showing generated images, variations, prompt controls, and design-side properties.

## Layout system
- Left navigation sidebar for app-level destinations and recent threads
- Center chat pane for prompting, reasoning, tool activity, and agent progress
- Right canvas pane for persistent work outputs
- Right utility rail for contextual properties, comments, activity, assets, and versions

## Design tab behavior
The new **Design** tab sits directly after **Code** in the canvas tab row. It is designed as a true creative workspace surface where image generations, variations, prompts, assets, comments, and property controls can all live in one place.

## Engineering notes
- Recommended font stack: Inter / SF Pro
- Recommended desktop target size for implementation preview: 1586×992 reference artboard
- Use split-view resizing between chat and canvas
- Canvas tab system order: Document → Browser → Code → Design → Board
- Buttons and pills use soft 12–16 px corner radii with restrained blue primary actions

## Figma import note
A native `.fig` export is not available in this environment. The included SVG artboards can be imported directly into Figma. A lightweight plugin stub is included only as a convenience reminder. For actual handoff, the quickest path is:
1. Open Figma Desktop
2. Create a new file
3. Drag in the SVG artboards from `artboards/svg/`
4. Organize them as pages or frames
5. Save/export as needed
