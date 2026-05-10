# Hermes Desktop Figma Importer

This local development plugin creates editable Figma pages from the SVG artboards in this package.

## Use
1. Open Figma Desktop.
2. Go to **Plugins → Development → Import plugin from manifest…**
3. Select `figma_plugin/manifest.json`.
4. Run **Hermes Desktop Design Importer**.
5. Figma will create pages for full app screens, modals/sheets, responsive modes, and system states.
6. Use **File → Save local copy** or export from Figma to create a native `.fig` file.

Note: this environment cannot directly write Figma's proprietary `.fig` binary. The plugin recreates the design in Figma as editable layers/groups so you can save/export the final `.fig` from Figma.
